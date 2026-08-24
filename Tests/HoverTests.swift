import AppKit

// Moves the real cursor onto a task row from several entry points and checks
// whether the row's delete button becomes visible — i.e. whether hover fired.
@main
enum HoverTest {
    @MainActor
    static func main() {
        setvbuf(stdout, nil, _IONBF, 0)            // stream output, do not buffer
        UserDefaults.standard.removeObject(forKey: "sparks.state.v1")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))
        spin(0.6)
        HotKey.shared.onPress?()
        spin(1.2)

        guard let win = NSApp.windows.first(where: {
            "\(type(of: $0))".contains("Popover") && $0.isVisible }),
              let content = win.contentView else { print("no popover"); exit(1) }

        for t in ["Ring the notary", "Water the olive tree", "Call Mum back"] {
            delegate.store.add(t)
        }
        spin(1.0)

        let restore = NSEvent.mouseLocation

        // Find row 1 by clicking down the checkbox column until a task completes.
        var rowY: CGFloat = 0
        var y = content.bounds.height - 40
        while y > 30 {
            let before = delegate.store.completed.count
            click(win, content.convert(NSPoint(x: 23, y: y), to: nil))
            spin(0.08)
            if delegate.store.completed.count > before {
                rowY = y
                if let d = delegate.store.completed.first { delegate.store.toggle(d.id) }
                spin(0.3)
                break
            }
            y -= 2
        }
        guard rowY > 0 else {
            print("could not locate a row — open=\(delegate.store.open.count) done=\(delegate.store.completed.count) contentH=\(Int(content.bounds.height)) key=\(win.isKeyWindow)")
            exit(1)
        }
        print("row 1 centre is at content y=\(Int(rowY)); content is \(Int(content.bounds.width))pt wide\n")

        print("content isFlipped = \(content.isFlipped)\n")

        // Baseline: cursor parked well away from the panel.
        warp(toScreen: NSPoint(x: 40, y: 40))
        NSApp.activate(ignoringOtherApps: true)
        spin(0.8)
        guard let baseline = capture(content) else { print("no capture"); exit(1) }

        let probes: [(String, CGFloat)] = [
            ("over the task text",   110),
            ("top edge of row",       110),
            ("left padding, x=4",      4),
            ("left padding, x=10",    10),
            ("gap right of text",    250),
            ("right padding, x=314", 314),
            ("checkbox, x=23",        23),
        ]

        for (label, x) in probes {
            var best = 0.0
            for _ in 0..<3 {                       // cursor warps are a bit flaky
                warp(toScreen: NSPoint(x: 40, y: 40))          // leave the row first
                spin(0.4)
                warp(to: NSPoint(x: x, y: rowY), in: content)
                NSApp.activate(ignoringOtherApps: true)   // hover needs an active app
                spin(0.6)
                if let shot = capture(content) {
                    best = max(best, difference(baseline, shot))
                }
            }
            print(String(format: "%@  %-22@  pixels changed %.2f%%",
                         best > 0.4 ? "HOVER " : "  --  ", label as NSString, best))
        }

        // With the row genuinely hovered, the delete button is visible — and only
        // then is it hit-testable, since SwiftUI skips fully transparent views.
        let before = delegate.store.tasks.count
        warp(to: NSPoint(x: 110, y: rowY), in: content)
        NSApp.activate(ignoringOtherApps: true)
        spin(0.8)
        click(win, content.convert(NSPoint(x: 297, y: rowY), to: nil))
        spin(0.5)
        let removed = delegate.store.tasks.count == before - 1
        print("\n\(removed ? "ok  " : "FAIL") delete button removes a task while hovered")

        warp(toScreen: restore)
        exit(0)
    }

    // MARK: - Helpers

    @MainActor
    static func capture(_ view: NSView) -> NSBitmapImageRep? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// Percentage of pixels that differ between two captures of the same view.
    static func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
              let pa = a.bitmapData, let pb = b.bitmapData else { return 0 }
        let bytes = a.bytesPerRow * a.pixelsHigh
        var changed = 0
        var i = 0
        while i < bytes {
            if abs(Int(pa[i]) - Int(pb[i])) > 6 { changed += 1 }
            i += 4                                   // sample one channel per pixel
        }
        return Double(changed) / Double(bytes / 4) * 100
    }

    @MainActor
    static func warp(to contentPoint: NSPoint, in content: NSView) {
        let inWindow = content.convert(contentPoint, to: nil)
        let onScreen = content.window!.convertPoint(toScreen: inWindow)
        warp(toScreen: onScreen)
    }

    static func warp(toScreen p: NSPoint) {
        let displayHeight = CGDisplayBounds(CGMainDisplayID()).height
        CGWarpMouseCursorPosition(CGPoint(x: p.x, y: displayHeight - p.y))
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    @MainActor
    static func click(_ window: NSWindow, _ p: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(e)
            }
        }
    }

    @MainActor
    static func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let e = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01),
                                       inMode: .default, dequeue: true) { NSApp.sendEvent(e) }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}
