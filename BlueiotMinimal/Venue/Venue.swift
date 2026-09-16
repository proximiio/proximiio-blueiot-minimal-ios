//
//  Venue.swift
//  BlueiotMinimal
//
//  Positioning: SDK start, cloud relay attachment for one wristband, and a local
//  notification per geofence event.
//
//  The venue's BlueIoT anchors locate the wristband and report to a Proximi.io
//  cloud relay; the phone scans nothing.
//  `ProximiioConfiguration.relayOnly(token:runsInBackground:)` is the preset for
//  this integration: it disables the SDK's iBeacon, Eddystone and UWB sources.
//  The rest is two calls, start the SDK and attach the relay, and one
//  notification per geofence event.
//
//  Background positioning requires four settings. Each one missing has the same
//  symptom: positioning stops 30 seconds after the screen locks, as if the relay
//  had disconnected. `runsInBackground: true` on the SDK configuration and on
//  the relay provider configuration (both in this file); the `location`
//  background mode and its purpose string (`project.yml`); and location
//  authorization (`LocationPrompt`).
//
import Foundation
import Proximiio
import UserNotifications

@MainActor
final class Venue {

    /// The started SDK. `VenueMapScreen` passes it to the map, which reads the
    /// venue, the floors and the live position from it.
    let sdk: Proximiio

    /// The name of the attached provider, kept so a later `follow(_:)` can detach
    /// it. Detaching is by name.
    private var attachedProvider: String?

    private init(sdk: Proximiio) {
        self.sdk = sdk
        announceGeofences()
    }

    /// The SDK configuration. Separate from `start` so a test can read the
    /// background setting from it. `runsInBackground` defaults to `false`.
    static func configuration(token: String) -> ProximiioConfiguration {
        .relayOnly(token: token, runsInBackground: true)
    }

    /// Requests location authorization, authenticates, starts positioning and
    /// downloads the venue.
    ///
    /// The four calls run in this order and none is optional:
    ///  1. `requestPermissions()` shows the system location dialog behind
    ///     `LocationPrompt`. iOS asks once; an answered request returns
    ///     immediately with the stored answer.
    ///  2. `authenticate()` validates the token and runs the first sync, which
    ///     loads the floors the SDK resolves relay fixes against.
    ///  3. `start()` starts positioning. Under `relayOnly` that is the engine and
    ///     the keep-alive location session; fixes arrive once a provider is
    ///     attached.
    ///  4. `loadRouteNetwork()` downloads the venue GeoJSON: the POIs this app
    ///     searches and the path network `computeRoute` uses, cached locally. It
    ///     is the only network call wayfinding needs.
    static func start(token: String) async throws -> Venue {
        let sdk = try Proximiio(configuration: configuration(token: token))
        _ = await sdk.requestPermissions()
        _ = try await sdk.authenticate()
        try await sdk.start()
        _ = try await sdk.loadRouteNetwork()
        return Venue(sdk: sdk)
    }

    /// Points positioning at one wristband.
    ///
    /// Can be called again with a different id: the previous provider is
    /// detached first, so a change is a re-attach, not an SDK restart.
    ///
    /// Floor resolution is done by the SDK. It resolves engine floor numbers
    /// against the floor levels it synced, shifting numbers at and above ground
    /// by `engineGroundFloorNumber`, and logs a fix whose number matches no
    /// floor. Do not pass `floorNoMap`: a supplied table switches that
    /// derivation off.
    func follow(_ wristband: WristbandID) async {
        if let attachedProvider {
            await sdk.detachPositionProvider(named: attachedProvider)
            self.attachedProvider = nil
        }
        guard let host = VenueConfiguration.relayHost,
              let endpoint = BlueiotCloudRelayEndpoint(text: host)
        else { return }

        var configuration = BlueiotCloudRelayConfiguration(
            endpoint: endpoint,
            token: VenueConfiguration.relayToken,
            tagID: wristband.canonical,
            // Without this the SDK pauses the provider on backgrounding, regardless
            // of the process's own background permission.
            runsInBackground: true
        )
        // A LocalSense engine numbers floors from 1 with no 0 and basements
        // negative; Proximi.io numbers the ground floor 0. `engineGroundFloorNumber
        // = 1` states that convention; the SDK applies the shift above ground only
        // (engine 1 is level 0, engine 2 is level 1, engine -1 stays level -1).
        configuration.engineGroundFloorNumber = VenueConfiguration.groundFloorNumber

        let provider = BlueiotCloudRelayPositionProvider(configuration: configuration)
        attachedProvider = provider.name
        Proximiio.recordDiagnosticsEvent(.state, "wristband: \(wristband.canonical)")
        await sdk.attachPositionProvider(provider)
    }

    /// Posts one local notification per geofence enter or exit, in the foreground
    /// and in the background. The geofences are defined in Proximi.io Portal and
    /// synced by `authenticate()`. The SDK applies its enter/exit tolerance; the
    /// app adds no filtering. Privacy zones are not announced. Nothing is posted
    /// unless notification authorization is `.authorized` (`NotificationPrompt`).
    /// `ForegroundNotificationPresenter` shows a posted notification while the
    /// app is in the foreground.
    private func announceGeofences() {
        Task {
            for await event in await sdk.geofenceEvents() {
                switch event {
                case .entered(let geofence): await announce(name: geofence.name, entered: true)
                case .exited(let geofence, _): await announce(name: geofence.name, entered: false)
                default: break
                }
            }
        }
    }

    private func announce(name: String?, entered: Bool) async {
        let note = NotificationPrompt.note(name: name, entered: entered)
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else {
            Proximiio.recordDiagnosticsEvent(.state, "\(note.logLine) · not authorized")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        content.sound = .default
        // A new identifier per event, so notifications do not replace each other.
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        Proximiio.recordDiagnosticsEvent(.state, "\(note.logLine) · notified")
    }
}
