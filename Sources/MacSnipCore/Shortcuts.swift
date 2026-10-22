import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1)
    public static let option = Self(rawValue: 2)
    public static let shift = Self(rawValue: 4)
    public static let command = Self(rawValue: 8)
    public static let all: Self = [.control, .option, .shift, .command]
    /// Caps Lock remapped to Hyper sends ⌃⌥⌘, or ⌃⌥⌘⇧ depending on the remapping tool.
    public static let hyper: Self = [.control, .option, .command]
}

public struct KeyboardShortcut: Codable, Hashable {
    public var keyCode: UInt16
    public var modifiers: ShortcutModifiers
    public init(_ keyCode: UInt16, _ modifiers: ShortcutModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // Virtual key codes stay consistent between recording and event dispatch.
    public static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        64: "F17", 79: "F18", 80: "F19", 90: "F20", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        111: "F12", 113: "F15", 115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4",
        119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
    public static let functionKeys: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90
    ]
    public var keyName: String { Self.keyNames[keyCode] ?? "Unknown" }
    public var isHyper: Bool { modifiers.isSuperset(of: .hyper) }
    public var display: String {
        if isHyper { return "Hyper+" + keyName }
        return (modifiers.contains(.control) ? "⌃" : "") +
            (modifiers.contains(.option) ? "⌥" : "") +
            (modifiers.contains(.shift) ? "⇧" : "") +
            (modifiers.contains(.command) ? "⌘" : "") + keyName
    }
    public static let escape = Self(53)
    public static let hyperP = Self(35, .hyper)
}

public struct ShortcutConfiguration: Codable, Equatable {
    public var capture: KeyboardShortcut
    public init(capture: KeyboardShortcut) { self.capture = capture }
    public static let defaults = Self(capture: .hyperP)

    /// A Hyper shortcut is registered with and without Shift, so it works with either Hyper remapping.
    public var registeredShortcuts: [KeyboardShortcut] {
        guard capture.isHyper else { return [capture] }
        return [KeyboardShortcut(capture.keyCode, .hyper), KeyboardShortcut(capture.keyCode, .hyper.union(.shift))]
    }

    public func conflicts(with reserved: Set<KeyboardShortcut>) -> [KeyboardShortcut] {
        registeredShortcuts.filter { reserved.contains($0) }
    }

    public var validationError: String? {
        guard KeyboardShortcut.keyNames[capture.keyCode] != nil, capture.modifiers.subtracting(.all).isEmpty else {
            return "Choose a supported key."
        }
        if capture == .escape { return "Esc is reserved for cancelling a capture." }
        if capture == KeyboardShortcut(12, .command) { return "⌘Q is reserved for quitting MacSnip." }
        if capture.modifiers.intersection([.control, .option, .command]).isEmpty,
           !KeyboardShortcut.functionKeys.contains(capture.keyCode) {
            return "The shortcut must include Control, Option or Command, or use a function key."
        }
        return nil
    }

    private static let defaultsKey = "shortcuts.v1"
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.validationError == nil else { return .defaults }
        return value
    }
    public func save(to defaults: UserDefaults = .standard) {
        guard validationError == nil, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
