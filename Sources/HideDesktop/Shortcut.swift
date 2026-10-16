import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a Carbon key code + Carbon modifier mask, plus how to display the key.
struct Shortcut: Equatable {
    var keyCode: Int
    var modifiers: Int
    var key: String

    static let `default` = Shortcut(keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey | cmdKey, key: "H")

    var display: String { Self.symbols(forCarbon: modifiers) + key }

    /// Menu items can only show a shortcut whose key is a plain character.
    var menuKeyEquivalent: String? {
        key.count == 1 && key.unicodeScalars.allSatisfy(\.isASCII) ? key.lowercased() : nil
    }

    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & controlKey != 0 { flags.insert(.control) }
        if modifiers & optionKey != 0 { flags.insert(.option) }
        if modifiers & shiftKey != 0 { flags.insert(.shift) }
        if modifiers & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    /// Builds a shortcut from a key press. Returns nil unless it includes ⌘, ⌥ or ⌃ (function keys excepted),
    /// so a stray letter can't hijack normal typing.
    init?(event: NSEvent) {
        let code = Int(event.keyCode)
        let mods = Self.carbon(from: event.modifierFlags)
        guard let key = Self.specialKeys[code]
                ?? event.characters(byApplyingModifiers: [])?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !key.isEmpty
        else { return nil }
        guard Self.functionKeys.contains(code) || mods & (cmdKey | optionKey | controlKey) != 0 else { return nil }
        self.init(keyCode: code, modifiers: mods, key: key)
    }

    init(keyCode: Int, modifiers: Int, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    // MARK: Persistence

    var dictionary: [String: Any] { ["keyCode": keyCode, "modifiers": modifiers, "key": key] }

    init?(dictionary: [String: Any]?) {
        guard let d = dictionary, let code = d["keyCode"] as? Int, let mods = d["modifiers"] as? Int,
              let key = d["key"] as? String else { return nil }
        self.init(keyCode: code, modifiers: mods, key: key)
    }

    // MARK: Helpers

    static func carbon(from flags: NSEvent.ModifierFlags) -> Int {
        var mods = 0
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.shift) { mods |= shiftKey }
        if flags.contains(.command) { mods |= cmdKey }
        return mods
    }

    static func symbols(forCarbon mods: Int) -> String {
        var s = ""
        if mods & controlKey != 0 { s += "⌃" }
        if mods & optionKey != 0 { s += "⌥" }
        if mods & shiftKey != 0 { s += "⇧" }
        if mods & cmdKey != 0 { s += "⌘" }
        return s
    }

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static let specialKeys: [Int: String] = {
        var keys: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (i, code) in fKeys.enumerated() { keys[code] = "F\(i + 1)" }
        return keys
    }()
}

/// Owns the one global shortcut that toggles hiding.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var action: (() -> Void)?
    private var hotKey: HotKey?
    private let settings = Settings.shared

    /// The active shortcut, or nil when turned off.
    var shortcut: Shortcut? { settings.hotKeyEnabled ? settings.shortcut : nil }

    func reload() {
        hotKey = nil
        guard let s = shortcut else { return }
        hotKey = HotKey(keyCode: s.keyCode, modifiers: s.modifiers) { [weak self] in self?.action?() }
    }

    /// Stops listening while the user records a new shortcut, so pressing the old one doesn't fire it.
    func pause() { hotKey = nil }

    /// Saves and registers a new shortcut (nil turns it off). Returns false and keeps the old one
    /// if macOS refuses the combination.
    @discardableResult
    func set(_ new: Shortcut?) -> Bool {
        guard let new else {
            settings.hotKeyEnabled = false
            reload()
            return true
        }
        hotKey = nil
        guard let registered = HotKey(keyCode: new.keyCode, modifiers: new.modifiers, action: { [weak self] in
            self?.action?()
        }) else {
            reload()
            return false
        }
        hotKey = registered
        settings.shortcut = new
        settings.hotKeyEnabled = true
        return true
    }
}
