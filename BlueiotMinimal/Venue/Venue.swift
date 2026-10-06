//
//  Venue.swift
//  BlueiotMinimal
//
//  Positioning: SDK start, attachment of the wristband binding's position
//  provider, and a local notification per geofence event.
//
//  The venue's BlueIoT anchors locate the wristband and report to the
//  Proximi.io relay-api; the phone scans nothing.
//  `ProximiioConfiguration.relayOnly(token:runsInBackground:)` is the preset for
//  this integration: it disables the SDK's iBeacon, Eddystone and UWB sources.
//  The rest is two calls, start the SDK and attach the provider, and one
//  notification per geofence event.
//
//  Background positioning requires four settings. Each one missing has the same
//  symptom: positioning stops 30 seconds after the screen locks, as if the relay
//  had disconnected. `runsInBackground: true` on the SDK configuration (this
//  file) and on the binding configuration (`VenueConfiguration.binding`); the
//  `location` background mode and its purpose string (`project.yml`); and
//  location authorization (`LocationPrompt`).
//
import Foundation
import Proximiio
import UserNotifications
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

@MainActor
final class Venue {

    /// The started SDK. `VenueMapScreen` passes it to the map, which reads the
    /// venue, the floors and the live position from it.
    let sdk: Proximiio

    /// The binding client whose provider delivers the wristband's positions.
    private let binding: BlueiotWristbandBinding

    /// The name of the attached provider, kept so the debug journey playback can
    /// detach it. Detaching is by name.
    private var attachedProvider: String?

    #if DEBUG
    /// Debug builds only. The journey playback that replaces the relay, and its
    /// state for the map screen. See JourneyPlayback.swift.
    let playback = JourneyPlaybackController()
    #endif

    private init(sdk: Proximiio, binding: BlueiotWristbandBinding) {
        self.sdk = sdk
        self.binding = binding
        announceGeofences()
    }

    /// The SDK configuration. Separate from `start` so a test can read the
    /// background setting from it. `runsInBackground` defaults to `false`.
    static func configuration(token: String) -> ProximiioConfiguration {
        .relayOnly(token: token, runsInBackground: true)
    }

    /// Requests location authorization, authenticates, starts positioning,
    /// downloads the venue and attaches the binding's position provider.
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
    ///
    /// The binding's provider is attached once. It follows whichever session
    /// the binding holds, so a new bind, a take-over or an ended visit needs no
    /// re-attach.
    static func start(token: String, binding: BlueiotWristbandBinding) async throws -> Venue {
        let sdk = try Proximiio(configuration: configuration(token: token))
        _ = await sdk.requestPermissions()
        _ = try await sdk.authenticate()
        try await sdk.start()
        _ = try await sdk.loadRouteNetwork()
        let venue = Venue(sdk: sdk, binding: binding)
        #if DEBUG
        // Debug builds launched with `-journeyPlayback <id>` play a journey instead
        // of attaching the binding's provider. See JourneyPlaybackLaunch.swift.
        if let request = JourneyPlaybackLaunch.request(from: ProcessInfo.processInfo.arguments) {
            await venue.playJourney(id: request.journeyID, options: request.options)
            return venue
        }
        #endif
        await venue.attachRelay()
        return venue
    }

    /// Attaches the binding's position provider.
    ///
    /// The relay-api sends Proximi.io floor levels and, when it knows it, the
    /// floor id. The SDK resolves a level against the floors it synced.
    private func attachRelay() async {
        let provider = binding.positionProvider
        attachedProvider = provider.name
        await sdk.attachPositionProvider(provider)
    }

    /// Detaches the attached provider, if any.
    private func detachProvider() async {
        guard let attachedProvider else { return }
        await sdk.detachPositionProvider(named: attachedProvider)
        self.attachedProvider = nil
    }

    #if DEBUG
    /// Debug builds only. Fetches a journey by id and plays it in place of the
    /// attached provider. The `-journeyPlayback` launch argument uses this call.
    /// On a failed fetch nothing is attached, and `playback` shows the reason.
    func playJourney(id: String, options: JourneyPlaybackOptions) async {
        playback.begin(title: id)
        do {
            await playJourney(try await sdk.fetchJourney(id: id), options: options)
        } catch {
            await detachProvider()
            Proximiio.recordDiagnosticsEvent(.state, "journey playback failed: \(error.localizedDescription)")
            playback.fail(error.localizedDescription)
        }
    }

    /// Debug builds only. Plays `journey` in place of the attached provider,
    /// usually the binding's. The journey picker uses this call. `journey` must pass
    /// `validationFailure()`; the provider plays what it is given.
    func playJourney(_ journey: ProximiioJourney, options: JourneyPlaybackOptions) async {
        await detachProvider()
        await playback.end()
        playback.begin(title: journey.displayName)
        let provider = JourneyPlaybackLaunch.provider(for: journey, options: options)
        attachedProvider = provider.name
        Proximiio.recordDiagnosticsEvent(.state, "journey playback: \(journey.displayName), \(options.logLine)")
        await sdk.attachPositionProvider(provider)
        playback.attached(provider)
    }

    /// Debug builds only. Detaches the playback and attaches the binding's
    /// provider again, as `start` does without a launch argument.
    func stopJourney() async {
        await detachProvider()
        await playback.end()
        await attachRelay()
    }
    #endif

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
