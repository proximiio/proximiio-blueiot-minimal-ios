//
//  WristbandIDTests.swift
//  BlueiotMinimalTests
//
//  The spelling rule and its persistence, and nothing else. These two are worth
//  testing because they fail silently: a wristband read one way here and another way
//  by the relay matches nothing, and the symptom is "the dot never arrives" rather
//  than an error. The screens are not tested — they have no logic to get wrong.
//
import XCTest
@testable import BlueiotMinimal

final class WristbandIDTests: XCTestCase {

    // MARK: - Spelling

    /// The number printed on a real band, as it reads.
    func testBareNumberIsDecimal() {
        XCTAssertEqual(WristbandID(text: "1000045550")?.value, 1_000_045_550)
        // And specifically NOT hex: 0x1000045550 would be 68_723_244_368.
        XCTAssertEqual(WristbandID(text: "5555")?.value, 5555)
    }

    /// The three spellings of one tag all name it.
    func testEverySpellingOfOneTagAgrees() {
        let decimal = WristbandID(text: "7001")
        XCTAssertEqual(WristbandID(text: "0x1B59"), decimal)
        XCTAssertEqual(WristbandID(text: "0000000000001B59"), decimal)
        XCTAssertEqual(decimal?.value, 7001)
    }

    /// Letters can only be hex, whatever case they arrive in.
    func testLettersAreHex() {
        XCTAssertEqual(WristbandID(text: "3B9B7BEE")?.value, 1_000_045_550)
        XCTAssertEqual(WristbandID(text: "3b9b7bee")?.value, 1_000_045_550)
        XCTAssertEqual(WristbandID(text: "0X3B9B7BEE")?.value, 1_000_045_550)
    }

    /// Pasted ids carry whitespace; that is not a typo.
    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(WristbandID(text: "  1000045550\n")?.value, 1_000_045_550)
    }

    /// Whatever spelling came in, one goes out — decimal, the band's own.
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

    /// A value an earlier build wrote in another spelling still names the same tag,
    /// because loading re-reads it through the rule instead of trusting characters.
    func testAStoredForeignSpellingStillNamesTheSameTag() throws {
        let defaults = try freshDefaults()
        defaults.set("0x1B59", forKey: "WristbandID")

        XCTAssertEqual(WristbandStore.load(from: defaults)?.value, 7001)
    }

    func testNothingStoredMeansNoWristband() throws {
        XCTAssertNil(WristbandStore.load(from: try freshDefaults()))
    }

    /// A suite of its own, so a test never reads or writes the app's real store.
    private func freshDefaults() throws -> UserDefaults {
        let name = "WristbandIDTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}
