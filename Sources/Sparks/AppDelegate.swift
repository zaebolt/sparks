import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = Store()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var escMonitor: Any?
    private var rollOverTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        setUpStatusItem()
        setUpPopover()

        HotKey.shared.onPress = { [weak self] in self?.toggle() }
        if !HotKey.shared.register() {
            // Another app owns ⌥Space; the menu bar icon still works.
            NSLog("Sparks: could not register \(HotKey.displayName) — it is already taken.")
        }

        // Sweep completed tasks when the day turns over, including after sleep.
        rollOverTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            DispatchQueue.main.async { self.store.rollOverIfNeeded() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in DispatchQueue.main.async { self.store.rollOverIfNeeded() } }
    }

    func applicationWillTerminate(_ note: Notification) {
        HotKey.shared.unregister()
        rollOverTimer?.invalidate()
    }

    // MARK: - Setup

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
