import Foundation

/// The newest PNGs in the save folder, read from disk each time so deleted or moved files drop out
/// and a changed save folder is picked up.
public enum RecentScreenshots {
    public struct Entry: Equatable {
        public let url: URL
        public let date: Date
        public init(url: URL, date: Date) { self.url = url; self.date = date }
    }

    /// Newest first; files with the same date fall back to name order, which is chronological for MacSnip names.
    public static func newest(_ entries: [Entry], limit: Int) -> [Entry] {
        Array(entries
            .filter { $0.url.pathExtension.lowercased() == "png" }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.url.lastPathComponent > $1.url.lastPathComponent }
            .prefix(max(limit, 0)))
    }

    public static func scan(folder: URL, limit: Int, fileManager: FileManager = .default) -> [Entry] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles]) else { return [] }
        let entries = urls.compactMap { url -> Entry? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            return Entry(url: url, date: values.creationDate ?? values.contentModificationDate ?? .distantPast)
        }
        return newest(entries, limit: limit)
    }
}
