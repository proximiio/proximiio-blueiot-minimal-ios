//
//  BlueiotMinimalApp.swift
//  BlueiotMinimal
//
//  App entry point. Launch order: wristband prompt, location prompt, notification
//  prompt, map. The SDK starts when a wristband session is active and the
//  location prompt is answered.
//
//  This level owns the diagnostics log, the foreground notification delegate,
//  the wristband session and the launch order only. There is no tab bar or settings screen. Add product
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

    /// Pure function, covered by tests. `hasWristband` is `true` while a
    /// wristband session is active.
    static func current(hasWristband: Bool, owesLocationAsk: Bool, owesNotificationAsk: Bool) -> LaunchStep {
        if !hasWristband { return .wristband }
        if owesLocationAsk { return .location }
        if owesNotificationAsk { return .notifications }
        return .map
    }
}

/// Shows the prompts that are owed, then the map. A returning visitor with an
/// active session and every answer given opens the map directly.
struct RootView: View {
    /// The wristband session. Its binding state decides whether the wristband
    /// prompt is shown; the app stores no wristband id of its own.
    @StateObject private var wristband = WristbandSession()
    /// `true` only while location authorization is `.notDetermined`. Read at
    /// launch and again when a session starts, because a bind can ask for
    /// location first. iOS persists the answer, so the prompt is shown at most
    /// once per install.
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
            if wristband.state == nil {
                // The binding state arrives within the first frames. Until then
                // it is unknown whether a stored session exists.
                ProgressView()
            } else {
                switch LaunchStep.current(
                    hasWristband: wristband.isFollowing,
                    owesLocationAsk: owesLocationAsk,
                    owesNotificationAsk: owesNotificationAsk
                ) {
                case .wristband:
                    WristbandPrompt(session: wristband, notice: wristband.endNotice)
                case .location:
                    LocationPrompt { owesLocationAsk = false }
                case .notifications:
                    NotificationPrompt { owesNotificationAsk = false }
                case .map:
                    if let venue {
                        VenueMapScreen(venue: venue, wristband: wristband)
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
        }
        // Follows the binding state and runs `restore()` once. Lives as long as
        // the app's window.
        .task { await wristband.run() }
        .task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            owesNotificationAsk = NotificationPrompt.isOwed(status)
        }
        .onChange(of: wristband.isFollowing) {
            owesLocationAsk = LocationPrompt.isOwed(CLLocationManager().authorizationStatus)
        }
        // The SDK starts once, when a session is active and `LocationPrompt` is
        // answered, so the system location dialog follows that screen. The SDK
        // starts while `NotificationPrompt` is on screen, and the location dialog
        // is shown over it. The SDK keeps running when the session ends.
        .task(id: wristband.isFollowing && !owesLocationAsk) {
            guard wristband.isFollowing, !owesLocationAsk else { return }
            await connect()
        }
    }

    /// Starts the SDK and attaches the binding's position provider, once.
    private func connect() async {
        guard venue == nil else { return }
        do {
            guard let token = VenueConfiguration.token, let binding = wristband.binding else {
                throw VenueConfiguration.SetupIncomplete()
            }
            venue = try await Venue.start(token: token, binding: binding)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}
