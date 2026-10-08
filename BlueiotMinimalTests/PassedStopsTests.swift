//
//  PassedStopsTests.swift
//  BlueiotMinimalTests
//
//  `PassedStops`: when a stop the visitor walked past counts as passed, and the
//  arrival and advance rules of a visit.
//
import XCTest
@testable import BlueiotMinimal
import ProximiioMap

final class PassedStopsTests: XCTestCase {

    /// 1 m north of the test origin is 1 / 111 000 degree of latitude.
    private static func point(north meters: Double) -> MapCoordinate {
        MapCoordinate(latitude: 24.5 + meters / 111_000, longitude: 54.4)
    }

    private let stops = [
        JourneyStop(id: "a", title: "A", coordinate: point(north: 0), floor: FloorKey(level: 1)),
        JourneyStop(id: "b", title: "B", coordinate: point(north: 30), floor: FloorKey(level: 2)),
    ]

    private func update(_ detector: inout PassedStops, north meters: Double, level: Double = 1,
                        accuracy: Double = 3, open: [JourneyStop]? = nil) -> [String] {
        detector.update(coordinate: Self.point(north: meters), level: level,
                        horizontalAccuracy: accuracy, openStops: open ?? stops)
    }

    func testWalkingPastAStopMarksItPassed() {
        var detector = PassedStops()
        XCTAssertEqual(update(&detector, north: -12), [])
        XCTAssertEqual(update(&detector, north: 3), [])
        XCTAssertEqual(update(&detector, north: 7), [])
        XCTAssertEqual(update(&detector, north: 11), ["a"])
        XCTAssertEqual(update(&detector, north: 14), [])
    }

    func testAStopNeverEnteredIsNotPassed() {
        var detector = PassedStops()
        XCTAssertEqual(update(&detector, north: 6), [])
        XCTAssertEqual(update(&detector, north: 12), [])
    }

    func testImpreciseFixesDoNotEnterAStop() {
        var detector = PassedStops()
        XCTAssertEqual(update(&detector, north: 1, accuracy: 12), [])
        XCTAssertEqual(update(&detector, north: 12), [])
    }

    func testStopsOnAnotherFloorDoNotCount() {
        var detector = PassedStops()
        XCTAssertEqual(update(&detector, north: 30, level: 1), [])
        XCTAssertTrue(detector.near.isEmpty)
    }

    func testAStopThatIsNoLongerOpenIsForgotten() {
        var detector = PassedStops()
        _ = update(&detector, north: 1)
        XCTAssertEqual(detector.near, ["a"])
        XCTAssertEqual(update(&detector, north: 12, open: []), [])
    }

    func testMarkingSetsOnlyThePassedStopsDone() {
        let journey = PassedStops.marking(["a"], doneIn: Journey(stops: stops))
        XCTAssertEqual(journey.stops.map(\.state), [.done, .pending])
    }

    func testVisitRules() {
        XCTAssertEqual(JourneyRules.visit.advance, .onDeparture(meters: 8))
        XCTAssertEqual(RouteFollowRules.visit.arrival, .fromAccuracy(multiplier: 2.5, minimumMeters: 5, maximumMeters: 10))
        XCTAssertEqual(RouteFollowRules.visit.arrivalDwellSeconds, 1)
    }
}
