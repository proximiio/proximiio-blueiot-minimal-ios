//
//  LevelChangeTests.swift
//  BlueiotMinimalTests
//
//  `LevelChangeDetector`, `LiftDetector`, `LiftArea` and the card text. The
//  card view is not tested.
//
import XCTest
@testable import BlueiotMinimal
import Proximiio
import ProximiioMap

final class LevelChangeTests: XCTestCase {

    // MARK: Floor change

    func testFirstFloorIsNoChange() {
        var detector = LevelChangeDetector()
        XCTAssertNil(detector.update(level: 1))
        XCTAssertEqual(detector.level, 1)
    }

    func testDefaultChangesOnTheFirstFixOnTheNewFloor() {
        var detector = LevelChangeDetector()
        _ = detector.update(level: 1)
        XCTAssertEqual(detector.update(level: 2), LevelChange(from: 1, to: 2))
        XCTAssertNil(detector.update(level: 2))
    }

    func testChangeNeedsTwoFixesOnTheNewFloor() {
        var detector = LevelChangeDetector(confirmations: 2)
        _ = detector.update(level: 1)
        XCTAssertNil(detector.update(level: 2))
        XCTAssertEqual(detector.update(level: 2), LevelChange(from: 1, to: 2))
        XCTAssertNil(detector.update(level: 2))
    }

    func testSingleFixOnAnotherFloorIsIgnored() {
        var detector = LevelChangeDetector(confirmations: 2)
        _ = detector.update(level: 1)
        XCTAssertNil(detector.update(level: 2))
        XCTAssertNil(detector.update(level: 1))
        XCTAssertNil(detector.update(level: 2))
        XCTAssertEqual(detector.level, 1)
    }

    func testDirectionAndMissingFloor() {
        var detector = LevelChangeDetector()
        _ = detector.update(level: 4)
        XCTAssertNil(detector.update(level: nil))
        let change = detector.update(level: 2.0001)
        XCTAssertEqual(change, LevelChange(from: 4, to: 2))
        XCTAssertEqual(change?.isUp, false)
    }

    // MARK: Lift ride

    private static let start = Date(timeIntervalSinceReferenceDate: 0)

    /// A field log: 1 s fixes inside the lift, then the new floor.
    func testStandingInTheLiftBoardsAfterTheDwell() {
        var lift = LiftDetector()
        XCTAssertNil(lift.update(inLift: false, at: Self.start))
        XCTAssertNil(lift.update(inLift: true, at: Self.start + 1))
        XCTAssertNil(lift.update(inLift: true, at: Self.start + 2))
        XCTAssertNil(lift.update(inLift: true, at: Self.start + 3))
        XCTAssertEqual(lift.update(inLift: true, at: Self.start + 4), .boarded)
        XCTAssertNil(lift.update(inLift: true, at: Self.start + 5))
        XCTAssertTrue(lift.isRiding)
    }

    /// A field log: two fixes inside another lift while walking.
    func testWalkingThroughALiftIsNoRide() {
        var lift = LiftDetector()
        XCTAssertNil(lift.update(inLift: true, at: Self.start))
        XCTAssertNil(lift.update(inLift: true, at: Self.start + 1))
        XCTAssertNil(lift.update(inLift: false, at: Self.start + 2))
        XCTAssertNil(lift.update(inLift: false, at: Self.start + 3))
        XCTAssertNil(lift.update(inLift: true, at: Self.start + 4))
        XCTAssertFalse(lift.isRiding)
    }

    func testLeavingTheLiftEndsTheRideAfterTwoFixesOutside() {
        var lift = LiftDetector()
        _ = lift.update(inLift: true, at: Self.start)
        XCTAssertEqual(lift.update(inLift: true, at: Self.start + 3), .boarded)
        XCTAssertNil(lift.update(inLift: false, at: Self.start + 4))
        XCTAssertNil(lift.update(inLift: true, at: Self.start + 5))
        XCTAssertNil(lift.update(inLift: false, at: Self.start + 6))
        XCTAssertEqual(lift.update(inLift: false, at: Self.start + 7), .left)
        XCTAssertFalse(lift.isRiding)
    }

    // MARK: Lift area

    private func square(_ type: String = "elevator", geometry: String = "Polygon") -> ProximiioFeature {
        let ring: JSONValue = .array([
            [17.0, 48.0], [17.001, 48.0], [17.001, 48.001], [17.0, 48.001], [17.0, 48.0],
        ].map { .array([.number($0[0]), .number($0[1])]) })
        let coordinates: JSONValue = geometry == "Polygon" ? .array([ring]) : .array([.array([ring])])
        return ProximiioFeature(
            id: type,
            geometry: ProximiioFeature.Geometry(type: geometry, coordinates: coordinates),
            properties: .object(["type": .string(type)])
        )
    }

    func testLiftAreasAreElevatorPolygons() {
        let lifts = LiftArea.all(features: [square(), square(geometry: "MultiPolygon"), square("poi")])
        XCTAssertEqual(lifts.count, 2)
        XCTAssertTrue(lifts[0].contains(MapCoordinate(latitude: 48.0005, longitude: 17.0005)))
        XCTAssertFalse(lifts[0].contains(MapCoordinate(latitude: 48.002, longitude: 17.0005)))
        XCTAssertTrue(lifts[1].contains(MapCoordinate(latitude: 48.0005, longitude: 17.0005)))
    }

    // MARK: Card

    func testCardText() {
        XCTAssertEqual(LevelChangeCard(phase: .riding, from: 0, to: nil).title, "In the lift")
        XCTAssertEqual(LevelChangeCard(phase: .riding, from: 0, to: 2).title, "Going to level 2")
        XCTAssertEqual(LevelChangeCard(phase: .riding, from: 0, to: 2).symbol, "arrow.up")
        XCTAssertEqual(LevelChangeCard(phase: .arrived, from: 2, to: 1).title, "Level 1")
        XCTAssertEqual(LevelChangeCard(phase: .arrived, from: 2, to: 1).symbol, "arrow.down")
    }
}
