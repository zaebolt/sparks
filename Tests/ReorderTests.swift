import AppKit

// Drags open tasks around with synthetic mouse events and checks the order.
@main
enum DragTest {
    static var failures = 0
    static var midDragShot: String?

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
        NSApp.activate(ignoringOtherApps: true)
        HotKey.shared.onPress?()
        spin(1.2)
        var attempts = 0
        while popoverWindow() == nil, attempts < 3 {      // it can lose the race to open
            NSApp.activate(ignoringOtherApps: true)
            HotKey.shared.onPress?()
            spin(1.2)
            attempts += 1
        }

        guard let win = popoverWindow(), let content = win.contentView else {
            print("popover would not open"); exit(1)
        }

        print("popover open")
        // add() puts the newest on top, so seed in reverse to get Alpha, Bravo, Charlie
        for t in ["Charlie", "Bravo", "Alpha"] { delegate.store.add(t) }
        spin(1.0)

        // Locate rows by finding their checkboxes in a captured frame. Clicking
        // around to find them mutates the very state under test.
        let allBands = checkboxBands(content)
        let bands = evenlySpacedRun(allBands, expected: delegate.store.open.count)
        print("bright bands \(allBands.map { Int($0) }) -> rows \(bands.map { Int($0) })")
        guard bands.count == delegate.store.open.count else {
            print("found \(bands.count) rows, expected \(delegate.store.open.count)"); exit(1)
        }
        let rowTop = bands[0], step = bands[1] - bands[0]
        print("checkbox centres at \(bands.map { Int($0) }), step \(Int(step))pt\n")
        print("start: \(order(delegate))")
        if CommandLine.arguments.count > 1 { midDragShot = CommandLine.arguments[1] }

        // 1. Drag the first task down past one neighbour.
        drag(win, content, x: 110, from: rowTop, by: step * 1.1)
        spin(0.6)
        check("drag down one moves Alpha below Bravo",
              order(delegate) == ["Bravo", "Alpha", "Charlie"], delegate)

        // 2. Drag it down past the next one too.
        drag(win, content, x: 110, from: rowTop + step, by: step * 1.1)
        spin(0.6)
        check("drag down again puts Alpha last",
              order(delegate) == ["Bravo", "Charlie", "Alpha"], delegate)

        // 3. Drag it all the way back to the top.
        drag(win, content, x: 110, from: rowTop + 2 * step, by: -step * 2.2)
        spin(0.6)
        check("drag up two returns Alpha to the top",
              order(delegate) == ["Alpha", "Bravo", "Charlie"], delegate)

        // 4. A nudge shorter than the threshold must not reorder.
        drag(win, content, x: 110, from: rowTop, by: step * 0.3)
        spin(0.6)
        check("a small nudge leaves the order alone",
              order(delegate) == ["Alpha", "Bravo", "Charlie"], delegate)

        // 5. A plain click still completes rather than reorders.
        let doneBefore = delegate.store.completed.count
        click(win, content.convert(NSPoint(x: 110, y: rowTop), to: nil))
        spin(0.5)
        check("a click still completes the task",
              delegate.store.completed.count == doneBefore + 1, delegate)

        // 6. Right-clicking partway through a drag abandons it.
        let settled = order(delegate)
        let calm = capture(content)
        drag(win, content, x: 110, from: rowTop + step, by: step * 1.4, rightClickMidway: true)
        spin(0.8)
        check("right-click during a drag leaves the order alone",
              order(delegate) == settled, delegate)

        // The panel must also *look* settled: no row left lifted or shifted.
        let after = capture(content)
        if let dir = ProcessInfo.processInfo.environment["SPARKS_TEST_DUMP"] {
            for (name, rep) in [("calm", calm), ("after", after)] {
                if let rep, let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
                }
            }
        }
        let residue = (calm != nil && after != nil) ? difference(calm!, after!) : 100
        check(String(format: "the panel settles back (%.2f%% of pixels differ)", residue),
              residue < 0.5, delegate)

        // 7. And the panel is still usable afterwards — no drag left half-applied.
        drag(win, content, x: 110, from: rowTop, by: step * 1.1)
        spin(0.8)
        var expected = settled
        expected.swapAt(0, 1)
        check("a drag still works after a cancelled one",
              order(delegate) == expected, delegate)

        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }


    /// Vertical centres of the checkbox column, found by scanning a captured
    /// frame for the box outlines. The panel background is much darker.
    @MainActor
    static func checkboxBands(_ view: NSView) -> [CGFloat] {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return [] }
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        guard let data = rep.bitmapData else { return [] }
        let bpr = rep.bytesPerRow, spp = rep.samplesPerPixel
        var rows: [Int] = []
        for py in 0..<rep.pixelsHigh {
            var bright = false
            var vx = CGFloat(14)
            while vx <= 32 {
                let px = Int(vx * scale)
                if px < rep.pixelsWide {
                    let o = py * bpr + px * spp
                    let v = max(data[o], max(data[o + 1], data[o + 2]))
                    if v > 90 { bright = true; break }
                }
                vx += 1
            }
            if bright { rows.append(py) }
        }
        // group consecutive scan lines into boxes
        var bands: [CGFloat] = []
        var run: [Int] = []
        for r in rows {
            if let last = run.last, r - last > 2 {
                if run.count > 3 { bands.append(CGFloat(run.reduce(0, +)) / CGFloat(run.count) / scale) }
                run = []
            }
            run.append(r)
        }
        if run.count > 3 { bands.append(CGFloat(run.reduce(0, +)) / CGFloat(run.count) / scale) }
        return bands
    }


    /// The header icon and footer badge also show up bright in that column. Real
    /// rows are the longest evenly spaced run at something like a row's pitch.
    static func evenlySpacedRun(_ all: [CGFloat], expected: Int) -> [CGFloat] {
        var candidates: [[CGFloat]] = []
        for i in 0..<all.count {
            for j in (i + 1)..<all.count {
                let step = all[j] - all[i]
                guard step >= 22, step <= 40 else { continue }
                var run = [all[i], all[j]]
                var next = all[j] + step
                for k in (j + 1)..<all.count where abs(all[k] - next) < 3 {
                    run.append(all[k])
                    next = all[k] + step
                }
                candidates.append(run)
            }
        }
        // Prefer a run with exactly one entry per open task; then the longest;
        // then the tightest pitch, since the rows are the closest-packed group.
        return candidates.sorted { a, b in
            let am = a.count == expected, bm = b.count == expected
            if am != bm { return am }
            if a.count != b.count { return a.count > b.count }
            return (a[1] - a[0]) < (b[1] - b[0])
        }.first ?? []
    }



    /// Posts an event to the application's queue so it takes the same path a real
    /// one does — including any local event monitors.
    @MainActor
    static func queue(_ type: NSEvent.EventType, _ location: NSPoint, _ window: NSWindow) {
        if let e = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil,
                                      eventNumber: 0, clickCount: 1, pressure: 1) {
            NSApp.postEvent(e, atStart: false)
        }
    }

    @MainActor
    static func capture(_ view: NSView) -> NSBitmapImageRep? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// Percentage of pixels that differ between two captures of the same view.
    static func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
              let pa = a.bitmapData, let pb = b.bitmapData else { return 100 }
        let bytes = a.bytesPerRow * a.pixelsHigh
        var changed = 0, i = 0
        while i < bytes {
            if abs(Int(pa[i]) - Int(pb[i])) > 6 { changed += 1 }
            i += 4
        }
        return Double(changed) / Double(bytes / 4) * 100
    }

    @MainActor
    static func order(_ d: AppDelegate) -> [String] { d.store.open.map(\.text) }

    @MainActor
    static func check(_ name: String, _ ok: Bool, _ d: AppDelegate) {
        print("\(ok ? "ok  " : "FAIL") \(name)")
        if !ok { print("     got \(order(d))"); failures += 1 }
    }

    /// Press, move in small steps, release — the shape SwiftUI's DragGesture wants.
    /// With `rightClickMidway`, a right button press and release is injected
    /// halfway through, which is the usual way to abandon a drag.
    @MainActor
    static func drag(_ window: NSWindow, _ content: NSView, x: CGFloat, from y: CGFloat,
                     by dy: CGFloat, rightClickMidway: Bool = false) {
        func post(_ type: NSEvent.EventType, _ p: NSPoint) {
            if let e = NSEvent.mouseEvent(with: type, location: content.convert(p, to: nil),
                                          modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(e)
            }
        }
        post(.leftMouseDown, NSPoint(x: x, y: y))
        spin(0.06)
        let steps = 12
        for i in 1...steps {
            post(.leftMouseDragged, NSPoint(x: x, y: y + dy * CGFloat(i) / CGFloat(steps)))
            spin(0.03)
            if rightClickMidway, i == steps / 2 {
                let p = NSPoint(x: x, y: y + dy * CGFloat(i) / CGFloat(steps))
                // Through the app's event queue, not straight at the window: the
                // app watches for the right button with a local event monitor,
                // and monitors only see events that come off the queue.
                queue(.rightMouseDown, content.convert(p, to: nil), window)
                spin(0.12)
                queue(.rightMouseUp, content.convert(p, to: nil), window)
                spin(0.15)
            }
            if i == steps - 1, let path = midDragShot {     // grab the lift mid-flight
                midDragShot = nil
                if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.cacheDisplay(in: content.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])!
                        .write(to: URL(fileURLWithPath: path))
                }
            }
        }
        post(.leftMouseUp, NSPoint(x: x, y: y + dy))
        spin(0.06)
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
    static func popoverWindow() -> NSWindow? {
        NSApp.windows.first { "\(type(of: $0))".contains("Popover") && $0.isVisible }
    }

    @MainActor
    static func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let e = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.005),
                                       inMode: .default, dequeue: true) { NSApp.sendEvent(e) }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
    }
}
