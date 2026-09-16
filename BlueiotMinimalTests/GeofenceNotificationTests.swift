//
//  GeofenceNotificationTests.swift
//  BlueiotMinimalTests
//
//  A note that says "arrived" on the way out is wrong in a way nothing on the map
//  shows, and a notification ask that fires on launch spends the one prompt iOS
//  gives on a screen nobody was standing in.
//
import UserNotifications
import XCTest
@testable import BlueiotMinimal

final class GeofenceNotificationTests: XCTestCase {

    func testNoteNamesThePlaceAndTheDirection() {
        let entered = NotificationPrompt.note(name: "Lobby", entered: true)
        XCTAssertEqual(entered.title, "Lobby")
        XCTAssertEqual(entered.body, "You have arrived.")
        XCTAssertEqual(entered.logLine, "geofence enter · Lobby")

        let left = NotificationPrompt.note(name: "Lobby", entered: false)
        XCTAssertEqual(left.title, "Lobby")
        XCTAssertEqual(left.body, "You have left.")
        XCTAssertEqual(left.logLine, "geofence exit · Lobby")
    }

    /// A geofence left unnamed in the Portal still produces a note that reads.
    func testUnnamedGeofenceStillReads() {
        XCTAssertEqual(NotificationPrompt.note(name: "", entered: true).title, "Unnamed area")
        XCTAssertEqual(NotificationPrompt.note(name: nil, entered: false).logLine, "geofence exit · Unnamed area")
    }

    /// Asked once, on the first note, and never after an answer — location's rule,
    /// for the other permission.
    func testNotificationsAreAskedForOnlyWhileUndetermined() {
        XCTAssertTrue(NotificationPrompt.isOwed(.notDetermined))
        XCTAssertFalse(NotificationPrompt.isOwed(.authorized))
        XCTAssertFalse(NotificationPrompt.isOwed(.denied))
        XCTAssertFalse(NotificationPrompt.isOwed(.provisional))
    }
}
