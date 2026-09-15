//
//  LocationPrompt.swift
//  BlueiotMinimal
//
//  The other thing this app asks a person for — once, between the wristband and
//  the map.
//
//  Not for the position: the venue's anchors place the wristband, and the phone's
//  location never enters it. It is asked for because iOS suspends a backgrounded
//  app after 30 seconds unless a location session is running, and CoreLocation
//  runs none unauthorised — so with the question unanswered, the dot stops the
//  moment the phone goes in a pocket. "While Using the App" is enough; nothing here
//  asks for Always. The two flags that go with it are in `Venue.swift`, the
//  background mode and the purpose string in `project.yml`.
//
import CoreLocation
import SwiftUI

struct LocationPrompt: View {
    let onContinue: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Your location", systemImage: "location")
        } description: {
            Text("Allow location when iOS asks, and your position keeps updating with the phone in your pocket — refuse, and the map still works while the app is on screen.")
        } actions: {
            Button("Continue", action: onContinue).buttonStyle(.borderedProminent)
        }
    }

    /// Shown only while iOS has never been asked. A refusal is an answer: the map
    /// works on screen without it, and nobody is asked twice.
    static func isOwed(_ status: CLAuthorizationStatus) -> Bool {
        status == .notDetermined
    }
}
