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
}
