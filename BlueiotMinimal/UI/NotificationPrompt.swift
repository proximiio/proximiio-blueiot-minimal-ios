//
//  NotificationPrompt.swift
//  BlueiotMinimal
//
//  Notification prompt, the only one not on the launch path. iOS shows its own
//  notification authorization dialog once per install. `Venue` raises this card
//  on the first geofence event that would have produced a notification, and the
//  system dialog follows the button. An event that arrives in the background
//  leaves the card pending until the app is next in the foreground.
//
import SwiftUI
import UserNotifications

struct NotificationPrompt: View {
    let onContinue: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Notifications", systemImage: "bell")
        } description: {
            Text("Allow notifications when iOS asks, and the app tells you as you enter and leave the venue's places — with the phone in your pocket too.")
        } actions: {
            Button("Continue") {
                onContinue()
                Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Same rule as `LocationPrompt.isOwed`: `true` only while the status is `.notDetermined`.
    static func isOwed(_ status: UNAuthorizationStatus) -> Bool {
        status == .notDetermined
    }

    /// The notification title and body and the diagnostics line for one geofence
    /// event. Pure function, covered by tests; keep the text and the log line in step.
    static func note(name: String?, entered: Bool) -> (title: String, body: String, logLine: String) {
        let place = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed area"
        return (place, entered ? "You have arrived." : "You have left.", "geofence \(entered ? "enter" : "exit") · \(place)")
    }
}
