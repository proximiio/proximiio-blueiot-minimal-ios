//
//  BlueiotMinimalApp.swift
//  BlueiotMinimal
//
//  App entry point. Launch order: wristband prompt, location prompt, notification
//  prompt, map. The SDK starts when the location prompt is answered.
//
//  This level owns the diagnostics log, the foreground notification delegate and
//  the launch order only. There is no tab bar or settings screen. Add product
//  screens where `VenueMapScreen` is built.
//
import CoreLocation
import Proximiio
import SwiftUI
import UserNotifications

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
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            Proximiio.recordDiagnosticsEvent(.state, "notifications: \(NotificationPrompt.name(of: status))")
        }
        // Installed before `Venue` exists, so the first geofence notification
        // posted in the foreground is shown.
        ForegroundNotificationPresenter.install()
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

/// The launch screens in the order `RootView` shows them. A prompt is shown
/// while its answer is owed; `.map` follows the last one.
enum LaunchStep: Equatable {
    case wristband, location, notifications, map

    /// Pure function, covered by tests.
    static func current(hasWristband: Bool, owesLocationAsk: Bool, owesNotificationAsk: Bool) -> LaunchStep {
        if !hasWristband { return .wristband }
        if owesLocationAsk { return .location }
        if owesNotificationAsk { return .notifications }
        return .map
    }
}

/// Shows the prompts that are owed, then the map. A returning visitor with every
/// answer given opens the map directly.
struct RootView: View {
    /// Loaded once from `WristbandStore`. A stored id skips the prompt.
    @State private var wristband = WristbandStore.load()
    /// Read once. `true` only while location authorization is `.notDetermined`;
    /// iOS persists the answer, so the prompt is shown at most once per install.
    @State private var owesLocationAsk = LocationPrompt.isOwed(CLLocationManager().authorizationStatus)
    /// `true` only while notification authorization is `.notDetermined`. Read
    /// once, by the first `.task` below: `notificationSettings()` has no
    /// synchronous form. `false` until the read returns; the `.map` step shows
    /// `ProgressView` then, because `Venue.start` waits on network requests.
    @State private var owesNotificationAsk = false
    @State private var venue: Venue?
    @State private var failure: String?

    var body: some View {
        Group {
            switch LaunchStep.current(
                hasWristband: wristband != nil,
                owesLocationAsk: owesLocationAsk,
                owesNotificationAsk: owesNotificationAsk
            ) {
            case .wristband:
                WristbandPrompt(onSave: save)
            case .location:
                LocationPrompt { owesLocationAsk = false }
            case .notifications:
                NotificationPrompt { owesNotificationAsk = false }
            case .map:
                if let venue {
                    VenueMapScreen(venue: venue, wristband: wristband?.canonical ?? "", onSaveWristband: save)
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
        }
        .task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            owesNotificationAsk = NotificationPrompt.isOwed(status)
        }
        // Keyed on the wristband: saving a different id re-runs `connect()`, which
        // re-points positioning at the new id without restarting the SDK or
        // rebuilding the map. The key is `nil` while `LocationPrompt` is on
        // screen, so the SDK and the system location dialog start only after
        // that screen is answered. The SDK starts while `NotificationPrompt` is
        // on screen, and the location dialog is shown over it.
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
