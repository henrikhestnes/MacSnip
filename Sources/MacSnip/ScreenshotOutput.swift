import AppKit
import UniformTypeIdentifiers
import MacSnipCore

enum Preferences {
    private static let folderKey = "saveFolder"
    static let defaultFolder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Screenshots", isDirectory: true)

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: ["captureOnRelease": false, "playSound": true, "showThumbnail": true])
    }
    static var saveFolder: URL {
        get { UserDefaults.standard.string(forKey: folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultFolder }
        set { UserDefaults.standard.set(newValue.path, forKey: folderKey) }
    }
    /// Off matches Ubuntu: adjust the selection, then press Enter or the capture button.
    static var captureOnRelease: Bool {
        get { UserDefaults.standard.bool(forKey: "captureOnRelease") }
        set { UserDefaults.standard.set(newValue, forKey: "captureOnRelease") }
    }
    static var playSound: Bool {
        get { UserDefaults.standard.bool(forKey: "playSound") }
        set { UserDefaults.standard.set(newValue, forKey: "playSound") }
    }
    static var showThumbnail: Bool {
        get { UserDefaults.standard.bool(forKey: "showThumbnail") }
        set { UserDefaults.standard.set(newValue, forKey: "showThumbnail") }
    }
    static func resetAll() {
        for key in [folderKey, "captureOnRelease", "playSound", "showThumbnail"] { UserDefaults.standard.removeObject(forKey: key) }
    }
}

enum ScreenshotOutput {
    /// Copies to the clipboard first, so a failed save still leaves the image ready to paste.
    static func deliver(png: Data, image: CGImage, scale: CGFloat, folder: URL = Preferences.saveFolder,
                        date: Date = Date()) throws -> URL {
        copyToPasteboard(png: png, image: image, scale: scale)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = ScreenshotNaming.uniqueURL(in: folder, for: date)
        try png.write(to: url, options: .withoutOverwriting)
        return url
    }

    /// The DPI tag makes Retina captures open at their on-screen size, like macOS screenshots.
    static func pngData(_ image: CGImage, scale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        let dpi = 72 * scale
        CGImageDestinationAddImage(destination, image,
                                   [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static var tiffProvider: TIFFProvider?

    private static func copyToPasteboard(png: Data, image: CGImage, scale: CGFloat) {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        // TIFF is for older apps; it is large, so it is only encoded if something asks for it.
        let provider = TIFFProvider(image: image, scale: scale)
        item.setDataProvider(provider, forTypes: [.tiff])
        tiffProvider = provider
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    private final class TIFFProvider: NSObject, NSPasteboardItemDataProvider {
        let image: CGImage
        let scale: CGFloat
        init(image: CGImage, scale: CGFloat) { self.image = image; self.scale = scale }
        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            let rep = NSBitmapImageRep(cgImage: image)
            rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            if let tiff = rep.tiffRepresentation { item.setData(tiff, forType: type) }
        }
    }

    static func playShutter() {
        let directory = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/"
        for name in ["Screen Capture.aif", "Shutter.aif", "Grab.aif"] {
            if let sound = NSSound(contentsOfFile: directory + name, byReference: true) { sound.play(); return }
        }
    }
}
