import AppKit

/// A floating preview after each capture: click to open, drag into another app, or let it fade.
final class ThumbnailToast: NSObject {
    private static var current: ThumbnailToast?
    private let panel: NSPanel
    private var timer: Timer?

    static func show(image: CGImage, scale: CGFloat, url: URL, on screen: NSScreen) {
        dismissCurrent()
        let toast = ThumbnailToast(image: image, scale: scale, url: url, screen: screen)
        current = toast
        toast.panel.orderFrontRegardless()
        toast.scheduleDismiss()
    }

    static func dismissCurrent() {
        current?.timer?.invalidate()
        current?.panel.orderOut(nil)
        current = nil
    }

    private init(image: CGImage, scale: CGFloat, url: URL, screen: NSScreen) {
        let pointSize = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let fit = min(220 / max(pointSize.width, 1), 160 / max(pointSize.height, 1), 1)
        let size = NSSize(width: max(pointSize.width * fit, 24), height: max(pointSize.height * fit, 24))
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.maxX - size.width - 20, y: visible.minY + 20, width: size.width, height: size.height)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = ThumbnailView(frame: NSRect(origin: .zero, size: size), url: url,
                                 image: NSImage(cgImage: image, size: pointSize))
        view.onFinish = { [weak self] in self?.dismiss() }
        view.onHover = { [weak self] hovering in
            if hovering { self?.timer?.invalidate() } else { self?.scheduleDismiss() }
        }
        panel.contentView = view
    }

    private func scheduleDismiss() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in self?.dismiss() }
    }

    private func dismiss() {
        timer?.invalidate()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            if Self.current === self { Self.current = nil }
        })
    }
}

private final class ThumbnailView: NSView, NSDraggingSource {
    let url: URL
    let image: NSImage
    var onFinish: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var mouseDownPoint: NSPoint?

    init(frame: NSRect, url: URL, image: NSImage) {
        self.url = url
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        let imageView = NSImageView(frame: bounds)
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        toolTip = "\(url.lastPathComponent) — click to open, drag to share"
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { mouseDownPoint = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3 else { return }
        mouseDownPoint = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownPoint != nil else { return }
        mouseDownPoint = nil
        NSWorkspace.shared.open(url)
        onFinish?()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onFinish?()
    }
}
