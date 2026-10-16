import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Carbon hot keys need no Accessibility permission.
final class HotKey {
    private static var action: (() -> Void)?
    private static var handler: EventHandlerRef?
    private var ref: EventHotKeyRef?

    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        HotKey.action = action

        if HotKey.handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.action?() }
                return noErr
            }, 1, &spec, nil, &HotKey.handler)
        }

        let id = EventHotKeyID(signature: OSType(0x4241_5245), id: 1) // "BARE"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { return nil }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }
}
