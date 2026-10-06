//
//  PositionSmoothingSettingTests.swift
//  BlueiotMinimalTests
//
//  The "Smooth position" switch and the map smoothing it selects. A wrong
//  mapping fails silently: the dot is smoothed while a tester compares raw
//  positions, or jumps for a visitor. The registered default must match the
//  `DefaultValue` in Settings.bundle, because iOS shows that value in the
//  Settings app but does not store it.
//
import XCTest
@testable import BlueiotMinimal
import ProximiioMap

final class PositionSmoothingSettingTests: XCTestCase {

    /// An empty defaults domain per test, so the simulator's stored value does
    /// not affect the result.
    private func freshDefaults() throws -> UserDefaults {
        let suite = "PositionSmoothingSettingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testUnchangedSwitchSmooths() throws {
        let defaults = try freshDefaults()
        PositionSmoothingSetting.register(in: defaults)
        XCTAssertEqual(PositionSmoothingSetting.smoothing(in: defaults), .adaptive)
    }

    func testSwitchOffDrawsEachFix() throws {
        let defaults = try freshDefaults()
        PositionSmoothingSetting.register(in: defaults)
        defaults.set(false, forKey: PositionSmoothingSetting.key)
        XCTAssertEqual(PositionSmoothingSetting.smoothing(in: defaults), .none)
    }

    func testSwitchBackOnSmooths() throws {
        let defaults = try freshDefaults()
        PositionSmoothingSetting.register(in: defaults)
        defaults.set(false, forKey: PositionSmoothingSetting.key)
        defaults.set(true, forKey: PositionSmoothingSetting.key)
        XCTAssertEqual(PositionSmoothingSetting.smoothing(in: defaults), .adaptive)
    }

    /// Settings.bundle is in the app, which hosts these tests. Its switch must
    /// use the same key and default as `PositionSmoothingSetting`.
    func testSettingsBundleMatchesRegisteredDefault() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Root", withExtension: "plist", subdirectory: "Settings.bundle"))
        let root = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
        let specifiers = try XCTUnwrap(root["PreferenceSpecifiers"] as? [[String: Any]])
        let toggle = try XCTUnwrap(specifiers.first { $0["Key"] as? String == PositionSmoothingSetting.key })
        XCTAssertEqual(toggle["Type"] as? String, "PSToggleSwitchSpecifier")
        XCTAssertEqual(toggle["DefaultValue"] as? Bool, PositionSmoothingSetting.defaultValue)
    }

    // MARK: - Smoothing values

    func testNumberAcceptsDotAndComma() {
        XCTAssertEqual(PositionSmoothingSetting.number(from: "0.75"), 0.75)
        XCTAssertEqual(PositionSmoothingSetting.number(from: "0,75"), 0.75)
        XCTAssertEqual(PositionSmoothingSetting.number(from: " 2 "), 2)
        XCTAssertEqual(PositionSmoothingSetting.number(from: NSNumber(value: 1.5)), 1.5)
    }

    func testNumberIgnoresEmptyAndInvalidText() {
        XCTAssertNil(PositionSmoothingSetting.number(from: nil))
        XCTAssertNil(PositionSmoothingSetting.number(from: ""))
        XCTAssertNil(PositionSmoothingSetting.number(from: "   "))
        XCTAssertNil(PositionSmoothingSetting.number(from: "abc"))
        XCTAssertNil(PositionSmoothingSetting.number(from: "1,2,3"))
        XCTAssertNil(PositionSmoothingSetting.number(from: "nan"))
        XCTAssertNil(PositionSmoothingSetting.number(from: "inf"))
    }

    func testEmptyFieldsGiveTheMapDefault() throws {
        let defaults = try freshDefaults()
        PositionSmoothingSetting.register(in: defaults)
        XCTAssertEqual(PositionSmoothingSetting.tuning(in: defaults), .default)
    }

    func testEnteredValuesAreUsed() throws {
        let defaults = try freshDefaults()
        defaults.set("1,5", forKey: PositionSmoothingSetting.Knob.deadBandMeters.rawValue)
        defaults.set("0.2", forKey: PositionSmoothingSetting.Knob.positionSettlingSeconds.rawValue)
        let tuning = PositionSmoothingSetting.tuning(in: defaults)
        XCTAssertEqual(tuning.deadBandMeters, 1.5)
        XCTAssertEqual(tuning.positionSettlingSeconds, 0.2)
        XCTAssertEqual(tuning.windowSeconds, PositionSmoothingTuning.default.windowSeconds)
    }

    func testInvalidValueFallsBackToDefault() throws {
        let defaults = try freshDefaults()
        defaults.set("fast", forKey: PositionSmoothingSetting.Knob.walkSmoothingSeconds.rawValue)
        defaults.set("", forKey: PositionSmoothingSetting.Knob.deadBandMeters.rawValue)
        XCTAssertEqual(PositionSmoothingSetting.tuning(in: defaults), .default)
    }

    /// The app passes a negative value through. The map raises it to 0, and the
    /// window to its 0.5 s minimum.
    func testNegativeValueIsClampedByTheMap() throws {
        let defaults = try freshDefaults()
        defaults.set("-1", forKey: PositionSmoothingSetting.Knob.deadBandMeters.rawValue)
        defaults.set("-2,5", forKey: PositionSmoothingSetting.Knob.windowSeconds.rawValue)
        let tuning = PositionSmoothingSetting.tuning(in: defaults)
        XCTAssertEqual(tuning.deadBandMeters, 0)
        XCTAssertEqual(tuning.windowSeconds, 0.5)
    }

    func testResetEmptiesTheValuesAndTurnsItselfOff() throws {
        let defaults = try freshDefaults()
        PositionSmoothingSetting.register(in: defaults)
        for knob in PositionSmoothingSetting.Knob.allCases {
            defaults.set("0,1", forKey: knob.rawValue)
        }
        XCTAssertFalse(PositionSmoothingSetting.resetTuningIfRequested(in: defaults))
        XCTAssertNotEqual(PositionSmoothingSetting.tuning(in: defaults), .default)

        defaults.set(true, forKey: PositionSmoothingSetting.resetKey)
        XCTAssertTrue(PositionSmoothingSetting.resetTuningIfRequested(in: defaults))
        XCTAssertFalse(defaults.bool(forKey: PositionSmoothingSetting.resetKey))
        XCTAssertEqual(PositionSmoothingSetting.tuning(in: defaults), .default)
        for knob in PositionSmoothingSetting.Knob.allCases {
            XCTAssertNil(defaults.object(forKey: knob.rawValue))
        }
    }

    /// Each value has a text field with the same key, and its title shows the
    /// map default. The reset switch is off by default.
    func testSettingsBundleListsEveryValue() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Root", withExtension: "plist", subdirectory: "Settings.bundle"))
        let root = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
        let specifiers = try XCTUnwrap(root["PreferenceSpecifiers"] as? [[String: Any]])
        for knob in PositionSmoothingSetting.Knob.allCases {
            let field = try XCTUnwrap(specifiers.first { $0["Key"] as? String == knob.rawValue }, knob.rawValue)
            XCTAssertEqual(field["Type"] as? String, "PSTextFieldSpecifier")
            XCTAssertNil(field["DefaultValue"], knob.rawValue)
            let title = try XCTUnwrap(field["Title"] as? String)
            XCTAssertTrue(title.hasSuffix("default \(String(format: "%g", knob.defaultValue))"), title)
        }
        let reset = try XCTUnwrap(specifiers.first { $0["Key"] as? String == PositionSmoothingSetting.resetKey })
        XCTAssertEqual(reset["Type"] as? String, "PSToggleSwitchSpecifier")
        XCTAssertEqual(reset["DefaultValue"] as? Bool, false)
    }

    func testSummaryListsTheTuningWhenOn() {
        var style = PositionStyle()
        XCTAssertTrue(PositionSmoothingSetting.summary(of: style).hasSuffix("(defaults)"))
        style.smoothingTuning = PositionSmoothingTuning(deadBandMeters: 0.2)
        XCTAssertTrue(PositionSmoothingSetting.summary(of: style).contains("dead band 0.2 m"))
        style.smoothing = .none
        XCTAssertEqual(PositionSmoothingSetting.summary(of: style), "position smoothing: off")
    }
}
