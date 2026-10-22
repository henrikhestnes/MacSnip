import AppKit
import Carbon
import MacSnipCore

extension ShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
    var carbon: UInt32 {
        var value: UInt32 = 0
        if contains(.control) { value |= UInt32(controlKey) }
        if contains(.option) { value |= UInt32(optionKey) }
        if contains(.shift) { value |= UInt32(shiftKey) }
        if contains(.command) { value |= UInt32(cmdKey) }
        return value
    }
    var cocoa: NSEvent.ModifierFlags {
        var value: NSEvent.ModifierFlags = []
        if contains(.control) { value.insert(.control) }
        if contains(.option) { value.insert(.option) }
        if contains(.shift) { value.insert(.shift) }
        if contains(.command) { value.insert(.command) }
        return value
    }
}

extension KeyboardShortcut {
    init(_ event: NSEvent) { self.init(event.keyCode, ShortcutModifiers(event.modifierFlags)) }
    var menuKey: String { keyName.count == 1 ? keyName.lowercased() : "" }
}

/// Read only when editing shortcuts; this does not monitor keyboard input.
enum SystemShortcuts {
    static func current() -> Set<KeyboardShortcut> {
        var result: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&result)
        let array = result?.takeRetainedValue()
        guard status == noErr, let entries = array as? [[String: Any]] else {
            // The Carbon query may be unavailable in a restricted process.
            return fromPreferences()
        }
        return Set(entries.compactMap { entry in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let flags = entry[kHISymbolicHotKeyModifiers as String] as? NSNumber,
                  let keyCode = UInt16(exactly: code.uint32Value) else { return nil }
            let value = flags.uint32Value
            var modifiers: ShortcutModifiers = []
            if value & UInt32(controlKey) != 0 { modifiers.insert(.control) }
            if value & UInt32(optionKey) != 0 { modifiers.insert(.option) }
            if value & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
            if value & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
            return KeyboardShortcut(keyCode, modifiers)
        })
    }
    private static func fromPreferences() -> Set<KeyboardShortcut> {
        guard let entries = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                      "com.apple.symbolichotkeys" as CFString) as? [String: [String: Any]] else { return [] }
        return Set(entries.values.compactMap { entry in
            guard (entry["enabled"] as? NSNumber)?.boolValue == true,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [NSNumber], parameters.count == 3,
                  let keyCode = UInt16(exactly: parameters[1].uint32Value) else { return nil }
            return KeyboardShortcut(keyCode, ShortcutModifiers(NSEvent.ModifierFlags(rawValue: parameters[2].uintValue)))
        })
    }
    static func error(for configuration: ShortcutConfiguration, reserved: Set<KeyboardShortcut>) -> String? {
        let conflicts = configuration.conflicts(with: reserved)
        guard !conflicts.isEmpty else { return nil }
        return "Already assigned in macOS Keyboard Shortcuts: \(conflicts.map(\.display).joined(separator: ", ")). Choose different keys."
    }
}
