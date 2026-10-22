import CoreGraphics

public enum SelectionHandle: CaseIterable {
    case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left

    private enum Edge { case min, max, none }
    private var horizontal: Edge {
        switch self {
        case .bottomLeft, .topLeft, .left: return .min
        case .bottomRight, .topRight, .right: return .max
        case .bottom, .top: return .none
        }
    }
    private var vertical: Edge {
        switch self {
        case .bottomLeft, .bottom, .bottomRight: return .min
        case .topLeft, .top, .topRight: return .max
        case .left, .right: return .none
        }
    }

    public func point(in rect: CGRect) -> CGPoint {
        func value(_ edge: Edge, _ min: CGFloat, _ mid: CGFloat, _ max: CGFloat) -> CGFloat {
            switch edge { case .min: return min; case .max: return max; case .none: return mid }
        }
        return CGPoint(x: value(horizontal, rect.minX, rect.midX, rect.maxX),
                       y: value(vertical, rect.minY, rect.midY, rect.maxY))
    }

    /// Drags this handle to `point`, keeping the opposite edges fixed. Dragging past them flips the selection.
    public func resize(_ rect: CGRect, to point: CGPoint) -> CGRect {
        func span(_ edge: Edge, _ min: CGFloat, _ max: CGFloat, _ p: CGFloat) -> (CGFloat, CGFloat) {
            switch edge { case .min: return (max, p); case .max: return (min, p); case .none: return (min, max) }
        }
        let (x0, x1) = span(horizontal, rect.minX, rect.maxX, point.x)
        let (y0, y1) = span(vertical, rect.minY, rect.maxY, point.y)
        return SelectionGeometry.rect(from: CGPoint(x: x0, y: y0), to: CGPoint(x: x1, y: y1))
    }
}

public enum SelectionGeometry {
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Prefers corners over edges when handles overlap on a small selection.
    public static func handle(at point: CGPoint, in rect: CGRect, radius: CGFloat) -> SelectionHandle? {
        let corners: [SelectionHandle] = [.bottomLeft, .bottomRight, .topRight, .topLeft]
        let edges: [SelectionHandle] = [.bottom, .right, .top, .left]
        for handle in corners + edges {
            let p = handle.point(in: rect)
            if hypot(p.x - point.x, p.y - point.y) <= radius { return handle }
        }
        return nil
    }

    public static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// Moves without resizing, stopping at the edges of `bounds`.
    public static func move(_ rect: CGRect, by delta: CGVector, within bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: delta.dx, dy: delta.dy)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return moved
    }

    /// Rounds outward to whole device pixels so the saved image matches what was highlighted.
    public static func snap(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = (rect.minX * scale).rounded(.down) / scale
        let minY = (rect.minY * scale).rounded(.down) / scale
        let maxX = (rect.maxX * scale).rounded(.up) / scale
        let maxY = (rect.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Pixel rectangle inside a display image (top-left origin) for a selection in global bottom-left coordinates.
    public static func pixelRect(for selection: CGRect, displayFrame: CGRect, scale: CGFloat) -> CGRect {
        let local = selection.intersection(displayFrame)
        guard !local.isNull else { return .null }
        return CGRect(x: ((local.minX - displayFrame.minX) * scale).rounded(),
                      y: ((displayFrame.maxY - local.maxY) * scale).rounded(),
                      width: (local.width * scale).rounded(),
                      height: (local.height * scale).rounded())
    }
}
