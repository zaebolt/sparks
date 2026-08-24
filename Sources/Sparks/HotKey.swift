import AppKit
import Carbon.HIToolbox

/// A single system-wide hot key, registered through Carbon so it works without
/// Accessibility permissions and without the app ever taking focus first.
final class HotKey {
    static let shared = HotKey()

    /// ⌥Space — two keys, and not claimed by macOS out of the box.
    static let displayName = "⌥Space"
    private static let keyCode = UInt32(kVK_Space)
    private static let modifiers = UInt32(optionKey)

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    private init() {}

    @discardableResult
    func register() -> Bool {
        guard ref == nil else { return true }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKey.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)

        let id = EventHotKeyID(signature: OSType(0x53_50_52_4B), id: 1) // 'SPRK'
        let status = RegisterEventHotKey(HotKey.keyCode, HotKey.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
