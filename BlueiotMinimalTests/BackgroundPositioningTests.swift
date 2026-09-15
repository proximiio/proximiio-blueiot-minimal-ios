//
//  BackgroundPositioningTests.swift
//  BlueiotMinimalTests
//
//  Positioning in a pocket needs four things (see `Venue.swift`). These are the two
//  that fail silently: forget either and the dot stops 30 seconds after the screen
//  locks, with nothing on screen to say why. The other two live in `project.yml`,
//  and a build without them is one the SDK warns about in the log.
//
import Proximiio
import XCTest
@testable import BlueiotMinimal

@MainActor
final class BackgroundPositioningTests: XCTestCase {

    /// Asked once: while iOS has never been asked, and never after an answer — a
    /// refusal included, because nagging is how a refusal becomes an uninstall.
    func testLocationIsAskedForOnlyWhileUndetermined() {
        XCTAssertTrue(LocationPrompt.isOwed(.notDetermined))
        XCTAssertFalse(LocationPrompt.isOwed(.authorizedWhenInUse))
        XCTAssertFalse(LocationPrompt.isOwed(.authorizedAlways))
        XCTAssertFalse(LocationPrompt.isOwed(.denied))
        XCTAssertFalse(LocationPrompt.isOwed(.restricted))
    }

    /// The SDK-side half of staying alive off screen. `relayOnly` defaults this to
    /// `false`, and a default is the easiest thing to fall back to unnoticed.
    func testRelayOnlyConfigurationKeepsRunningInTheBackground() {
        XCTAssertTrue(Venue.configuration(token: "t").allowsBackgroundLocationUpdates)
    }
}
