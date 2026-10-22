import AppKit

/// Bottom-center panel like Ubuntu's: Selection / Screen / Window, a shutter button, and close.
final class CaptureToolbar: NSVisualEffectView {
    private weak var session: CaptureSession?
    private let modes = NSSegmentedControl(labels: ["Selection", "Screen", "Window"], trackingMode: .selectOne,
                                           target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "")

    init(session: CaptureSession) {
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: 452, height: 88))
        appearance = NSAppearance(named: .darkAqua)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true

        for (index, symbol) in ["rectangle.dashed", "display", "macwindow"].enumerated() {
            modes.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), forSegment: index)
            modes.setImageScaling(.scaleProportionallyDown, forSegment: index)
            modes.setWidth(100, forSegment: index)
        }
        modes.segmentStyle = .rounded
        modes.target = self
        modes.action = #selector(modeChanged)
        modes.refusesFirstResponder = true
        modes.frame = NSRect(x: 16, y: 40, width: 312, height: 30)
        modes.toolTip = "S, C or W"
        addSubview(modes)

        let shutter = ShutterButton(frame: NSRect(x: 344, y: 34, width: 44, height: 44))
        shutter.target = self
        shutter.action = #selector(captureClicked)
        shutter.toolTip = "Capture (Enter)"
        shutter.setAccessibilityLabel("Capture")
        addSubview(shutter)

        let close = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Cancel")!,
                             target: self, action: #selector(closeClicked))
        close.isBordered = false
        close.refusesFirstResponder = true
        close.imageScaling = .scaleProportionallyUpOrDown
        close.contentTintColor = .secondaryLabelColor
        close.frame = NSRect(x: 404, y: 42, width: 28, height: 28)
        close.toolTip = "Cancel (Esc)"
        addSubview(close)

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.frame = NSRect(x: 12, y: 10, width: frame.width - 24, height: 16)
        addSubview(hint)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Keep clicks on the panel background from starting a selection underneath.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    func containsGlobal(_ point: CGPoint) -> Bool {
        guard let window else { return false }
        return window.convertToScreen(convert(bounds, to: nil)).contains(point)
    }

    func update(mode: CaptureMode, captureOnRelease: Bool) {
        modes.selectedSegment = mode.rawValue
        switch mode {
        case .selection:
            hint.stringValue = captureOnRelease ? "Drag to capture an area · Esc to cancel"
                                                : "Drag to select · Enter, Space or ⌘C to capture · Esc to cancel"
        case .screen: hint.stringValue = "Click a display to capture it · Esc to cancel"
        case .window: hint.stringValue = "Click a window to capture it · Esc to cancel"
        }
    }

    @objc private func modeChanged() {
        guard let mode = CaptureMode(rawValue: modes.selectedSegment) else { return }
        session?.setMode(mode)
    }
    @objc private func captureClicked() { session?.capture() }
    @objc private func closeClicked() { session?.cancel() }
}

private final class ShutterButton: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        refusesFirstResponder = true
        setButtonType(.momentaryPushIn)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        ring.lineWidth = 3
        NSColor.white.setStroke()
        ring.stroke()
        (isHighlighted ? NSColor.white.withAlphaComponent(0.6) : NSColor.white).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 7, dy: 7)).fill()
    }
}
