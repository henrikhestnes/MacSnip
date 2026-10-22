import AppKit
import ScreenCaptureKit
import MacSnipCore

enum CaptureMode: Int, CaseIterable {
    case selection, screen, window
}

enum CaptureResult {
    case image(CGImage, scale: CGFloat, screen: NSScreen)
    /// Window shots are taken live so overlapping windows are left out; the frozen crop is the fallback.
    case window(WindowTarget, content: SCShareableContent, fallback: (CGImage, CGFloat)?, screen: NSScreen)
}

final class OverlayPanel: NSPanel {
    weak var session: CaptureSession?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { session?.cancel() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if KeyboardShortcut(event) == KeyboardShortcut(8, .command) { session?.capture(); return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// The Ubuntu-style capture UI: frozen displays, a dimmed backdrop, and a mode toolbar.
final class CaptureSession {
    /// Restored on the next capture, as Ubuntu does.
    private static var lastSelection: CGRect?
    private static let handleRadius: CGFloat = 10

    let frozen: FrozenScreens
    private let captureOnRelease: Bool
    private let completion: (CaptureResult?) -> Void
    private(set) var mode: CaptureMode = .selection
    private(set) var selection: CGRect?
    private(set) var hoveredWindow: WindowTarget?
    private(set) var pointer: CGPoint
    private(set) var isMovingSelection = false
    private let bounds: CGRect
    private var drag: Drag?
    private var panels: [OverlayPanel] = []
    private var views: [OverlayView] = []
    private var toolbar: CaptureToolbar?
    private var finished = false

    private enum Drag {
        case create(anchor: CGPoint)
        case move(start: CGPoint, original: CGRect)
        case resize(SelectionHandle, original: CGRect)
    }

    init(frozen: FrozenScreens, captureOnRelease: Bool, completion: @escaping (CaptureResult?) -> Void) {
        self.frozen = frozen
        self.captureOnRelease = captureOnRelease
        self.completion = completion
        pointer = NSEvent.mouseLocation
        bounds = frozen.displays.reduce(CGRect.null) { $0.union($1.frame) }
        if !captureOnRelease, let last = Self.lastSelection, bounds.contains(last) { selection = last }
    }

    func show() {
        for display in frozen.displays {
            let panel = OverlayPanel(contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.session = self
            panel.title = "MacSnip Capture"
            panel.isReleasedWhenClosed = false
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.hidesOnDeactivate = false
            panel.animationBehavior = .none
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let view = OverlayView(display: display, session: self)
            panel.contentView = view
            panel.setFrame(display.frame, display: false)
            panels.append(panel)
            views.append(view)
        }
        let active = displayIndex(at: pointer)
        let toolbar = CaptureToolbar(session: self)
        let host = views[active]
        toolbar.setFrameOrigin(NSPoint(x: (host.bounds.width - toolbar.frame.width) / 2, y: 48))
        host.addSubview(toolbar)
        self.toolbar = toolbar
        for panel in panels { panel.orderFrontRegardless() }
        panels[active].makeKeyAndOrderFront(nil)
        panels[active].makeFirstResponder(host)
        updateHover()
        refresh()
        cursor(at: pointer).set()
    }

    private func displayIndex(at point: CGPoint) -> Int {
        frozen.displays.firstIndex { $0.frame.insetBy(dx: -1, dy: -1).contains(point) } ?? 0
    }
    var pointerDisplay: FrozenDisplay { frozen.displays[displayIndex(at: pointer)] }

    // MARK: Input, in global AppKit coordinates

    func mouseDown(at point: CGPoint, clickCount: Int) {
        pointer = point
        switch mode {
        case .screen, .window:
            updateHover()
            capture()
            return
        case .selection: break
        }
        if clickCount >= 2, let selection, selection.contains(point) { capture(); return }
        if let selection, let handle = SelectionGeometry.handle(at: point, in: selection, radius: Self.handleRadius) {
            drag = .resize(handle, original: selection)
        } else if let selection, selection.contains(point) {
            drag = .move(start: point, original: selection)
            isMovingSelection = true
        } else {
            drag = .create(anchor: SelectionGeometry.clamp(point, to: bounds))
        }
        cursor(at: point).set()
    }

    func mouseDragged(to point: CGPoint) {
        pointer = point
        let clamped = SelectionGeometry.clamp(point, to: bounds)
        switch drag {
        case .create(let anchor): selection = SelectionGeometry.rect(from: anchor, to: clamped)
        case .move(let start, let original):
            selection = SelectionGeometry.move(original, by: CGVector(dx: point.x - start.x, dy: point.y - start.y), within: bounds)
        case .resize(let handle, let original): selection = handle.resize(original, to: clamped)
        case nil: return
        }
        refresh()
    }

    func mouseUp(at point: CGPoint) {
        guard let finishedDrag = drag else { return }
        mouseDragged(to: point)
        drag = nil
        isMovingSelection = false
        // A click without dragging clears the selection.
        if let current = selection, current.width < 2 || current.height < 2 { selection = nil }
        if case .create = finishedDrag, captureOnRelease, selection != nil { capture(); return }
        refresh()
        cursor(at: point).set()
    }

    func mouseMoved(to point: CGPoint) {
        pointer = point
        if mode != .selection, !(toolbar?.containsGlobal(point) ?? false) {
            updateHover()
            refresh()
        }
        cursor(at: point).set()
    }

    func handleKey(_ event: NSEvent) {
        let modifiers = ShortcutModifiers(event.modifierFlags)
        guard modifiers.subtracting(.shift).isEmpty else { return }
        let step: CGFloat = modifiers.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 53: cancel()
        case 36, 76, 49: capture()           // Return, Enter, Space
        case 1: setMode(.selection)          // S
        case 8: setMode(.screen)             // C
        case 13: setMode(.window)            // W
        case 123: nudge(dx: -step, dy: 0)
        case 124: nudge(dx: step, dy: 0)
        case 125: nudge(dx: 0, dy: -step)
        case 126: nudge(dx: 0, dy: step)
        default: break
        }
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard mode == .selection, drag == nil, let current = selection else { return }
        selection = SelectionGeometry.move(current, by: CGVector(dx: dx, dy: dy), within: bounds)
        refresh()
    }

    func setMode(_ mode: CaptureMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        drag = nil
        isMovingSelection = false
        updateHover()
        refresh()
        cursor(at: pointer).set()
    }

    private func updateHover() {
        hoveredWindow = mode == .window ? frozen.windows.first { $0.frame.contains(pointer) } : nil
    }

    func cursor(at point: CGPoint) -> NSCursor {
        if toolbar?.containsGlobal(point) ?? false { return .arrow }
        guard mode == .selection else { return .pointingHand }
        if isMovingSelection { return .closedHand }
        guard let selection, drag == nil else { return .crosshair }
        if let handle = SelectionGeometry.handle(at: point, in: selection, radius: Self.handleRadius) {
            switch handle {
            case .left, .right: return .resizeLeftRight
            case .top, .bottom: return .resizeUpDown
            default: return .crosshair
            }
        }
        return selection.contains(point) ? .openHand : .crosshair
    }

    // MARK: Finishing

    func capture() {
        switch mode {
        case .selection:
            guard let selection else { NSSound.beep(); return }
            let scale = frozen.displays.filter { $0.frame.intersects(selection) }.map(\.scale).max() ?? 2
            guard let (image, imageScale) = ScreenCapturer.image(of: SelectionGeometry.snap(selection, scale: scale),
                                                                 from: frozen.displays) else { NSSound.beep(); return }
            Self.lastSelection = selection
            let center = CGPoint(x: selection.midX, y: selection.midY)
            finish(.image(image, scale: imageScale, screen: frozen.displays[displayIndex(at: center)].screen))
        case .screen:
            let display = pointerDisplay
            finish(.image(display.image, scale: display.scale, screen: display.screen))
        case .window:
            guard let window = hoveredWindow else { NSSound.beep(); return }
            let visible = window.frame.intersection(bounds)
            let center = CGPoint(x: visible.midX, y: visible.midY)
            finish(.window(window, content: frozen.content, fallback: ScreenCapturer.image(of: visible, from: frozen.displays),
                           screen: frozen.displays[displayIndex(at: center)].screen))
        }
    }

    func cancel() { finish(nil) }

    private func finish(_ result: CaptureResult?) {
        guard !finished else { return }
        finished = true
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        views.removeAll()
        toolbar = nil
        NSCursor.arrow.set()
        completion(result)
    }

    private func refresh() {
        for view in views { view.update() }
        toolbar?.update(mode: mode, captureOnRelease: captureOnRelease)
    }
}

final class OverlayView: NSView {
    let display: FrozenDisplay
    private weak var session: CaptureSession?
    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let sizeLabel = NSTextField(labelWithString: "")

    init(display: FrozenDisplay, session: CaptureSession) {
        self.display = display
        self.session = session
        super.init(frame: NSRect(origin: .zero, size: display.frame.size))
        wantsLayer = true
        // The frozen image lives in its own bottom subview so the toolbar and size label always draw above it.
        let canvas = PassthroughView(frame: bounds)
        canvas.wantsLayer = true
        addSubview(canvas)
        guard let layer = canvas.layer else { return }
        imageLayer.contents = display.image
        imageLayer.contentsGravity = .resize
        imageLayer.contentsScale = display.scale
        imageLayer.frame = bounds
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.5).cgColor
        dimLayer.fillRule = .evenOdd
        dimLayer.frame = bounds
        borderLayer.fillColor = nil
        borderLayer.frame = bounds
        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor.black.withAlphaComponent(0.35).cgColor
        handlesLayer.lineWidth = 1
        handlesLayer.frame = bounds
        for sublayer in [imageLayer, dimLayer, borderLayer, handlesLayer] {
            sublayer.actions = ["path": NSNull(), "contents": NSNull(), "hidden": NSNull()]
            layer.addSublayer(sublayer)
        }
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sizeLabel.textColor = .white
        sizeLabel.alignment = .center
        sizeLabel.wantsLayer = true
        sizeLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        sizeLabel.layer?.cornerRadius = 5
        sizeLabel.isHidden = true
        addSubview(sizeLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func global(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        session?.mouseDown(at: global(event), clickCount: event.clickCount)
    }
    override func mouseDragged(with event: NSEvent) { session?.mouseDragged(to: global(event)) }
    override func mouseUp(with event: NSEvent) { session?.mouseUp(at: global(event)) }
    override func mouseMoved(with event: NSEvent) { session?.mouseMoved(to: global(event)) }
    override func rightMouseDown(with event: NSEvent) { session?.cancel() }
    override func keyDown(with event: NSEvent) { session?.handleKey(event) }

    func update() {
        guard let session else { return }
        let origin = display.frame.origin
        func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -origin.x, dy: -origin.y) }
        var hole: CGRect?
        var showHandles = false
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1.5
        switch session.mode {
        case .selection:
            hole = session.selection.map(local)
            showHandles = hole != nil
        case .window:
            hole = session.hoveredWindow.map { local($0.frame) }
            borderLayer.strokeColor = NSColor.controlAccentColor.cgColor
            borderLayer.lineWidth = 4
        case .screen:
            if session.pointerDisplay.frame == display.frame { hole = bounds.insetBy(dx: 2, dy: 2) }
            borderLayer.strokeColor = NSColor.controlAccentColor.cgColor
            borderLayer.lineWidth = 4
        }
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let hole { dim.addRect(hole) }
        dimLayer.path = dim
        borderLayer.path = hole.map { CGPath(rect: $0, transform: nil) }
        let handles = CGMutablePath()
        if showHandles, let hole {
            for handle in SelectionHandle.allCases {
                let p = handle.point(in: hole)
                handles.addEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
            }
        }
        handlesLayer.path = handles
        updateSizeLabel(session: session, hole: hole)
    }

    /// Pixel size of the selection, shown once above its top-left corner.
    private func updateSizeLabel(session: CaptureSession, hole: CGRect?) {
        guard session.mode == .selection, let selection = session.selection, let hole,
              display.frame.insetBy(dx: -1, dy: -1).contains(CGPoint(x: selection.minX, y: selection.maxY)) else {
            sizeLabel.isHidden = true
            return
        }
        let snapped = SelectionGeometry.snap(selection, scale: display.scale)
        sizeLabel.stringValue = "\(Int((snapped.width * display.scale).rounded())) × \(Int((snapped.height * display.scale).rounded()))"
        sizeLabel.sizeToFit()
        let size = NSSize(width: sizeLabel.frame.width + 12, height: sizeLabel.frame.height + 4)
        var y = hole.maxY + 6
        if y + size.height > bounds.maxY { y = hole.maxY - size.height - 6 }
        sizeLabel.frame = NSRect(x: max(hole.minX, 4), y: y, width: size.width, height: size.height)
        sizeLabel.isHidden = false
    }
}

/// Never receives clicks itself, so they reach the overlay view (which accepts the first click).
private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
