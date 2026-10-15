//
//  FloorLevelTests.swift
//  BlueiotMinimalTests
//
//  `FloorLevel.matches(_:_:)`, the SDK rule the app compares floor levels
//  with: RouteConnector.swift, LevelChange.swift and LevelChangeOverlay.swift.
//
import XCTest
import Proximiio

final class FloorLevelTests: XCTestCase {

    /// Level 1.5 is a floor of its own. Rounding it gives level 2.
    func testMezzanineIsNotTheLevelAboveOrBelow() {
        XCTAssertTrue(FloorLevel.matches(1.5, 1.5))
        XCTAssertFalse(FloorLevel.matches(1.5, 2))
        XCTAssertFalse(FloorLevel.matches(1.5, 1))
    }

    func testLevelsWithinOneHundredthMatch() {
        XCTAssertTrue(FloorLevel.matches(2, 2.004))
        XCTAssertFalse(FloorLevel.matches(2, 2.05))
    }

    func testUnknownLevelMatchesAnyLevel() {
        XCTAssertTrue(FloorLevel.matches(nil, 2))
        XCTAssertTrue(FloorLevel.matches(1.5, nil))
        XCTAssertTrue(FloorLevel.matches(nil, nil))
    }
}
