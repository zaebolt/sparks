import AppKit

@main
enum UITest {
    static var failures = 0

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

        // ---- 1. Placement: is the panel actually hanging off the icon? ----
        NSApp.activate(ignoringOtherApps: true)
        HotKey.shared.onPress?()
        spin(1.0)
        var attempts = 0
        while popoverWindow() == nil, attempts < 3 {      // it can lose the race to open
            NSApp.activate(ignoringOtherApps: true)
            HotKey.shared.onPress?()
            spin(1.2)
            attempts += 1
        }
        guard let win = popoverWindow(), let button = statusButton(app: delegate) else {
            print("FAIL no popover / status button"); exit(1)
        }
        let icon = button.window!.convertToScreen(button.convert(button.bounds, to: nil))
        let gap = icon.minY - win.frame.maxY
        let dx = abs(win.frame.midX - icon.midX)
        print(String(format: "icon at x=%.0f y=%.0f..%.0f   panel top=%.0f midX=%.0f",
                     icon.midX, icon.minY, icon.maxY, win.frame.maxY, win.frame.midX))
        check("panel hangs just below the icon (gap \(Int(gap))pt)", gap >= -2 && gap <= 12)
        check("panel is centred under the icon (off by \(Int(dx))pt)", dx <= 8)

        // ---- 1b. The standard editing shortcuts reach the composer ----
        // They are not built into a text field. AppKit resolves them against the
        // main menu's Edit items, and an accessory app has none until the
        // delegate installs one — so this is really a test of that menu.
        // Borrows the real clipboard, and puts it back.
        let savedClipboard = NSPasteboard.general.string(forType: .string)
        if let field = win.firstResponder as? NSTextView {
            field.insertText("clipboard probe", replacementRange: field.selectedRange())
            spin(0.3)
            field.setSelectedRange(NSRange(location: 0, length: 0))   // cursor, no selection
            cmd(win, "a"); spin(0.3)
            check("cmd+A selects all of the composer",
                  field.selectedRange().length == ("clipboard probe" as NSString).length)
            NSPasteboard.general.clearContents()
            cmd(win, "c"); spin(0.3)
            check("cmd+C copies from the composer",
                  NSPasteboard.general.string(forType: .string) == "clipboard probe")
            cmd(win, "a"); spin(0.2)
            cmd(win, "x"); spin(0.3)
            check("cmd+X cuts from the composer", field.string.isEmpty)
            cmd(win, "v"); spin(0.3)
            check("cmd+V pastes into the composer", field.string == "clipboard probe")
            cmd(win, "a"); spin(0.2)
            field.insertText("", replacementRange: field.selectedRange())   // leave it empty
            spin(0.2)
        } else {
            print("FAIL the composer was not focused when the panel opened"); failures += 1
        }
        NSPasteboard.general.clearContents()
        if let savedClipboard { NSPasteboard.general.setString(savedClipboard, forType: .string) }

        // ---- 2. Size adapts to content instead of scrolling ----
        let emptyH = win.frame.height
        for t in ["Ring the notary", "Read the Sardinia lease", "Water the olive tree"] {
            delegate.store.add(t)
        }
        spin(0.8)
        let threeH = win.frame.height
        check("panel grew for three tasks (\(Int(emptyH)) → \(Int(threeH)))", threeH > emptyH + 40)

        delegate.store.add("Call Mum back")
        delegate.store.add("Order the espresso beans")
        spin(0.8)
        let fiveH = win.frame.height
        check("panel grew again at five (\(Int(threeH)) → \(Int(fiveH)))", fiveH > threeH)
        check("panel stays a sane height", fiveH < 520)

        // ---- 3. Does clicking the checkbox actually complete a task? ----
        let content = win.contentView!
        let origin = content.convert(NSPoint.zero, to: nil)
        print(String(format: "window %.0fx%.0f, content %.0fx%.0f at (%.0f, %.0f)",
                     win.frame.width, win.frame.height,
                     content.bounds.width, content.bounds.height, origin.x, origin.y))

        let before = delegate.store.completed.count
        var hitY: CGFloat?
        var hitX: CGFloat?
        for x in [CGFloat(23), 150] {           // checkbox column, then the task text
            var y = content.bounds.height - 40
            while y > 30, hitY == nil {
                click(win, content.convert(NSPoint(x: x, y: y), to: nil))
                spin(0.06)
                if delegate.store.completed.count > before { hitY = y; hitX = x }
                y -= 2
            }
            if hitY != nil { break }
        }
        if let hitX, let hitY { print("   (hit at x=\(Int(hitX)) y=\(Int(hitY)))") } else { print("   (no hit anywhere)") }
        check("clicking completes a task", delegate.store.completed.count == before + 1)
        if let done = delegate.store.completed.first { print("   completed: \(done.text)") }
        check("completed task stays listed", delegate.store.completed.count == 1)
        check("a slot freed up", delegate.store.open.count == 4)

        // Dump the real popover so its layout can be eyeballed, not just asserted.
        if CommandLine.arguments.count > 1, let content = win.contentView {
            spin(0.4)
            let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            print("wrote \(CommandLine.arguments[1]) (\(Int(content.bounds.width))x\(Int(content.bounds.height)))")
        }

        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Helpers

    static func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "ok  " : "FAIL") \(name)")
        if !ok { failures += 1 }
    }

    @MainActor
    static func popoverWindow() -> NSWindow? {
        NSApp.windows.first { "\(type(of: $0))".contains("Popover") && $0.isVisible }
    }

    @MainActor
    static func statusButton(app: AppDelegate) -> NSStatusBarButton? {
        NSStatusBar.system.value(forKey: "_statusItems")  // not needed; use the visible one
        return NSApp.windows.compactMap { win -> NSStatusBarButton? in
            findButton(win.contentView)
        }.first
    }

    @MainActor
    static func findButton(_ view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let b = view as? NSStatusBarButton { return b }
        for sub in view.subviews { if let b = findButton(sub) { return b } }
        return nil
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

    /// A ⌘-modified key press, the way the Edit menu's key equivalents see it.
    @MainActor
    static func cmd(_ win: NSWindow, _ ch: String) {
        if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: win.windowNumber, context: nil,
                                    characters: ch, charactersIgnoringModifiers: ch,
                                    isARepeat: false, keyCode: 0) {
            NSApp.sendEvent(e)
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
