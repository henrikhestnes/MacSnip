import AppKit
import ScreenCaptureKit
import MacSnipCore

/// One display as it looked when the capture shortcut was pressed. Frames are global AppKit points.
struct FrozenDisplay {
    let screen: NSScreen
    let frame: CGRect
    let scale: CGFloat
    let image: CGImage
}

struct WindowTarget {
    let id: CGWindowID
    let frame: CGRect
}

struct FrozenScreens {
    let displays: [FrozenDisplay]
    /// Ordinary app windows, front to back.
    let windows: [WindowTarget]
    let content: SCShareableContent
}

enum CaptureError: LocalizedError {
    case noDisplays, encodingFailed
    var errorDescription: String? {
        switch self {
        case .noDisplays: return "No displays could be captured."
        case .encodingFailed: return "The screenshot could not be encoded as PNG."
        }
    }
}

enum ScreenCapturer {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// AppKit's origin is the bottom-left of the primary display; Core Graphics uses its top-left.
    static func appKitRect(fromCoreGraphics rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    @MainActor
    static func freeze() async throws -> FrozenScreens {
        // Read window positions first; they are only needed for window mode.
        let windows = onScreenWindows()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApp = content.applications.filter { $0.processID == getpid() }
        let targets: [(screen: NSScreen, display: SCDisplay)] = NSScreen.screens.compactMap { screen in
            guard let id = displayID(of: screen), let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
            return (screen, display)
        }
        let images = try await withThrowingTaskGroup(of: (Int, CGImage).self) { group in
            for (index, target) in targets.enumerated() {
                let scale = target.screen.backingScaleFactor
                let size = target.screen.frame.size
                let filter = SCContentFilter(display: target.display, excludingApplications: ownApp, exceptingWindows: [])
                group.addTask {
                    let config = SCStreamConfiguration()
                    config.width = Int((size.width * scale).rounded())
                    config.height = Int((size.height * scale).rounded())
                    config.showsCursor = false
                    config.captureResolution = .best
                    return (index, try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config))
                }
            }
            var images: [Int: CGImage] = [:]
            for try await (index, image) in group { images[index] = image }
            return images
        }
        let displays = targets.enumerated().compactMap { index, target -> FrozenDisplay? in
            guard let image = images[index] else { return nil }
            return FrozenDisplay(screen: target.screen, frame: target.screen.frame,
                                 scale: target.screen.backingScaleFactor, image: image)
        }
        guard !displays.isEmpty else { throw CaptureError.noDisplays }
        return FrozenScreens(displays: displays, windows: windows, content: content)
    }

    private static func onScreenWindows() -> [WindowTarget] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let pid = getpid()
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != pid,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 40, rect.height >= 40 else { return nil }
            return WindowTarget(id: id, frame: appKitRect(fromCoreGraphics: rect))
        }
    }

    /// Captures the window by itself, so overlapping windows are not included.
    static func captureWindow(_ target: WindowTarget, content: SCShareableContent) async throws -> (CGImage, CGFloat) {
        guard let window = content.windows.first(where: { $0.windowID == target.id }) else { throw CaptureError.noDisplays }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true
        return (try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config), scale)
    }

    /// Cuts `selection` out of the frozen displays, stitching across displays when needed.
    static func image(of selection: CGRect, from displays: [FrozenDisplay]) -> (CGImage, CGFloat)? {
        let hits = displays.filter { $0.frame.intersects(selection) }
        if hits.count == 1, let display = hits.first {
            let pixels = SelectionGeometry.pixelRect(for: selection, displayFrame: display.frame, scale: display.scale)
            return display.image.cropping(to: pixels).map { ($0, display.scale) }
        }
        guard let scale = hits.map(\.scale).max() else { return nil }
        let width = Int((selection.width * scale).rounded()), height = Int((selection.height * scale).rounded())
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        func context(_ space: CGColorSpace) -> CGContext? {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let context = hits[0].image.colorSpace.flatMap(context) ?? context(srgb) else { return nil }
        context.interpolationQuality = .high
        for display in hits {
            context.draw(display.image, in: CGRect(x: (display.frame.minX - selection.minX) * scale,
                                                   y: (display.frame.minY - selection.minY) * scale,
                                                   width: display.frame.width * scale,
                                                   height: display.frame.height * scale))
        }
        return context.makeImage().map { ($0, scale) }
    }
}
