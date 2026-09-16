//
//  LocationPrompt.swift
//  BlueiotMinimal
//
//  Location prompt, shown once between the wristband prompt and the map.
//
//  The phone's location is not used for positioning; the venue's anchors position
//  the wristband. Location authorization is required because iOS suspends a
//  backgrounded app after 30 seconds unless a location session is running, and
//  CoreLocation runs none without authorization. Without it, positioning stops
//  when the app leaves the screen. "While Using the App" is sufficient; the app
//  does not request Always. The related settings are `runsInBackground` in
//  `Venue.swift` and the background mode and purpose string in `project.yml`.
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

    /// `true` only while the status is `.notDetermined`. A denial is not asked
    /// about again; the map works in the foreground without location.
    static func isOwed(_ status: CLAuthorizationStatus) -> Bool {
        status == .notDetermined
    }
}
