import AppKit
import ServiceManagement
import MacSnipCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var captureItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private let hotKey = GlobalHotKey()
    private var shortcuts = ShortcutConfiguration.load()
    private var shortcutErrors: [String] = []
    private var settings: SettingsWindow?
    private var session: CaptureSession?
    private var isFreezing = false
    private var previousApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Preferences.registerDefaults()
        configureMenu()
        enableLaunchAtLoginOnFirstRun()
        hotKey.onPress = { [weak self] in self?.startCapture() }
        shortcutErrors = hotKey.register(shortcuts).map { "\($0.shortcut) (\($0.status))" }
        refreshMenu()
        // Shows the system prompt once; capture explains how to grant access if it is still missing.
        if !ScreenCapturer.hasPermission { CGRequestScreenCaptureAccess() }
        if !shortcutErrors.isEmpty { showSettings() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: Menu

    private func configureMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit MacSnip", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "MacSnip")
        let menu = NSMenu()
        menu.autoenablesItems = false
        captureItem = NSMenuItem(title: "Take Screenshot", action: #selector(captureFromMenu), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(withTitle: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacSnip", action: #selector(quit), keyEquivalent: "q").target = self
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    private func refreshMenu() {
        captureItem.keyEquivalent = shortcuts.capture.menuKey
        captureItem.keyEquivalentModifierMask = shortcuts.capture.modifiers.cocoa
        let status = SMAppService.mainApp.status
        loginItem.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
        statusItem.button?.toolTip = "MacSnip · \(shortcuts.capture.display) to take a screenshot"
    }

    @objc private func captureFromMenu() {
        // Let the menu close before the screen is frozen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.startCapture() }
    }

    @objc private func openFolder() {
        let folder = Preferences.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    /// Launch at Login defaults to on, but only once, so turning it off in the menu sticks.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "launchAtLoginConfigured"
        // Skip `swift run` binaries and translocated copies, whose paths would not survive a restart.
        let path = Bundle.main.bundlePath
        guard !UserDefaults.standard.bool(forKey: key), path.hasSuffix(".app"), !path.contains("/AppTranslocation/") else { return }
        if SMAppService.mainApp.status == .notRegistered, (try? SMAppService.mainApp.register()) == nil { return }
        UserDefaults.standard.set(true, forKey: key)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("Launch at Login could not be changed", error.localizedDescription)
        }
        refreshMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Capture

    private func startCapture() {
        guard session == nil, !isFreezing else { return }
        guard ScreenCapturer.hasPermission else { showPermissionAlert(); return }
        ThumbnailToast.dismissCurrent()
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApplication = frontmost?.processIdentifier == getpid() ? nil : frontmost
        isFreezing = true
        Task { @MainActor in
            defer { isFreezing = false }
            do {
                let frozen = try await ScreenCapturer.freeze()
                let session = CaptureSession(frozen: frozen, captureOnRelease: Preferences.captureOnRelease) { result in
                    self.finishCapture(result)
                }
                self.session = session
                session.show()
            } catch {
                if ScreenCapturer.hasPermission {
                    showAlert("The screen could not be captured", error.localizedDescription)
                } else {
                    showPermissionAlert()
                }
            }
        }
    }

    private func finishCapture(_ result: CaptureResult?) {
        session = nil
        previousApplication?.activate()
        previousApplication = nil
        switch result {
        case nil: return
        case .image(let image, let scale, let screen):
            deliver(image, scale: scale, screen: screen)
        case .window(let target, let content, let fallback, let screen):
            Task { @MainActor in
                if let (image, scale) = try? await ScreenCapturer.captureWindow(target, content: content) {
                    deliver(image, scale: scale, screen: screen)
                } else if let (image, scale) = fallback {
                    deliver(image, scale: scale, screen: screen)
                } else {
                    NSSound.beep()
                }
            }
        }
    }

    private func deliver(_ image: CGImage, scale: CGFloat, screen: NSScreen) {
        if Preferences.playSound { ScreenshotOutput.playShutter() }
        // Encode off the main thread so the overlay disappears immediately on large displays.
        DispatchQueue.global(qos: .userInitiated).async {
            let png = ScreenshotOutput.pngData(image, scale: scale)
            DispatchQueue.main.async { self.finishDelivery(png: png, image: image, scale: scale, screen: screen) }
        }
    }

    private func finishDelivery(png: Data?, image: CGImage, scale: CGFloat, screen: NSScreen) {
        guard let png else {
            showAlert("The screenshot could not be saved", CaptureError.encodingFailed.localizedDescription)
            return
        }
        do {
            let url = try ScreenshotOutput.deliver(png: png, image: image, scale: scale)
            if Preferences.showThumbnail { ThumbnailToast.show(image: image, scale: scale, url: url, on: screen) }
        } catch {
            showAlert("The screenshot is on the clipboard but could not be saved",
                      "\(error.localizedDescription)\n\nFolder: \(Preferences.saveFolder.path)")
        }
    }

    // MARK: Settings and alerts

    @objc private func showSettings() {
        if settings == nil {
            settings = SettingsWindow(configuration: shortcuts, onShortcut: { [weak self] proposed in
                self?.applyShortcuts(proposed) ?? "MacSnip is unavailable."
            }, onRecordingChange: { [weak self] recording in
                guard let self else { return }
                self.shortcutErrors = self.hotKey.suspendForRecording(recording).map { "\($0.shortcut) (\($0.status))" }
            })
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.window.center()
        settings?.window.makeKeyAndOrderFront(nil)
        if !shortcutErrors.isEmpty {
            showAlert("Shortcut unavailable",
                      "Could not register \(shortcutErrors.joined(separator: ", ")). Another app may be using it; choose a different shortcut.")
            shortcutErrors = []
        }
    }

    private func applyShortcuts(_ proposed: ShortcutConfiguration) -> String? {
        if let error = proposed.validationError ?? SystemShortcuts.error(for: proposed, reserved: SystemShortcuts.current()) {
            return error
        }
        let errors = hotKey.register(proposed)
        guard errors.isEmpty else {
            return "Could not register \(errors.map { "\($0.shortcut) (\($0.status))" }.joined(separator: ", ")). Another app may be using it. Your previous shortcut is still active."
        }
        shortcuts = proposed
        shortcuts.save()
        shortcutErrors = []
        refreshMenu()
        return nil
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "MacSnip needs Screen Recording access"
        alert.informativeText = "Enable MacSnip in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen MacSnip."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            CGRequestScreenCaptureAccess()
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
