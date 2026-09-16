//
//  NotificationPrompt.swift
//  BlueiotMinimal
//
//  The third thing this app asks a person for, and the only one not asked on the
//  way in. iOS grants one notification prompt per install, so it is not spent on a
//  launch path: this card goes up on the first geofence note `Venue` would have
//  shown — when "what are these for" answers itself — and iOS's own prompt follows
//  the button. A note in a pocket leaves the card waiting for the next time on screen.
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

    /// `LocationPrompt`'s rule, for the other permission: a refusal is an answer.
    static func isOwed(_ status: UNAuthorizationStatus) -> Bool {
        status == .notDetermined
    }

    /// The words on one note and its diagnostics line. Pure, so tested; change both.
    static func note(name: String?, entered: Bool) -> (title: String, body: String, logLine: String) {
        let place = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed area"
        return (place, entered ? "You have arrived." : "You have left.", "geofence \(entered ? "enter" : "exit") · \(place)")
    }
}
