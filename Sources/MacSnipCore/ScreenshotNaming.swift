import Foundation

public enum ScreenshotNaming {
    /// yyyy-MM-dd_HH.mm.ss, e.g. 2026-10-22_14.32.05. Largest unit first, zero-padded, 24-hour clock,
    /// so alphabetical order is chronological. Dots stand in for ":", which Finder shows as "/".
    public static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        return String(format: "%04d", c.year ?? 0) + "-\(two(c.month))-\(two(c.day))_\(two(c.hour)).\(two(c.minute)).\(two(c.second))"
    }

    /// If a name is taken, the next free second is used instead of adding a suffix,
    /// so names stay unique and still sort in the order they were taken.
    public static func uniqueURL(in folder: URL, for date: Date, timeZone: TimeZone = .current,
                                 fileExtension: String = "png",
                                 exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        var date = date
        while true {
            let url = folder.appendingPathComponent(baseName(for: date, timeZone: timeZone)).appendingPathExtension(fileExtension)
            if !exists(url) { return url }
            date += 1
        }
    }
}
