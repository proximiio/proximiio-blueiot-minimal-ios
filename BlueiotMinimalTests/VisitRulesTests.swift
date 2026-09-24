//
//  VisitRulesTests.swift
//  BlueiotMinimalTests
//
//  The rules in `VisitRules.swift` and `GuidanceLine.offersReroute(for:)`, and
//  the two library behaviours they answer: `proposeOrder(from: .visitor)`
//  returns `nil` without a fix, and `JourneyNavigator.end()` switches the
//  session's single-route guidance off.
//
import XCTest
@testable import BlueiotMinimal
import Proximiio
import ProximiioMap

final class VisitRulesTests: XCTestCase {

    private func stop(
        _ id: String,
        state: JourneyStop.State = .pending,
        kind: JourneyStop.Kind = .planned,
        east: Double = 0
    ) -> JourneyStop {
        JourneyStop(
            id: id,
            title: id.capitalized,
            coordinate: point(east: east),
            floor: FloorKey(level: 0),
            poiID: id,
            kind: kind,
            state: state
        )
    }

    private func proposal(saving meters: Double, liveStopID: String? = nil) -> JourneyOrderProposal {
        JourneyOrderProposal(
            order: meters > 0 ? ["b", "a"] : ["a", "b"],
            currentOrder: ["a", "b"],
            pinnedStopIDs: [],
            currentMeters: 200,
            proposedMeters: 200 - meters,
            liveStopID: liveStopID
        )
    }

    // MARK: - StartOrder

    /// A new visit, and a visit walking to its first stop, are still ordered.
    func testStartOrderIsOwedBeforeAnyStopIsReached() {
        XCTAssertTrue(StartOrder.isOwed(Journey(stops: [stop("a"), stop("b")])))
        XCTAssertTrue(StartOrder.isOwed(Journey(stops: [stop("a", state: .active), stop("b")])))
    }

    /// A reached, done or skipped stop, a stop-off or a single stop ends it.
    func testStartOrderIsNotOwedOnceTheVisitMoved() {
        XCTAssertFalse(StartOrder.isOwed(Journey(stops: [stop("a", state: .reached), stop("b")])))
        XCTAssertFalse(StartOrder.isOwed(Journey(stops: [stop("a", state: .done), stop("b")])))
        XCTAssertFalse(StartOrder.isOwed(Journey(stops: [stop("a", state: .skipped), stop("b")])))
        XCTAssertFalse(StartOrder.isOwed(Journey(stops: [
            stop("wc", state: .active, kind: .detour), stop("a"), stop("b"),
        ])))
        XCTAssertFalse(StartOrder.isOwed(Journey(stops: [stop("a")])))
    }

    /// The bar says what happened: shortened, already shortest, or nothing.
    func testStartOrderNote() {
        XCTAssertEqual(
            StartOrder.note(for: proposal(saving: 42.4), applied: true),
            "Stops put in the shortest order: 42 m less to walk."
        )
        XCTAssertEqual(
            StartOrder.note(for: proposal(saving: 0), applied: false),
            "Your stops are already in the shortest order."
        )
        // Under 1 m is not a saving to announce.
        XCTAssertEqual(
            StartOrder.note(for: proposal(saving: 0.3), applied: true),
            "Your stops are already in the shortest order."
        )
        // A shorter order refused as stale: nothing to say yet.
        XCTAssertNil(StartOrder.note(for: proposal(saving: 42), applied: false))
        XCTAssertNil(StartOrder.note(for: nil, applied: false))
    }

    // MARK: - OrderAdvice

    func testOrderAdviceShowsTheSaving() {
        let advice = OrderAdvice.of(proposal(saving: 57.6), movableStops: 2, isMeasuring: false, canApply: true)
        XCTAssertEqual(advice, .save(meters: 58))
        XCTAssertEqual(advice.text, "Save 58 m by reordering")
    }

    /// The row is shown when no order is shorter, so the visitor sees the
    /// order was measured.
    func testOrderAdviceSaysWhenTheOrderIsAlreadyShortest() {
        XCTAssertEqual(
            OrderAdvice.of(proposal(saving: 0), movableStops: 2, isMeasuring: false, canApply: true),
            .alreadyShortest
        )
        XCTAssertEqual(
            OrderAdvice.of(proposal(saving: 0.4), movableStops: 2, isMeasuring: false, canApply: true),
            .alreadyShortest
        )
    }

    func testOrderAdviceWhileMeasuringStaleOrUnmeasurable() {
        XCTAssertEqual(OrderAdvice.of(nil, movableStops: 3, isMeasuring: true, canApply: false), .measuring)
        XCTAssertEqual(
            OrderAdvice.of(proposal(saving: 50), movableStops: 2, isMeasuring: false, canApply: false),
            .measuring
        )
        XCTAssertEqual(OrderAdvice.of(nil, movableStops: 3, isMeasuring: false, canApply: false), .unmeasurable)
        XCTAssertEqual(OrderAdvice.of(nil, movableStops: 1, isMeasuring: false, canApply: false), OrderAdvice.none)
        XCTAssertNil(OrderAdvice.none.text)
    }

    // MARK: - StopOff

    func testStopOffText() {
        XCTAssertEqual(
            StopOff.menuHeader(goingTo: "Gallery"),
            "Go to the nearest one before Gallery. Your plan continues afterwards."
        )
        XCTAssertEqual(StopOff.title(stop("toilets", kind: .detour)), "Stop off: Toilets")
        XCTAssertEqual(
            StopOff.status(hasArrived: false, next: "Gallery"),
            "On the way, then on to Gallery. Back to the plan cancels the stop-off."
        )
        XCTAssertEqual(
            StopOff.status(hasArrived: true, next: "Gallery"),
            "Tap Continue when you are done, then on to Gallery."
        )
        XCTAssertEqual(
            StopOff.status(hasArrived: true, next: nil),
            "Tap Continue when you are done, then the visit ends."
        )
    }

    // MARK: - Single-route re-route

    private func guidance(offRoute: Bool, arrived: Bool) -> RouteGuidance {
        RouteGuidance(
            projection: RouteProjection(
                segmentIndex: 0,
                t: 0,
                coordinate: point(east: 0),
                floor: FloorKey(level: 0),
                offRouteMeters: offRoute ? 20 : 0,
                traveledMeters: 0
            ),
            manoeuvre: nil,
            manoeuvreIndex: nil,
            nextManoeuvre: nil,
            distanceToManoeuvreMeters: 10,
            remainingMeters: 10,
            traveledMeters: 0,
            offRouteMeters: offRoute ? 20 : 0,
            isOffRoute: offRoute,
            hasArrived: arrived,
            arrivalProgress: arrived ? 1 : 0,
            progress: RouteGeometry.Progress(completedThrough: 0)
        )
    }

    func testRerouteIsOfferedOnlyOffTheRoute() {
        XCTAssertTrue(GuidanceLine.offersReroute(for: guidance(offRoute: true, arrived: false)))
        XCTAssertFalse(GuidanceLine.offersReroute(for: guidance(offRoute: false, arrived: false)))
        XCTAssertFalse(GuidanceLine.offersReroute(for: guidance(offRoute: true, arrived: true)))
        XCTAssertFalse(GuidanceLine.offersReroute(for: nil))
        XCTAssertEqual(GuidanceLine.sentence(for: guidance(offRoute: true, arrived: false)), "You have left the route.")
    }

    // MARK: - The library behaviours behind the fixes

    private let anchor = MapCoordinate(latitude: 48.1486, longitude: 17.1077)

    /// `east` metres east of the anchor, on the corridor.
    private func point(east: Double) -> MapCoordinate {
        MapCoordinate(
            latitude: anchor.latitude,
            longitude: anchor.longitude + east / (111_320.0 * cos(anchor.latitude * .pi / 180))
        )
    }

    /// A facade with no network and no CoreLocation over a throwaway database,
    /// with one 200 m corridor as its route network.
    @MainActor
    private func makeSession() async throws -> ProximiioMapSession {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("visit-rules-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: database) }
        let sdk = try Proximiio(configuration: ProximiioConfiguration(
            token: "test-token",
            databasePath: database.path,
            nativeLocationEnabled: false
        ))
        await sdk.setRouteNetwork([
            RouteFeature(
                id: "corridor",
                coordinates: (0 ... 20).map {
                    let value = point(east: Double($0) * 10)
                    return ProximiioCoordinate(latitude: value.latitude, longitude: value.longitude)
                },
                level: 0
            ),
        ])
        return ProximiioMapSession(sdk: sdk)
    }

    /// Ending a visit: `end()` sets `guidanceRules` to `nil`. A second `end()`
    /// after the map screen restored the rules left single-route guidance off,
    /// with no instruction line and no off-route warning. `JourneyBar` ends
    /// the navigator once, before `onEnd` restores the rules.
    @MainActor
    func testEndingAVisitSwitchesGuidanceOffUntilTheRulesAreSetAgain() async throws {
        let session = try await makeSession()
        session.guidanceRules = .venueWalk
        let navigator = JourneyNavigator(
            session: session,
            journey: Journey(stops: [stop("a", east: 50), stop("b", east: 150)])
        )
        await navigator.start()

        navigator.end()
        XCTAssertNil(session.guidanceRules)

        session.guidanceRules = .venueWalk // `VenueMapScreen.endVisit()`
        XCTAssertEqual(session.guidanceRules, .venueWalk)
    }

    /// Without a fix, `.visitor` has no answer; the tap order stays and
    /// `JourneyBar` orders the visit on the first fix. `.activeStop` measures
    /// a badly tapped order without a fix, holding the first stop.
    @MainActor
    func testVisitorOrderNeedsAFix() async throws {
        let session = try await makeSession()
        let navigator = JourneyNavigator(
            session: session,
            journey: Journey(stops: [stop("a", east: 20), stop("c", east: 180), stop("b", east: 100)])
        )

        let fromVisitor = await navigator.proposeOrder(from: .visitor)
        XCTAssertNil(fromVisitor)

        let measured = await navigator.proposeOrder(from: .activeStop)
        let fromFirstStop = try XCTUnwrap(measured)
        XCTAssertEqual(fromFirstStop.order, ["a", "b", "c"])
        XCTAssertTrue(fromFirstStop.isImprovement)
        XCTAssertEqual(
            OrderAdvice.of(fromFirstStop, movableStops: 3, isMeasuring: false, canApply: navigator.canApply(fromFirstStop)),
            .save(meters: Int(fromFirstStop.savedMeters.rounded()))
        )
    }
}
