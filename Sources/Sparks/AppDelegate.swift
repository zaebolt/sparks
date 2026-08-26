import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = Store()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var escMonitor: Any?
    private var dayObserver: Any?
    private var wakeObserver: Any?
    private var editObserver: Any?
    private var isEditingTask = false

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        setUpEditMenu()
        setUpStatusItem()
        setUpPopover()

        HotKey.shared.onPress = { [weak self] in self?.toggle() }
        if !HotKey.shared.register() {
            // Another app owns ⌥Space; the menu bar icon still works.
            NSLog("Sparks: could not register \(HotKey.displayName) — it is already taken.")
        }

        // Sweep completed tasks when the day turns over, including after sleep.
        //
        // This used to poll on a 60s timer, which meant ~1440 wakes a day to
        // compare two strings, all but one of which found nothing to do. A
        // timer with no tolerance cannot be coalesced with anything else
        // either, so each one was a discrete wake from idle — and on Apple
        // silicon the wake costs far more than the work. These fire only when
        // the day actually turns:
        //
        //   - NSCalendarDayChanged  at midnight, and on a time zone or clock change
        //   - didWakeNotification   for a machine that slept through midnight
        //
        // `showPopover` checks once more before showing, so a rollover the
        // system somehow failed to announce still cannot reach the screen.
        dayObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.store.rollOverIfNeeded() } }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.store.rollOverIfNeeded() } }

        // While a task is being renamed, Esc belongs to the row: it calls the
        // edit off and the panel stays put. The row installs its own monitor
        // for that, so this one only has to keep out of the way — which means
        // the two never have to be installed in a particular order.
        editObserver = NotificationCenter.default.addObserver(
            forName: .sparksEditingChanged, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.isEditingTask = note.object as? Bool ?? false }
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        HotKey.shared.unregister()
        if let dayObserver { NotificationCenter.default.removeObserver(dayObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let editObserver { NotificationCenter.default.removeObserver(editObserver) }
        dayObserver = nil
        wakeObserver = nil
        editObserver = nil
    }

    // MARK: - Setup

    /// The standard editing shortcuts, which a text field does not carry on its
    /// own: AppKit resolves ⌘C, ⌘X, ⌘V and ⌘A against the main menu's Edit
    /// items and sends the matching action down the responder chain to whatever
    /// is being edited. An accessory app starts with no main menu at all, so in
    /// the panel they did nothing — you could type into the composer or a task
    /// but not select, copy or paste in it.
    ///
    /// The menu is never seen. An `LSUIElement` app has no menu bar to draw it
    /// in; it exists so the key equivalents resolve. `target` stays nil so each
    /// item goes to the first responder, which while editing is the field
    /// editor behind the SwiftUI `TextField`.
    private func setUpEditMenu() {
        let edit = NSMenu(title: "Edit")
        let items: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            // undo:/redo: are not declared on a class this can name, so they
            // are built from their strings; the rest come off NSText.
            ("Undo",       NSSelectorFromString("undo:"), "z", [.command]),
            ("Redo",       NSSelectorFromString("redo:"), "z", [.command, .shift]),
            ("Cut",        #selector(NSText.cut(_:)),     "x", [.command]),
            ("Copy",       #selector(NSText.copy(_:)),    "c", [.command]),
            ("Paste",      #selector(NSText.paste(_:)),   "v", [.command]),
            ("Select All", #selector(NSText.selectAll(_:)), "a", [.command]),
        ]
        for (title, action, key, flags) in items {
            if title == "Cut" { edit.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = flags
            item.target = nil
            edit.addItem(item)
        }
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = Icon.statusItem()
        button.imagePosition = .imageOnly
        button.toolTip = "Sparks — \(HotKey.displayName)"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setUpPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // Without this the popover uses a stale default size: it opens detached
        // from the icon and never grows as tasks are added.
        let hosting = NSHostingController(rootView: ContentView(store: store))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    // MARK: - Show / hide

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggle()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open  \(HotKey.displayName)", action: #selector(open), keyEquivalent: "")
            .target = self

        let login = menu.addItem(withTitle: "Open at Login",
                                 action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sparks", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil       // restore normal click handling
    }

    @objc private func open() { if !popover.isShown { showPopover() } }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Sparks: could not change the login item — \(error.localizedDescription)")
        }
    }

    private func toggle() {
        popover.isShown ? closePopover() : showPopover()
    }

    private func showPopover(retriesLeft: Int = 10) {
        guard let button = statusItem.button else { return }

        // Right after launch the status item may not have been given its slot in
        // the menu bar yet. Showing then anchors the panel to a window still
        // sitting at the origin, and it opens in the corner of the screen instead
        // of under the icon. Wait for a real position before showing.
        if let window = button.window,
           retriesLeft > 0,
           !NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.showPopover(retriesLeft: retriesLeft - 1)
            }
            return
        }

        store.rollOverIfNeeded()

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NotificationCenter.default.post(name: .sparksDidOpen, object: nil)

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Esc
            guard self?.isEditingTask != true else { return event }  // the row's Esc, not ours
            self?.closePopover()
            return nil
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        NSApp.hide(nil)     // hand focus back to whatever the user was doing
    }

    func popoverDidClose(_ note: Notification) {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }
}
