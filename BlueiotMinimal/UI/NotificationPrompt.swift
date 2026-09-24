//
//  NotificationPrompt.swift
//  BlueiotMinimal
//
//  Notification prompt, shown once between the location prompt and the map, and
//  the delegate that shows notifications while the app is in the foreground.
//  iOS shows its notification authorization dialog once per install; the dialog
//  follows the button.
//
import SwiftUI
import UserNotifications

struct NotificationPrompt: View {
    let onContinue: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Notifications", systemImage: "bell")
        } description: {
            Text("Allow notifications when iOS asks, and the app tells you as you enter and leave the venue's places, with the phone in your pocket too — refuse, and the map still works.")
        } actions: {
            Button("Continue") {
                onContinue()
                Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Same rule as `LocationPrompt.isOwed`: `true` only while the status is
    /// `.notDetermined`. A denial is not asked about again.
    static func isOwed(_ status: UNAuthorizationStatus) -> Bool {
        status == .notDetermined
    }

    /// The Swift case name of `status`, for the diagnostics log.
    static func name(of status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown \(status.rawValue)"
        }
    }

    /// The notification title and body and the diagnostics line for one geofence
    /// event. Pure function, covered by tests; keep the text and the log line in step.
    static func note(name: String?, entered: Bool) -> (title: String, body: String, logLine: String) {
        let place = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed area"
        return (place, entered ? "You have arrived." : "You have left.", "geofence \(entered ? "enter" : "exit") · \(place)")
    }
}

/// Returns `[.banner, .list, .sound]` for a notification that arrives while the
/// app is in the foreground. Without a delegate, iOS shows no banner for it.
///
/// Not `@MainActor` and not part of `Venue`: `UNUserNotificationCenterDelegate`
/// is a nonisolated protocol, and the delegate is installed before `Venue`
/// exists. The center holds its delegate weakly; `shared` is the strong
/// reference for the process lifetime.
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private static let shared = ForegroundNotificationPresenter()

    /// Called from `BlueiotMinimalApp.init`, before any notification is posted.
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // `.list` keeps the notification in Notification Center after the banner.
        completionHandler([.banner, .list, .sound])
    }
}
