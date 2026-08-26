import AppKit

// Moves the real cursor onto a task row from several entry points and checks
// whether the row's delete button becomes visible — i.e. whether hover fired.
@main
enum HoverTest {
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

        // The pencil sits just left of the delete button, revealed by the same
        // hover. Editing is driven through the field editor rather than
        // synthetic key events: SwiftUI's field editor does not pick up
        // characters posted at the window, and this is what a keystroke would
        // reach anyway.
        warp(to: NSPoint(x: 110, y: rowY), in: content)
        NSApp.activate(ignoringOtherApps: true)
        spin(0.8)
        click(win, content.convert(NSPoint(x: 277, y: rowY), to: nil))
        spin(0.6)
        let opened = win.firstResponder is NSTextView
        print("\n\(opened ? "ok  " : "FAIL") the pencil opens a field on the row")
        if !opened { failures += 1 }

        // The same Edit-menu shortcuts have to reach a row's field, not just the
        // composer. Borrows the real clipboard, and puts it back.
        let savedClipboard = NSPasteboard.general.string(forType: .string)
        if let tv = win.firstResponder as? NSTextView {
            tv.selectAll(nil)
            tv.insertText("clipboard probe", replacementRange: tv.selectedRange())
            spin(0.3)
            tv.setSelectedRange(NSRange(location: 0, length: 0))      // cursor, no selection
            cmd(win, "a"); spin(0.3)
            let selectedAll = tv.selectedRange().length == ("clipboard probe" as NSString).length
            print("\(selectedAll ? "ok  " : "FAIL") cmd+A selects all of a task being edited")
            if !selectedAll { failures += 1 }
            NSPasteboard.general.clearContents()
            cmd(win, "c"); spin(0.3)
            let copied = NSPasteboard.general.string(forType: .string) == "clipboard probe"
            print("\(copied ? "ok  " : "FAIL") cmd+C copies from a task being edited")
            if !copied { failures += 1 }
            cmd(win, "a"); spin(0.2)
            cmd(win, "x"); spin(0.3)
            let cutOut = tv.string.isEmpty
            print("\(cutOut ? "ok  " : "FAIL") cmd+X cuts from a task being edited")
            if !cutOut { failures += 1 }
            cmd(win, "v"); spin(0.3)
            let pasted = tv.string == "clipboard probe"
            print("\(pasted ? "ok  " : "FAIL") cmd+V pastes into a task being edited")
            if !pasted { failures += 1 }
        }
        NSPasteboard.general.clearContents()
        if let savedClipboard { NSPasteboard.general.setString(savedClipboard, forType: .string) }

        if let tv = win.firstResponder as? NSTextView {
            tv.selectAll(nil)
            tv.insertText("rewritten by test", replacementRange: tv.selectedRange())
        }
        spin(0.4)
        key(win, keyCode: 36, chars: "\r")                     // Return commits
        spin(0.8)
        let committed = delegate.store.tasks.contains { $0.text == "rewritten by test" }
        print("\(committed ? "ok  " : "FAIL") Return keeps the new text")
        if !committed { failures += 1 }

        // Esc calls the edit off and leaves the panel open — the hand-off
        // between the delegate's monitor and the row's own.
        warp(to: NSPoint(x: 110, y: rowY), in: content)
        NSApp.activate(ignoringOtherApps: true)
        spin(0.8)
        click(win, content.convert(NSPoint(x: 277, y: rowY), to: nil))
        spin(0.6)
        if let tv = win.firstResponder as? NSTextView {
            tv.selectAll(nil)
            tv.insertText("should not stick", replacementRange: tv.selectedRange())
        }
        spin(0.4)
        key(win, keyCode: 53, chars: "\u{1b}")                 // Esc cancels
        spin(0.8)
        let discarded = !delegate.store.tasks.contains { $0.text == "should not stick" }
        print("\(discarded ? "ok  " : "FAIL") Esc throws the edit away")
        if !discarded { failures += 1 }
        let stillOpen = popoverWindow() != nil
        print("\(stillOpen ? "ok  " : "FAIL") Esc during an edit leaves the panel open")
        if !stillOpen { failures += 1 }

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
        if !removed { failures += 1 }

        warp(toScreen: restore)
        // This suite used to exit(0) whatever happened, so a FAIL it printed
        // never actually failed the run.
        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
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
    static func key(_ win: NSWindow, keyCode: UInt16, chars: String) {
        for t in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: [],
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: win.windowNumber, context: nil,
                                        characters: chars, charactersIgnoringModifiers: chars,
                                        isARepeat: false, keyCode: keyCode) {
                NSApp.sendEvent(e)
            }
        }
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
    static func popoverWindow() -> NSWindow? {
        NSApp.windows.first { "\(type(of: $0))".contains("Popover") && $0.isVisible }
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
