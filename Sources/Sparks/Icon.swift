import AppKit

enum Palette {
    /// #8EA0FF
    static let accent = NSColor(srgbRed: 142 / 255, green: 160 / 255, blue: 255 / 255, alpha: 1)

    /// Sits on top of `accent`. The accent is light enough that white on it is
    /// only about 2.4:1 — a deep indigo gets to 6.5:1 and keeps the same family.
    static let onAccent = NSColor(srgbRed: 27 / 255, green: 33 / 255, blue: 64 / 255, alpha: 1)
}

enum Icon {
    /// Which glyph sits in the menu bar. Change this one line to swap it.
    static let variant: Variant = .sparkInBulb

    enum Variant {
        case bulbFilled           // solid bulb, spark alongside
        case bulbOutline
        case bulbMaxFilled        // bulb throwing rays, no separate spark
        case bulbMaxOutline
        case sparkInBulb          // hand-drawn bulb whose filament is the spark
        case ledBulb

        func draw() {
            switch self {
            case .bulbFilled:
                drawSymbol("lightbulb.fill", into: NSRect(x: 0.4, y: 1.2, width: 13.4, height: 13.4), weight: .regular)
                drawSpark(centre: CGPoint(x: 14.6, y: 14.4), outer: 2.8)
            case .bulbOutline:
                drawSymbol("lightbulb", into: NSRect(x: 0.4, y: 1.2, width: 13.4, height: 13.4), weight: .medium)
                drawSpark(centre: CGPoint(x: 14.6, y: 14.4), outer: 2.8)
            case .bulbMaxFilled:
                drawSymbol("lightbulb.max.fill", into: NSRect(x: 0.6, y: 0.6, width: 16.8, height: 16.8), weight: .regular)
            case .bulbMaxOutline:
                drawSymbol("lightbulb.max", into: NSRect(x: 0.6, y: 0.6, width: 16.8, height: 16.8), weight: .medium)
            case .ledBulb:
                drawSymbol("lightbulb.led.fill", into: NSRect(x: 0.4, y: 1.2, width: 13.4, height: 13.4), weight: .regular)
                drawSpark(centre: CGPoint(x: 14.6, y: 14.4), outer: 2.8)
            case .sparkInBulb:
                drawSparkInBulb()
            }
        }
    }

    /// Bulb outline with the spark sitting where the filament would be.
    static func drawSparkInBulb() {
        let glass = NSBezierPath()
        glass.appendArc(withCenter: CGPoint(x: 9, y: 10.4), radius: 5.4,
                        startAngle: -52, endAngle: 232, clockwise: false)
        glass.line(to: CGPoint(x: 5.7, y: 4.8))
        glass.line(to: CGPoint(x: 12.3, y: 4.8))
        glass.close()
        glass.lineWidth = 1.25
        glass.lineJoinStyle = .round
        glass.stroke()

        for y in [3.2, 1.5] as [CGFloat] {              // screw base
            let rung = NSBezierPath()
            rung.move(to: CGPoint(x: 6.3, y: y))
            rung.line(to: CGPoint(x: 11.7, y: y))
            rung.lineWidth = 1.25
            rung.lineCapStyle = .round
            rung.stroke()
        }
        drawSpark(centre: CGPoint(x: 9, y: 10.6), outer: 3.5)
    }

    /// Template image, so the menu bar tints it for light/dark and highlight.
    static func statusItem(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.saveGState()
            ctx.scaleBy(x: size / 18, y: size / 18)          // design grid is 18x18
            NSColor.black.setStroke()
            NSColor.black.setFill()
            variant.draw()
            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Pieces

    /// Draws an SF Symbol aspect-fitted into a rect on the 18-grid.
    static func drawSymbol(_ name: String, into box: NSRect, weight: NSFont.Weight) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 64, weight: weight)
        guard let glyph = NSImage(systemSymbolName: name, accessibilityDescription: "brain")?
            .withSymbolConfiguration(cfg) else { return }
        let k = min(box.width / glyph.size.width, box.height / glyph.size.height)
        let w = glyph.size.width * k, h = glyph.size.height * k
        glyph.draw(in: NSRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h))
    }

    /// Four-pointed sparkle, filled — concave sides keep it sharp when small.
    static func drawSpark(centre c: CGPoint, outer r: CGFloat) {
        let inner = r * 0.30
        func pt(_ degrees: CGFloat, _ radius: CGFloat) -> CGPoint {
            let a = degrees * .pi / 180
            return CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
        }
        let tips: [CGFloat] = [90, 0, 270, 180]     // clockwise from the top
        let path = NSBezierPath()
        path.move(to: pt(tips[0], r))
        for i in 0..<4 {
            let waist = pt(tips[i] - 45, inner)
            path.curve(to: pt(tips[(i + 1) % 4], r), controlPoint1: waist, controlPoint2: waist)
        }
        path.close()
        path.fill()
    }

    /// Full-colour app icon, used for the .app bundle.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            let r = size * 0.2237                            // macOS squircle-ish
            let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                                  xRadius: r, yRadius: r)
            ctx.saveGState()
            bg.addClip()
            // Deeper than the UI accent so the white glyph stays legible on it.
            let grad = NSGradient(colors: [NSColor(srgbRed: 0.427, green: 0.478, blue: 0.878, alpha: 1),
                                           NSColor(srgbRed: 0.204, green: 0.239, blue: 0.612, alpha: 1)])
            grad?.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)
            ctx.restoreGState()

            // The status glyph is a template, so tint an opaque white copy of it.
            let glyph = statusItem(size: size * 0.60)
            let box = NSRect(x: 0, y: 0, width: glyph.size.width, height: glyph.size.height)
            let white = NSImage(size: glyph.size, flipped: false) { rect in
                glyph.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let inset = (size - box.width) / 2
            white.draw(in: NSRect(x: inset, y: inset, width: box.width, height: box.height))
            return true
        }
    }
}
