import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var chunks = Data()
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
let types = [16: ["icp4", "ic11"], 32: ["icp5", "ic12"], 128: ["ic07", "ic13"],
             256: ["ic08", "ic14"], 512: ["ic09", "ic10"]]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 210, yRadius: 210)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.18, blue: 0.27, alpha: 1),
                                  ending: NSColor(srgbRed: 0.07, green: 0.08, blue: 0.13, alpha: 1))!
        gradient.draw(in: background, angle: -60)
        // A dimmed screen with a bright selection, like the capture overlay.
        context.setFillColor(NSColor(srgbRed: 0.45, green: 0.75, blue: 1, alpha: 1).cgColor)
        context.fill(CGRect(x: 330, y: 330, width: 364, height: 364))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(44)
        let (low, high, arm): (CGFloat, CGFloat, CGFloat) = (230, 794, 150)
        for (x, y, dx, dy) in [(low, low, 1.0, 1.0), (high, low, -1.0, 1.0), (high, high, -1.0, -1.0), (low, high, 1.0, -1.0)] {
            context.move(to: CGPoint(x: x + dx * arm, y: y))
            context.addLine(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: x, y: y + dy * arm))
        }
        context.strokePath()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        // Modern ICNS entries contain PNG data. Write the container directly so the
        // build also works where iconutil's image conversion service is unavailable.
        chunks.append(Data(types[size]![scale - 1].utf8))
        chunks.append(bigEndian(png.count + 8))
        chunks.append(png)
    }
}
var icon = Data("icns".utf8)
icon.append(bigEndian(chunks.count + 8))
icon.append(chunks)
try icon.write(to: directory.deletingLastPathComponent().appendingPathComponent("AppIcon.icns"))
