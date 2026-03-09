import Carbon
import AppKit

/// Registers a global hotkey using Carbon event APIs.
/// Does NOT require Accessibility permissions.
final class HotkeyManager {

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var selfPtr: UnsafeMutableRawPointer?

    var callback: () -> Void

    init(keyCode: UInt32 = UInt32(kVK_Space),
         modifiers: UInt32 = UInt32(controlKey | optionKey),
         callback: @escaping () -> Void) {
        self.callback = callback
        register(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        unregister()
        selfPtr.map { Unmanaged<HotkeyManager>.fromOpaque($0).release() }
    }

    // MARK: - Update hotkey at runtime

    func update(keyCode: UInt32, modifiers: UInt32) {
        unregisterHotKey()
        register(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Private

    private func register(keyCode: UInt32, modifiers: UInt32) {
        // Install event handler once
        if eventHandlerRef == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind:  UInt32(kEventHotKeyPressed)
            )
            selfPtr = Unmanaged.passRetained(self).toOpaque()
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, userData -> OSStatus in
                    guard let ptr = userData else { return noErr }
                    Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue().callback()
                    return noErr
                },
                1, &spec, selfPtr, &eventHandlerRef
            )
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x43484150), id: 1)
        RegisterEventHotKey(
            keyCode, modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregisterHotKey() {
        if let k = hotKeyRef { UnregisterEventHotKey(k); hotKeyRef = nil }
    }

    private func unregister() {
        unregisterHotKey()
        if let h = eventHandlerRef { RemoveEventHandler(h); eventHandlerRef = nil }
    }
}
