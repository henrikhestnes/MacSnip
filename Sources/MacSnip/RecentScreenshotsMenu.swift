import AppKit
import ImageIO
import MacSnipCore

/// The "Recent Screenshots" submenu: click to copy a screenshot again, ⌥-click to show it in Finder.
final class RecentScreenshotsMenu: NSObject, NSMenuDelegate {
    static let limit = 10
    private static let thumbnailSize = NSSize(width: 64, height: 40)

    let menu = NSMenu(title: "Recent Screenshots")
    private let cache = NSCache<NSURL, NSImage>()
    private let queue = DispatchQueue(label: "MacSnip.thumbnails", qos: .userInitiated)
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    override init() {
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
    }

    /// Seeds the cache from a fresh capture, so its thumbnail is ready without decoding the file again.
    func remember(png: Data, url: URL) {
        queue.async { [weak self] in
            guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                  let image = Self.thumbnail(from: source) else { return }
            DispatchQueue.main.async { self?.cache.setObject(image, forKey: url as NSURL) }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let entries = RecentScreenshots.scan(folder: Preferences.saveFolder, limit: Self.limit)
        if entries.isEmpty {
            let empty = NSMenuItem(title: "No Screenshots Yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for entry in entries {
            let title = dateFormatter.string(from: entry.date)
            let copy = NSMenuItem(title: title, action: #selector(copyScreenshot(_:)), keyEquivalent: "")
            copy.keyEquivalentModifierMask = []
            copy.toolTip = "\(entry.url.lastPathComponent) — click to copy, ⌥-click to show in Finder"
            let reveal = NSMenuItem(title: "Show in Finder: \(title)", action: #selector(revealScreenshot(_:)), keyEquivalent: "")
            reveal.keyEquivalentModifierMask = .option
            reveal.isAlternate = true
            for item in [copy, reveal] {
                item.target = self
                item.representedObject = entry.url
                menu.addItem(item)
            }
            setThumbnail(for: entry.url, on: [copy, reveal])
        }
    }

    private func setThumbnail(for url: URL, on items: [NSMenuItem]) {
        if let cached = cache.object(forKey: url as NSURL) {
            items.forEach { $0.image = cached }
            return
        }
        items.forEach { $0.image = Self.placeholder }
        // Decoding a full-size PNG can take tens of milliseconds, so the menu opens first and fills in.
        queue.async { [weak self, weak first = items.first, weak second = items.last] in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = Self.thumbnail(from: source) else { return }
            DispatchQueue.main.async {
                self?.cache.setObject(image, forKey: url as NSURL)
                first?.image = image
                second?.image = image
            }
        }
    }

    /// Fixed-size canvas so every title lines up, whatever the screenshot's aspect ratio.
    private static func thumbnail(from source: CGImageSource) -> NSImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: Int(thumbnailSize.width * 2)]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let size = thumbnailSize
        return NSImage(size: size, flipped: false) { bounds in
            let fit = min(bounds.width / CGFloat(cgImage.width), bounds.height / CGFloat(cgImage.height))
            let drawn = NSSize(width: CGFloat(cgImage.width) * fit, height: CGFloat(cgImage.height) * fit)
            let rect = NSRect(x: (bounds.width - drawn.width) / 2, y: (bounds.height - drawn.height) / 2,
                              width: drawn.width, height: drawn.height)
            NSGraphicsContext.current?.imageInterpolation = .high
            NSImage(cgImage: cgImage, size: drawn).draw(in: rect)
            NSColor.separatorColor.setStroke()
            NSBezierPath(rect: rect.insetBy(dx: 0.25, dy: 0.25)).stroke()
            return true
        }
    }

    private static let placeholder = NSImage(size: thumbnailSize, flipped: false) { bounds in
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 2), xRadius: 3, yRadius: 3).fill()
        return true
    }

    @objc private func copyScreenshot(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, ScreenshotOutput.copyToPasteboard(fileAt: url) else { NSSound.beep(); return }
    }

    @objc private func revealScreenshot(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
