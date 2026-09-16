//
//  GeofenceNotificationTests.swift
//  BlueiotMinimalTests
//
//  Notification text per direction, and the prompt rule. A wrong direction is not
//  visible on the map. iOS shows the notification dialog once per install; a
//  prompt on launch would spend it before any geofence event.
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

    /// A geofence without a name in Proximi.io Portal still produces a readable note.
    func testUnnamedGeofenceStillReads() {
        XCTAssertEqual(NotificationPrompt.note(name: "", entered: true).title, "Unnamed area")
        XCTAssertEqual(NotificationPrompt.note(name: nil, entered: false).logLine, "geofence exit · Unnamed area")
    }

    /// Notifications are asked for only while the status is `.notDetermined`;
    /// the same rule as location.
    func testNotificationsAreAskedForOnlyWhileUndetermined() {
        XCTAssertTrue(NotificationPrompt.isOwed(.notDetermined))
        XCTAssertFalse(NotificationPrompt.isOwed(.authorized))
        XCTAssertFalse(NotificationPrompt.isOwed(.denied))
        XCTAssertFalse(NotificationPrompt.isOwed(.provisional))
    }
}
