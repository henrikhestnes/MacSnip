import XCTest
@testable import MacSnipCore

final class RecentScreenshotsTests: XCTestCase {
    func entry(_ name: String, _ seconds: TimeInterval) -> RecentScreenshots.Entry {
        .init(url: URL(fileURLWithPath: "/shots/\(name)"), date: Date(timeIntervalSince1970: seconds))
    }

    func testNewestFirstPNGOnlyAndLimited() {
        let entries = [entry("a.png", 1), entry("b.PNG", 3), entry("notes.txt", 9), entry("c.png", 2), entry("d.png", 0)]
        XCTAssertEqual(RecentScreenshots.newest(entries, limit: 3).map(\.url.lastPathComponent), ["b.PNG", "c.png", "a.png"])
    }

    func testSameDateFallsBackToNameOrder() {
        let entries = [entry("2026-10-22_14.32.05.png", 5), entry("2026-10-22_14.32.06.png", 5)]
        XCTAssertEqual(RecentScreenshots.newest(entries, limit: 10).map(\.url.lastPathComponent),
                       ["2026-10-22_14.32.06.png", "2026-10-22_14.32.05.png"])
    }

    func testScanSkipsFoldersHiddenFilesAndMissingFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub.png"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["one.png", ".hidden.png", "two.jpg"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        XCTAssertEqual(RecentScreenshots.scan(folder: folder, limit: 10).map(\.url.lastPathComponent), ["one.png"])
        XCTAssertEqual(RecentScreenshots.scan(folder: folder.appendingPathComponent("missing"), limit: 10), [])
    }
}
