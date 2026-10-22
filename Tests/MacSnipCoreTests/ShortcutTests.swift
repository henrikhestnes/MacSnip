import XCTest
@testable import MacSnipCore

final class ShortcutTests: XCTestCase {
    func testDefaultIsHyperPWithAndWithoutShift() {
        let config = ShortcutConfiguration.defaults
        XCTAssertNil(config.validationError)
        XCTAssertEqual(config.capture.display, "Hyper+P")
        XCTAssertEqual(Set(config.registeredShortcuts), [
            KeyboardShortcut(35, [.control, .option, .command]),
            KeyboardShortcut(35, [.control, .option, .command, .shift])
        ])
    }

    func testRecordingShiftedHyperStillRegistersBothVariants() {
        let config = ShortcutConfiguration(capture: KeyboardShortcut(1, .all))
        XCTAssertEqual(config.capture.display, "Hyper+S")
        XCTAssertEqual(config.registeredShortcuts.count, 2)
    }

    func testOrdinaryShortcutRegistersOnce() {
        let shortcut = KeyboardShortcut(23, [.command, .shift])
        let config = ShortcutConfiguration(capture: shortcut)
        XCTAssertNil(config.validationError)
        XCTAssertEqual(config.registeredShortcuts, [shortcut])
        XCTAssertEqual(shortcut.display, "⇧⌘5")
    }

    func testShortcutNeedsModifierUnlessFunctionKey() {
        for shortcut in [KeyboardShortcut(35), KeyboardShortcut(35, .shift), .escape, KeyboardShortcut(12, .command)] {
            XCTAssertNotNil(ShortcutConfiguration(capture: shortcut).validationError, shortcut.display)
        }
        XCTAssertNil(ShortcutConfiguration(capture: KeyboardShortcut(105)).validationError) // F13
    }

    func testPersistenceRoundTripsAndRejectsInvalid() {
        let defaults = UserDefaults(suiteName: "MacSnipTests-\(UUID())")!
        XCTAssertEqual(ShortcutConfiguration.load(from: defaults), .defaults)
        let custom = ShortcutConfiguration(capture: KeyboardShortcut(1, [.control, .shift]))
        custom.save(to: defaults)
        XCTAssertEqual(ShortcutConfiguration.load(from: defaults), custom)
    }

    func testConflictsReportRegisteredVariants() {
        let reserved: Set = [KeyboardShortcut(35, .all)]
        XCTAssertEqual(ShortcutConfiguration.defaults.conflicts(with: reserved), [KeyboardShortcut(35, .all)])
    }
}
