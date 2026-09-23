//
//  DeviationPromptTests.swift
//  BlueiotMinimalTests
//
//  `DeviationPrompt.after(_:showing:)`: which journey events open the deviation
//  prompt, which close it and which leave it. A wrong rule leaves a visitor off
//  the route without a prompt, or keeps a prompt on screen after the visitor has
//  returned.
//
import XCTest
@testable import BlueiotMinimal
import ProximiioMap

final class DeviationPromptTests: XCTestCase {

    private let cafe = JourneyStop(
        id: "cafe",
        title: "Café",
        coordinate: MapCoordinate(latitude: 0, longitude: 0),
        floor: FloorKey(level: 0),
        poiID: "cafe",
        kind: .detour,
        state: .active
    )

    private var farPrompt: DeviationPrompt? {
        DeviationPrompt.after(.farFromRoute(distance: 31.6), showing: nil)
    }

    /// The three events that open the prompt, each with its own sentence.
    func testDeviationEventsOpenThePrompt() throws {
        XCTAssertEqual(farPrompt, DeviationPrompt(
            reason: .farFromRoute,
            message: "You are 32 m from your route."
        ))
        XCTAssertEqual(DeviationPrompt.after(.offRouteTooLong(duration: 300), showing: nil), DeviationPrompt(
            reason: .offRouteTooLong,
            message: "You have been off your route for 5 min."
        ))
        XCTAssertEqual(DeviationPrompt.after(.detourOverstayed(stop: cafe, duration: 1020), showing: nil), DeviationPrompt(
            reason: .detourOverstayed,
            message: "You left your route for Café 17 min ago."
        ))
    }

    /// A duration under half a minute is shown as 1 min, not 0.
    func testMinutesAreAtLeastOne() {
        XCTAssertEqual(
            DeviationPrompt.after(.offRouteTooLong(duration: 10), showing: nil)?.message,
            "You have been off your route for 1 min."
        )
    }

    /// `leftRoute` opens no prompt, and leaves an open one unchanged.
    func testLeftRouteOpensNothing() {
        XCTAssertNil(DeviationPrompt.after(.leftRoute(distance: 14), showing: nil))
        XCTAssertEqual(DeviationPrompt.after(.leftRoute(distance: 14), showing: farPrompt), farPrompt)
    }

    /// A newer deviation event replaces the prompt on screen.
    func testNewerDeviationReplacesThePrompt() {
        XCTAssertEqual(
            DeviationPrompt.after(.offRouteTooLong(duration: 300), showing: farPrompt)?.reason,
            .offRouteTooLong
        )
    }

    /// Returning to the route and finishing the visit close any prompt.
    func testReturnAndFinishClose() {
        XCTAssertNil(DeviationPrompt.after(.returnedToRoute, showing: farPrompt))
        XCTAssertNil(DeviationPrompt.after(.journeyFinished, showing: farPrompt))
    }

    /// The end of a detour closes a detour prompt only.
    func testDetourEndClosesOnlyADetourPrompt() {
        let detourPrompt = DeviationPrompt.after(.detourOverstayed(stop: cafe, duration: 1020), showing: nil)
        XCTAssertNil(DeviationPrompt.after(.detourEnded(cafe, completed: false), showing: detourPrompt))
        XCTAssertEqual(DeviationPrompt.after(.detourEnded(cafe, completed: false), showing: farPrompt), farPrompt)
    }

    /// Transitions that are not deviations leave the prompt as it is.
    func testOtherEventsKeepThePrompt() {
        XCTAssertEqual(DeviationPrompt.after(.rerouted(to: cafe), showing: farPrompt), farPrompt)
        XCTAssertEqual(DeviationPrompt.after(.stopReached(cafe), showing: farPrompt), farPrompt)
        XCTAssertNil(DeviationPrompt.after(.detourStarted(cafe), showing: nil))
    }
}
