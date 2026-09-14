//
//  Venue.swift
//  BlueiotMinimal
//
//  THE WHOLE OF THIS APP'S POSITIONING.
//
//  The venue's anchors locate the wristband and report to a Proximi.io cloud relay;
//  the phone scans nothing. `ProximiioConfiguration.relayOnly(token:)` is the preset
//  for exactly that shape of app — it turns the SDK's own iBeacon, Eddystone, UWB and
//  CoreLocation sources off, so there is no radio to tune and no permission to ask
//  for. Everything else here is two calls: start the SDK, attach the relay provider.
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

    /// Authenticates, starts, and downloads the venue.
    ///
    /// Three awaits, in this order, and none of them is optional:
    ///  1. `authenticate()` validates the token and runs the first sync — which is
    ///     what fills `floors()` that `follow(_:)` below reads.
    ///  2. `start()` starts positioning. Under `relayOnly` that means the engine and
    ///     nothing else; the fixes arrive once a provider is attached.
    ///  3. `loadRouteNetwork()` downloads the venue's GeoJSON: the POIs this app
    ///     searches *and* the path network `computeRoute` walks, cached locally, so
    ///     it is the one network call wayfinding needs.
    static func start(token: String) async throws -> Venue {
        let sdk = try Proximiio(configuration: .relayOnly(token: token))
        _ = try await sdk.authenticate()
        try await sdk.start()
        _ = try await sdk.loadRouteNetwork()
        return Venue(sdk: sdk)
    }

    /// Points positioning at one wristband.
    ///
    /// Safe to call again with a different band: the previous provider is detached
    /// first, so changing the id is a re-attach rather than a restart.
    func follow(_ wristband: WristbandID) async {
        if let attachedProvider {
            await sdk.detachPositionProvider(named: attachedProvider)
            self.attachedProvider = nil
        }
        guard let host = VenueConfiguration.relayHost,
              let endpoint = BlueiotCloudRelayEndpoint(text: host)
        else { return }

        let floors = await sdk.floors()
        let provider = BlueiotCloudRelayPositionProvider(configuration: .init(
            endpoint: endpoint,
            token: VenueConfiguration.relayToken,
            tagID: wristband.canonical,
            floorNoMap: Self.floorIDsByEngineNumber(floors),
            // Where the dot goes when the relay names a floor the venue does not know.
            defaultFloorID: floors.first { $0.level == 0 }?.id
        ))
        attachedProvider = provider.name
        await sdk.attachPositionProvider(provider)
    }

    /// Engine floor number → Proximi.io floor id. This is how a number in a relay
    /// message becomes the level the map draws the dot on.
    ///
    /// SEAM: it assumes the venue's Blueiot engine numbers floors the way Proximi.io
    /// does, ground = 0. LocalSense deployments are often numbered from 1 instead. If
    /// yours is, add the offset to `number` here — this is the only place in the app
    /// where engine floor numbers are translated.
    static func floorIDsByEngineNumber(_ floors: [ProximiioFloor]) -> [String: String] {
        floors.reduce(into: [:]) { map, floor in
            let number = String(Int(floor.level.rounded()))
            // A multi-building organisation can have two floors at the same level;
            // the first wins rather than the last, so the map is stable across syncs.
            if map[number] == nil { map[number] = floor.id }
        }
    }
}
