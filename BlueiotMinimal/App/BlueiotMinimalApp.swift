//
//  BlueiotMinimalApp.swift
//  BlueiotMinimal
//
//  THE WHOLE APP, IN ORDER: ask for the wristband, start the SDK, show the map.
//
//  Nothing else happens at this level. There is no tab bar, no onboarding flow and
//  no settings — a visitor is handed a band, types the number on it once, and is on
//  the map. Your product's screens go where `VenueMapScreen` is built.
//
import SwiftUI

@main
struct BlueiotMinimalApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

/// First run asks for the wristband; every run after that goes straight to the map.
struct RootView: View {
    /// Read from the store on the first body evaluation, so a returning visitor
    /// never sees the prompt.
    @State private var wristband = WristbandStore.load()
    @State private var venue: Venue?
    @State private var failure: String?
    @State private var isChangingWristband = false

    var body: some View {
        Group {
            if wristband == nil {
                WristbandPrompt(onSave: save)
            } else if let venue {
                VenueMapScreen(venue: venue) { isChangingWristband = true }
            } else if let failure {
                ContentUnavailableView(
                    "Cannot reach the venue",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure)
                )
            } else {
                ProgressView()
            }
        }
        // Keyed on the wristband: saving a different one re-runs this, and
        // `connect()` re-points positioning at the new band without restarting
        // the SDK or rebuilding the map.
        .task(id: wristband) { await connect() }
        .sheet(isPresented: $isChangingWristband) {
            WristbandPrompt(
                current: wristband?.canonical ?? "",
                onCancel: { isChangingWristband = false },
                onSave: { id in
                    isChangingWristband = false
                    save(id)
                }
            )
        }
    }

    private func save(_ id: WristbandID) {
        WristbandStore.save(id)
        wristband = id
    }

    private func connect() async {
        guard let wristband else { return }
        do {
            if let venue {
                // Already running: only the band changed.
                await venue.follow(wristband)
                return
            }
            guard let token = VenueConfiguration.token else {
                throw VenueConfiguration.SetupIncomplete()
            }
            let venue = try await Venue.start(token: token)
            await venue.follow(wristband)
            self.venue = venue
        } catch {
            failure = error.localizedDescription
        }
    }
}
