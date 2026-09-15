//
//  Venue.swift
//  BlueiotMinimal
//
//  THE WHOLE OF THIS APP'S POSITIONING.
//
//  The venue's anchors locate the wristband and report to a Proximi.io cloud relay;
//  the phone scans nothing. `ProximiioConfiguration.relayOnly(token:runsInBackground:)`
//  is the preset for exactly that shape of app — it turns the SDK's own iBeacon,
//  Eddystone and UWB sources off, so there is no radio to tune. Everything else here
//  is two calls: start the SDK, attach the relay provider.
//
//  POSITIONING CARRIES ON IN A POCKET. That takes four things, and each one missing
//  looks the same — the dot stops 30 seconds after the screen locks, as if the
//  relay had died: `runsInBackground: true` on the SDK configuration and again on
//  the relay provider's (both below); the `location` background mode and its
//  purpose string (`project.yml`); and location authorization (`LocationPrompt`).
//
import Foundation
import Proximiio

@MainActor
final class Venue {

    /// The started SDK. `VenueMapScreen` hands this to the map, which reads the
    /// venue, the floors and the live position off it.
    let sdk: Proximiio

    /// So a second `follow(_:)` can take the first one down. Only the name is kept —
    /// detaching is by name.
    private var attachedProvider: String?

    private init(sdk: Proximiio) { self.sdk = sdk }

    /// The SDK, configured for this shape of app. Apart from `start` so a test can
    /// read the flag off it — `runsInBackground` defaults to `false`.
    static func configuration(token: String) -> ProximiioConfiguration {
        .relayOnly(token: token, runsInBackground: true)
    }

    /// Asks for location, authenticates, starts, and downloads the venue.
    ///
    /// Four awaits, in this order, and none of them is optional:
    ///  1. `requestPermissions()` is the system prompt behind `LocationPrompt`. iOS
    ///     asks once; an answered question returns at once with its answer, so a
    ///     returning visitor pays nothing here.
    ///  2. `authenticate()` validates the token and runs the first sync — which is
    ///     what fills the floors the SDK resolves relay fixes against.
    ///  3. `start()` starts positioning. Under `relayOnly` that means the engine and
    ///     the keep-alive location session; the fixes arrive once a provider is
    ///     attached.
    ///  4. `loadRouteNetwork()` downloads the venue's GeoJSON: the POIs this app
    ///     searches *and* the path network `computeRoute` walks, cached locally, so
    ///     it is the one network call wayfinding needs.
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
    /// Safe to call again with a different band: the previous provider is detached
    /// first, so changing the id is a re-attach rather than a restart.
    ///
    /// WHICH STOREY A FIX LANDS ON is not this app's arithmetic. An engine floor
    /// number *is* the Proximi.io floor level, and the SDK already syncs every floor
    /// with its level, so it derives the number-to-floor table itself and tells you
    /// in the log when a fix names a number the venue has no floor for. Pass no
    /// `floorNoMap` and none of that happens: a table you supply switches derivation
    /// off.
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
            // Without this the SDK pauses the provider on backgrounding, whatever
            // the process itself is allowed to do.
            runsInBackground: true
        )
        // The one thing the SDK cannot know: this venue's LocalSense calls the ground
        // floor 1 where Proximi.io calls it level 0. Delete this line, and
        // `BLUEIOT_GROUND_FLOOR_NO` with it, the day the deployment is renumbered.
        configuration.engineGroundFloorNumber = VenueConfiguration.groundFloorNumber

        let provider = BlueiotCloudRelayPositionProvider(configuration: configuration)
        attachedProvider = provider.name
        await sdk.attachPositionProvider(provider)
    }
}
