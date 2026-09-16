//
//  BlueiotMinimalApp.swift
//  BlueiotMinimal
//
//  App entry point. Launch order: wristband prompt, location prompt, SDK start,
//  map. The notification prompt is raised later, on the first geofence event.
//
//  This level owns the diagnostics log and the launch order only. There is no
//  tab bar, onboarding flow or settings screen. Add product screens where
//  `VenueMapScreen` is built.
//
import CoreLocation
import Proximiio
import SwiftUI

@main
struct BlueiotMinimalApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Starts the SDK diagnostics log (README, "The diagnostics log"). This is
        // the first statement in the app: lines emitted before the call returns
        // are dropped. The call is async and `init` is not, so it runs in a
        // `Task`. `capturesSDKLog: true` includes the SDK's own log lines (fixes,
        // floors, relay state, warnings). If the log cannot be written, the app
        // runs without one.
        Task {
            try? await Proximiio.startDiagnosticsRecording(
                .init(capturesSDKLog: true, additionalSecrets: VenueConfiguration.secrets)
            )
        }
    }

    var body: some Scene {
        WindowGroup { RootView() }
            // Records scene transitions in the diagnostics log; the SDK does not observe them itself.
            .onChange(of: scenePhase) { _, phase in
                guard phase != .inactive else { return }
                Proximiio.recordDiagnosticsEvent(.state, "scene: \(phase == .background ? "background" : "foreground")")
            }
    }
}

/// Shows the wristband prompt and then the location prompt on the first run.
/// Later runs open the map directly.
struct RootView: View {
    /// Loaded once from `WristbandStore`. A stored id skips the prompt.
    @State private var wristband = WristbandStore.load()
    /// Read once. `true` only while location authorization is `.notDetermined`;
    /// iOS persists the answer, so the prompt is shown at most once per install.
    @State private var owesLocationAsk = LocationPrompt.isOwed(CLLocationManager().authorizationStatus)
    @State private var venue: Venue?
    @State private var failure: String?

    var body: some View {
        Group {
            if wristband == nil {
                WristbandPrompt(onSave: save)
            } else if owesLocationAsk {
                LocationPrompt { owesLocationAsk = false }
            } else if let venue {
                VenueMapScreen(venue: venue, wristband: wristband?.canonical ?? "", onSaveWristband: save)
                    // `Venue` sets `owesNotificationAsk` on the first geofence event; the prompt is not on the launch path.
                    .sheet(isPresented: Bindable(venue).owesNotificationAsk) {
                        NotificationPrompt { venue.owesNotificationAsk = false }
                            .interactiveDismissDisabled()
                    }
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
        // Keyed on the wristband: saving a different id re-runs `connect()`, which
        // re-points positioning at the new id without restarting the SDK or
        // rebuilding the map. The key is `nil` while `LocationPrompt` is on
        // screen, so the SDK and the system location dialog start only after
        // that screen is answered.
        .task(id: owesLocationAsk ? nil : wristband) { await connect() }
    }

    private func save(_ id: WristbandID) {
        WristbandStore.save(id)
        wristband = id
    }

    private func connect() async {
        guard let wristband else { return }
        do {
            if let venue {
                // SDK already running: only the wristband changed.
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
