//
//  BackgroundPositioningTests.swift
//  BlueiotMinimalTests
//
//  Two of the four background positioning settings (see `Venue.swift`). Both fail
//  silently: with either missing, positioning stops 30 seconds after the screen
//  locks and nothing on screen reports it. The other two are in `project.yml`;
//  the SDK logs a warning when they are missing.
//
import Proximiio
import XCTest
@testable import BlueiotMinimal

@MainActor
final class BackgroundPositioningTests: XCTestCase {

    /// Location is asked for only while the status is `.notDetermined`, never
    /// after an answer, including a denial.
    func testLocationIsAskedForOnlyWhileUndetermined() {
        XCTAssertTrue(LocationPrompt.isOwed(.notDetermined))
        XCTAssertFalse(LocationPrompt.isOwed(.authorizedWhenInUse))
        XCTAssertFalse(LocationPrompt.isOwed(.authorizedAlways))
        XCTAssertFalse(LocationPrompt.isOwed(.denied))
        XCTAssertFalse(LocationPrompt.isOwed(.restricted))
    }

    /// The SDK-side background setting. `relayOnly` defaults `runsInBackground`
    /// to `false`.
    func testRelayOnlyConfigurationKeepsRunningInTheBackground() {
        XCTAssertTrue(Venue.configuration(token: "t").allowsBackgroundLocationUpdates)
    }
}
