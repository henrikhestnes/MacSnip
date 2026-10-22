import XCTest
@testable import MacSnipCore

final class NamingTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        components.timeZone = utc
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    func testNameIsZeroPaddedLargestUnitFirst() {
        XCTAssertEqual(ScreenshotNaming.baseName(for: date(2026, 3, 7, 9, 5, 4), timeZone: utc), "2026-03-07_09.05.04")
    }

    func testAlphabeticalOrderIsChronological() {
        let dates = [date(2025, 12, 31, 23, 59, 59), date(2026, 1, 2, 9, 0, 0), date(2026, 1, 2, 14, 0, 0),
                     date(2026, 10, 1, 8, 30, 0), date(2026, 10, 22, 8, 5, 0), date(2026, 10, 22, 14, 32, 5)]
        let names = dates.map { ScreenshotNaming.baseName(for: $0, timeZone: utc) + ".png" }
        XCTAssertEqual(names.sorted(), names)
        XCTAssertEqual(names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, names) // Finder order
    }

    func testCollisionUsesNextFreeSecond() {
        let folder = URL(fileURLWithPath: "/shots")
        let taken: Set = ["/shots/2026-10-22_14.32.05.png", "/shots/2026-10-22_14.32.06.png"]
        let url = ScreenshotNaming.uniqueURL(in: folder, for: date(2026, 10, 22, 14, 32, 5), timeZone: utc) { taken.contains($0.path) }
        XCTAssertEqual(url.lastPathComponent, "2026-10-22_14.32.07.png")
    }
}

final class SelectionGeometryTests: XCTestCase {
    let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    func testCornerResizeKeepsOppositeCorner() {
        XCTAssertEqual(SelectionHandle.topRight.resize(rect, to: CGPoint(x: 350, y: 260)),
                       CGRect(x: 100, y: 100, width: 250, height: 160))
    }

    func testEdgeResizeOnlyChangesOneAxis() {
        XCTAssertEqual(SelectionHandle.left.resize(rect, to: CGPoint(x: 50, y: 999)),
                       CGRect(x: 50, y: 100, width: 250, height: 100))
    }

    func testResizePastOppositeEdgeFlips() {
        XCTAssertEqual(SelectionHandle.right.resize(rect, to: CGPoint(x: 40, y: 0)),
                       CGRect(x: 40, y: 100, width: 60, height: 100))
    }

    func testHandleHitTestPrefersCorners() {
        let tiny = CGRect(x: 0, y: 0, width: 4, height: 4)
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 0, y: 0), in: tiny, radius: 8), .bottomLeft)
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 200, y: 201), in: rect, radius: 8), .top)
        XCTAssertNil(SelectionGeometry.handle(at: CGPoint(x: 200, y: 150), in: rect, radius: 8))
    }

    func testMoveStopsAtBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertEqual(SelectionGeometry.move(rect, by: CGVector(dx: 500, dy: -500), within: bounds),
                       CGRect(x: 200, y: 0, width: 200, height: 100))
    }

    func testSnapRoundsOutwardToPixels() {
        let snapped = SelectionGeometry.snap(CGRect(x: 10.3, y: 10.8, width: 5.1, height: 5.1), scale: 2)
        XCTAssertEqual(snapped, CGRect(x: 10, y: 10.5, width: 5.5, height: 5.5))
    }

    func testPixelRectFlipsToImageCoordinates() {
        let display = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let selection = CGRect(x: -1340, y: 700, width: 100, height: 100)
        XCTAssertEqual(SelectionGeometry.pixelRect(for: selection, displayFrame: display, scale: 2),
                       CGRect(x: 200, y: 200, width: 200, height: 200))
    }
}
