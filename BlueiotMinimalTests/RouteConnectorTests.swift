//
//  RouteConnectorTests.swift
//  BlueiotMinimalTests
//
//  `RouteConnector.points(guidance:position:shownFloor:)`: when the line from
//  the position to the route ahead is drawn. The layer itself is not tested.
//
import XCTest
@testable import BlueiotMinimal
import ProximiioMap

final class RouteConnectorTests: XCTestCase {

    private let here = MapCoordinate(latitude: 48.1, longitude: 17.1)
    private let start = MapCoordinate(latitude: 48.10003, longitude: 17.1)

    private func guidance(start: MapCoordinate?, hasArrived: Bool = false) -> RouteGuidance {
        RouteGuidance(
            projection: RouteProjection(
                segmentIndex: 0, t: 0, coordinate: self.start, floor: FloorKey(level: 1),
                offRouteMeters: 3, traveledMeters: 0
            ),
            manoeuvre: nil, manoeuvreIndex: nil, nextManoeuvre: nil,
            distanceToManoeuvreMeters: 0, remainingMeters: 20, traveledMeters: 0,
            offRouteMeters: 3, isOffRoute: false, hasArrived: hasArrived, arrivalProgress: 0,
            progress: RouteGeometry.Progress(completedThrough: 0, point: start)
        )
    }

    private func position(level: Double?) -> VenuePosition {
        VenuePosition(coordinate: here, horizontalAccuracy: 2, floor: FloorKey(level), timestamp: Date())
    }

    func testJoinsThePositionToTheSplitPoint() {
        let points = RouteConnector.points(
            guidance: guidance(start: start), position: position(level: 1), shownFloor: FloorKey(level: 1)
        )
        XCTAssertEqual(points, [here, start])
    }

    func testNoLineOnAnotherFloor() {
        XCTAssertEqual(RouteConnector.points(
            guidance: guidance(start: start), position: position(level: 1), shownFloor: FloorKey(level: 2)
        ), [])
    }

    func testNoLineAfterArrival() {
        XCTAssertEqual(RouteConnector.points(
            guidance: guidance(start: start, hasArrived: true), position: position(level: 1), shownFloor: FloorKey(level: 1)
        ), [])
    }

    func testNoLineWithoutGuidanceOrSplitPoint() {
        XCTAssertEqual(RouteConnector.points(guidance: nil, position: position(level: 1), shownFloor: FloorKey(level: 1)), [])
        XCTAssertEqual(RouteConnector.points(
            guidance: guidance(start: nil), position: position(level: 1), shownFloor: FloorKey(level: 1)
        ), [])
    }

    func testPositionWithoutFloorCountsAsOnTheShownFloor() {
        XCTAssertEqual(RouteConnector.points(
            guidance: guidance(start: start), position: position(level: nil), shownFloor: FloorKey(level: 2)
        ), [here, start])
    }
}
