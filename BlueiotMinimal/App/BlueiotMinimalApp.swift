//
//  BlueiotMinimalApp.swift
//  BlueiotMinimal
//
//  THE WHOLE APP, IN ORDER: ask for the wristband, ask for location, start the
//  SDK, show the map.
//
//  Apart from the diagnostics log, nothing else happens at this level. There is no tab bar, no onboarding flow and
//  no settings — a visitor is handed a band, types the number on it once, answers
//  one location prompt, and is on the map. Your product's screens go where
//  `VenueMapScreen` is built.
//
import CoreLocation
import Proximiio
import SwiftUI

@main
struct BlueiotMinimalApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The SDK's diagnostics log — the one thing support can ask a visitor for
        // (README, "The diagnostics log"). First statement in the app, in a `Task`
        // because the call is async and `init` is not: until it returns, lines are
        // dropped. If there is nowhere to write, the app runs on without a log;
        // there is nothing a visitor could do about it.
        Task {
            try? await Proximiio.startDiagnosticsRecording(
                .init(capturesSDKLog: true, additionalSecrets: VenueConfiguration.secrets)
            )
        }
    }

    var body: some Scene {
        WindowGroup { RootView() }
            // The one thing the SDK cannot see from inside: when the app left the screen.
            .onChange(of: scenePhase) { _, phase in
                guard phase != .inactive else { return }
                Proximiio.recordDiagnosticsEvent(.state, "scene: \(phase == .background ? "background" : "foreground")")
            }
    }
}

/// First run asks for the wristband, then for location; every run after that goes
/// straight to the map.
struct RootView: View {
    /// Read from the store on the first body evaluation, so a returning visitor
    /// never sees the prompt.
    @State private var wristband = WristbandStore.load()
    /// Likewise read once: iOS remembers the answer, so this is `true` exactly
    /// until the first time `LocationPrompt` is answered.
    @State private var owesLocationAsk = LocationPrompt.isOwed(CLLocationManager().authorizationStatus)
    @State private var venue: Venue?
    @State private var failure: String?
    @State private var isChangingWristband = false

    var body: some View {
        Group {
            if wristband == nil {
                WristbandPrompt(onSave: save)
            } else if owesLocationAsk {
                LocationPrompt { owesLocationAsk = false }
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
        // the SDK or rebuilding the map. Held at `nil` while the location ask is
        // on screen, so the SDK — and the system prompt it raises — starts only
        // once that screen has been answered.
        .task(id: owesLocationAsk ? nil : wristband) { await connect() }
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
