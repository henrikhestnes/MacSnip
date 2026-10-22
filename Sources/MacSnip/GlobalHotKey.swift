import AppKit
import Carbon
import MacSnipCore

/// Carbon hot keys fire from any app and need no Accessibility or Input Monitoring permission.
final class GlobalHotKey {
    struct Registration {
        let shortcut: String
        let status: OSStatus
    }

    private static let signature: OSType = 0x4D534E50 // MSNP
    private var hotKeys: [KeyboardShortcut: (reference: EventHotKeyRef, id: UInt32)] = [:]
    private var nextID: UInt32 = 1000
    private var configuration = ShortcutConfiguration.defaults
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    func register(_ configuration: ShortcutConfiguration) -> [Registration] {
        if handler != nil { return replaceShortcuts(configuration) }

        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                          nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard result == noErr, pressed.signature == GlobalHotKey.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            if hotKey.hotKeys.values.contains(where: { $0.id == pressed.id }) { hotKey.onPress?() }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &event, context, &handler)
        guard status == noErr else {
            return configuration.registeredShortcuts.map { Registration(shortcut: $0.display, status: status) }
        }
        return replaceShortcuts(configuration, preserveOnFailure: false)
    }

    /// Register new chords before releasing old ones so a conflict cannot remove a working shortcut.
    private func replaceShortcuts(_ proposed: ShortcutConfiguration, preserveOnFailure: Bool = true) -> [Registration] {
        var replacements: [KeyboardShortcut: (reference: EventHotKeyRef, id: UInt32)] = [:]
        var errors: [Registration] = []
        for shortcut in proposed.registeredShortcuts {
            if let existing = hotKeys[shortcut] {
                replacements[shortcut] = existing
                continue
            }
            let id = nextID
            nextID += 1
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifiers.carbon,
                                            EventHotKeyID(signature: Self.signature, id: id),
                                            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            if status == noErr, let reference { replacements[shortcut] = (reference, id) }
            else { errors.append(Registration(shortcut: shortcut.display, status: status)) }
        }
        if preserveOnFailure && !errors.isEmpty {
            for (shortcut, registration) in replacements where hotKeys[shortcut] == nil {
                UnregisterEventHotKey(registration.reference)
            }
            return errors
        }
        for (shortcut, registration) in hotKeys where replacements[shortcut] == nil {
            UnregisterEventHotKey(registration.reference)
        }
        hotKeys = replacements
        configuration = proposed
        return errors
    }

    /// Released while recording a new shortcut so pressing the current one doesn't start a capture.
    func suspendForRecording(_ suspended: Bool) -> [Registration] {
        if suspended {
            for registration in hotKeys.values { UnregisterEventHotKey(registration.reference) }
            hotKeys.removeAll()
            return []
        }
        if handler == nil { return register(configuration) }
        return replaceShortcuts(configuration, preserveOnFailure: false)
    }

    deinit {
        for registration in hotKeys.values { UnregisterEventHotKey(registration.reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
