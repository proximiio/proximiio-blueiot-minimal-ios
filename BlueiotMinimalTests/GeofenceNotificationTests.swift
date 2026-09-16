//
//  GeofenceNotificationTests.swift
//  BlueiotMinimalTests
//
//  Notification text per direction, the prompt rule, the prompt's place in the
//  launch order, and foreground presentation. Each failure is silent: a wrong
//  direction is not visible on the map, a missing prompt leaves authorization
//  `.notDetermined` and nothing is posted, and a missing delegate hides every
//  notification posted while the app is on screen.
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

    /// Wristband, location, notifications, map. Each prompt is shown only after
    /// the ones before it are answered.
    func testLaunchOrderAsksForNotificationsAfterLocation() {
        XCTAssertEqual(LaunchStep.current(hasWristband: false, owesLocationAsk: true, owesNotificationAsk: true), .wristband)
        XCTAssertEqual(LaunchStep.current(hasWristband: true, owesLocationAsk: true, owesNotificationAsk: true), .location)
        XCTAssertEqual(LaunchStep.current(hasWristband: true, owesLocationAsk: false, owesNotificationAsk: true), .notifications)
        XCTAssertEqual(LaunchStep.current(hasWristband: true, owesLocationAsk: false, owesNotificationAsk: false), .map)
    }

    /// The test host runs `BlueiotMinimalApp.init`, which installs the delegate.
    /// `delegate` is `nil` if the presenter is not retained: the center holds it weakly.
    func testNotificationInTheForegroundIsShownAsABanner() throws {
        let delegate = try XCTUnwrap(UNUserNotificationCenter.current().delegate)
        XCTAssertTrue(delegate is ForegroundNotificationPresenter)
        // `UNNotification` has no public initializer; `NSObject.init()` creates an
        // empty instance. The presenter does not read it.
        let notification = try XCTUnwrap((UNNotification.self as NSObject.Type).init() as? UNNotification)
        var options: UNNotificationPresentationOptions = []
        delegate.userNotificationCenter?(.current(), willPresent: notification, withCompletionHandler: { options = $0 })
        XCTAssertEqual(options, [.banner, .list, .sound])
    }
}
