//
//  WristbandIDTests.swift
//  BlueiotMinimalTests
//
//  The parsing rule and its persistence. Both fail silently: an id parsed
//  differently here and by the relay matches no tag, and no position arrives.
//  The views are not tested.
//
import XCTest
@testable import BlueiotMinimal

final class WristbandIDTests: XCTestCase {

    // MARK: - Spelling

    /// The number printed on a band is read as decimal.
    func testBareNumberIsDecimal() {
        XCTAssertEqual(WristbandID(text: "1000045550")?.value, 1_000_045_550)
        // Not hexadecimal: 0x1000045550 would be 68_723_244_368.
        XCTAssertEqual(WristbandID(text: "5555")?.value, 5555)
    }

    /// The three spellings of one tag parse to the same id.
    func testEverySpellingOfOneTagAgrees() {
        let decimal = WristbandID(text: "7001")
        XCTAssertEqual(WristbandID(text: "0x1B59"), decimal)
        XCTAssertEqual(WristbandID(text: "0000000000001B59"), decimal)
        XCTAssertEqual(decimal?.value, 7001)
    }

    /// Letters are hexadecimal in either case.
    func testLettersAreHex() {
        XCTAssertEqual(WristbandID(text: "3B9B7BEE")?.value, 1_000_045_550)
        XCTAssertEqual(WristbandID(text: "3b9b7bee")?.value, 1_000_045_550)
        XCTAssertEqual(WristbandID(text: "0X3B9B7BEE")?.value, 1_000_045_550)
    }

    /// Pasted ids may carry surrounding whitespace.
    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(WristbandID(text: "  1000045550\n")?.value, 1_000_045_550)
    }

    /// The canonical spelling is decimal regardless of the input spelling.
    func testCanonicalSpellingIsDecimal() {
        XCTAssertEqual(WristbandID(text: "0x1B59")?.canonical, "7001")
        XCTAssertEqual(WristbandID(text: "0x1B59")?.hexadecimal, "0x1B59")
    }

    func testTextThatNamesNoTagIsRefused() {
        XCTAssertNil(WristbandID(text: ""))
        XCTAssertNil(WristbandID(text: "   "))
        XCTAssertNil(WristbandID(text: "-5"))
        XCTAssertNil(WristbandID(text: "band 7001"))
        XCTAssertNil(WristbandID(text: "0x"))
        XCTAssertFalse(WristbandID.isValid("not a band"))
        XCTAssertTrue(WristbandID.isValid("7001"))
    }

    // MARK: - Persistence

    func testSavedIDSurvivesAndComesBackCanonical() throws {
        let defaults = try freshDefaults()
        let typed = try XCTUnwrap(WristbandID(text: "0x1B59"))

        WristbandStore.save(typed, to: defaults)

        XCTAssertEqual(defaults.string(forKey: "WristbandID"), "7001", "the store holds the band's own spelling")
        XCTAssertEqual(WristbandStore.load(from: defaults), typed)
    }

    /// A value an earlier build wrote in another spelling parses to the same tag,
    /// because `load` re-parses it.
    func testAStoredForeignSpellingStillNamesTheSameTag() throws {
        let defaults = try freshDefaults()
        defaults.set("0x1B59", forKey: "WristbandID")

        XCTAssertEqual(WristbandStore.load(from: defaults)?.value, 7001)
    }

    func testNothingStoredMeansNoWristband() throws {
        XCTAssertNil(WristbandStore.load(from: try freshDefaults()))
    }

    /// A separate suite, so a test never reads or writes the app's store.
    private func freshDefaults() throws -> UserDefaults {
        let name = "WristbandIDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}
