import AppKit
import MacSnipCore

private final class ShortcutRecorder: NSButton {
    var shortcut: KeyboardShortcut { didSet { if !recording { title = shortcut.display } } }
    var onChange: ((KeyboardShortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    private(set) var recording = false

    init(shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        title = shortcut.display
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        target = self
        action = #selector(startRecording)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    @objc private func startRecording() { window?.makeFirstResponder(self) }
    override func mouseDown(with event: NSEvent) { startRecording() }
    override func becomeFirstResponder() -> Bool {
        recording = true
        title = "Press keys…"
        setAccessibilityValue("Recording shortcut. Escape cancels.")
        onRecordingChange?(true)
        return true
    }
    override func resignFirstResponder() -> Bool {
        if recording {
            recording = false
            title = shortcut.display
            setAccessibilityValue(shortcut.display)
            onRecordingChange?(false)
        }
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode != 53 {
            let candidate = KeyboardShortcut(event)
            guard KeyboardShortcut.keyNames[candidate.keyCode] != nil else { NSSound.beep(); return }
            window?.makeFirstResponder(nil)
            onChange?(candidate)
            return
        }
        window?.makeFirstResponder(nil)
    }
}

private final class SettingsPanel: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let recorder = firstResponder as? ShortcutRecorder, recorder.recording {
            recorder.keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class SettingsWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let recorder: ShortcutRecorder
    private let status = NSTextField(wrappingLabelWithString: "")
    private let folderLabel = NSTextField(labelWithString: "")
    private let captureOnRelease = NSButton(checkboxWithTitle: "Capture as soon as the mouse is released (skip confirming the selection)",
                                            target: nil, action: nil)
    private let playSound = NSButton(checkboxWithTitle: "Play shutter sound", target: nil, action: nil)
    private let showThumbnail = NSButton(checkboxWithTitle: "Show thumbnail after capture", target: nil, action: nil)
    private let onShortcut: (ShortcutConfiguration) -> String?
    private let onRecordingChange: (Bool) -> Void

    init(configuration: ShortcutConfiguration, onShortcut: @escaping (ShortcutConfiguration) -> String?,
         onRecordingChange: @escaping (Bool) -> Void) {
        recorder = ShortcutRecorder(shortcut: configuration.capture)
        self.onShortcut = onShortcut
        self.onRecordingChange = onRecordingChange
        window = SettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                               styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "MacSnip Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        guard let content = window.contentView else { return }
        func label(_ text: String, _ rect: NSRect, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                   color: NSColor = .labelColor) {
            let field = NSTextField(wrappingLabelWithString: text)
            field.frame = rect
            field.font = .systemFont(ofSize: size, weight: weight)
            field.textColor = color
            content.addSubview(field)
        }
        label("MacSnip", NSRect(x: 24, y: 368, width: 500, height: 30), size: 23, weight: .semibold)

        label("Capture shortcut", NSRect(x: 24, y: 330, width: 200, height: 20), weight: .medium)
        recorder.frame = NSRect(x: 300, y: 324, width: 236, height: 30)
        recorder.setAccessibilityLabel("Capture shortcut")
        recorder.onChange = { [weak self] shortcut in self?.apply(ShortcutConfiguration(capture: shortcut)) }
        recorder.onRecordingChange = onRecordingChange
        content.addSubview(recorder)
        label("Click the shortcut, then press new keys. Hyper shortcuts work with Caps Lock remapped to ⌃⌥⌘ or ⌃⌥⌘⇧.",
              NSRect(x: 24, y: 284, width: 512, height: 32), size: 11, color: .secondaryLabelColor)
        status.frame = NSRect(x: 24, y: 258, width: 512, height: 22)
        status.font = .systemFont(ofSize: 11)
        content.addSubview(status)

        label("Save screenshots to", NSRect(x: 24, y: 222, width: 200, height: 20), weight: .medium)
        folderLabel.frame = NSRect(x: 24, y: 198, width: 360, height: 20)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = .secondaryLabelColor
        content.addSubview(folderLabel)
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        choose.bezelStyle = .rounded
        choose.frame = NSRect(x: 396, y: 192, width: 140, height: 30)
        content.addSubview(choose)

        for (index, box) in [captureOnRelease, playSound, showThumbnail].enumerated() {
            box.frame = NSRect(x: 22, y: 146 - CGFloat(index) * 28, width: 516, height: 22)
            box.target = self
            box.action = #selector(togglesChanged)
            content.addSubview(box)
        }

        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        reset.bezelStyle = .rounded
        reset.frame = NSRect(x: 20, y: 20, width: 150, height: 32)
        content.addSubview(reset)
        let done = NSButton(title: "Done", target: self, action: #selector(close))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.frame = NSRect(x: 446, y: 20, width: 94, height: 32)
        content.addSubview(done)
        loadPreferences()
        showStatus(nil)
    }

    private func loadPreferences() {
        folderLabel.stringValue = (Preferences.saveFolder.path as NSString).abbreviatingWithTildeInPath
        folderLabel.toolTip = Preferences.saveFolder.path
        captureOnRelease.state = Preferences.captureOnRelease ? .on : .off
        playSound.state = Preferences.playSound ? .on : .off
        showThumbnail.state = Preferences.showThumbnail ? .on : .off
    }

    private func showStatus(_ error: String?, saved: Bool = false) {
        if let error {
            status.stringValue = error
            status.textColor = .systemRed
        } else {
            status.stringValue = saved ? "Shortcut saved." : "Screenshots are copied to the clipboard and saved as yyyy-mm-dd_hh.mm.ss.png."
            status.textColor = saved ? .systemGreen : .secondaryLabelColor
        }
    }

    private func apply(_ proposed: ShortcutConfiguration) {
        if let error = onShortcut(proposed) {
            showStatus(error)
        } else {
            recorder.shortcut = proposed.capture
            showStatus(nil, saved: true)
        }
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = Preferences.saveFolder
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Preferences.saveFolder = url
            self?.loadPreferences()
        }
    }

    @objc private func togglesChanged() {
        Preferences.captureOnRelease = captureOnRelease.state == .on
        Preferences.playSound = playSound.state == .on
        Preferences.showThumbnail = showThumbnail.state == .on
    }

    @objc private func restoreDefaults() {
        window.makeFirstResponder(nil)
        Preferences.resetAll()
        loadPreferences()
        apply(.defaults)
    }

    @objc private func close() { window.close() }
    func windowWillClose(_ notification: Notification) { window.makeFirstResponder(nil) }
    func windowDidResignKey(_ notification: Notification) { window.makeFirstResponder(nil) }
}
