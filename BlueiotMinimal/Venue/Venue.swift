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
            floorNoMap: Self.floorIDsByEngineNumber(
                floors,
                groundFloorNumber: VenueConfiguration.groundFloorNumber,
                anchorPlaceID: VenueConfiguration.anchorPlaceID
            ),
            // Where the dot goes when the relay names a floor the venue does not know.
            defaultFloorID: Self.groundFloorID(
                floors,
                anchorPlaceID: VenueConfiguration.anchorPlaceID
            )
        ))
        attachedProvider = provider.name
        await sdk.attachPositionProvider(provider)
    }

    /// Engine floor number → Proximi.io floor id. This is how a number in a relay
    /// message becomes the storey the map draws the dot on.
    ///
    /// THE RULE, in two halves, both of them this venue's and both set in
    /// `Config/App.xcconfig`:
    ///
    /// 1. **The offset.** Proximi.io numbers the ground floor level 0. A Blueiot
    ///    LocalSense engine numbers it whatever the deployment was configured with,
    ///    and these deployments usually start at 1 — this one does.
    ///    `BLUEIOT_GROUND_FLOOR_NO` is that number and the engine floor is
    ///    `level + groundFloorNumber`, so level 0 is engine floor 1 here. Mapped
    ///    one-to-one instead, every fix landed a storey too high.
    ///
    /// 2. **The anchor place.** One Proximi.io organisation can hold several
    ///    buildings; this one holds nine, and eight of them have a floor at level 0.
    ///    `BLUEIOT_ANCHOR_PLACE_ID` names the building this app is deployed in. It
    ///    wins every storey it has, and the other places only fill numbers it does
    ///    not — so "engine floor 2" is *this* building's first floor rather than
    ///    whichever building the sync happened to return first, and a number only
    ///    another place has still resolves to something rather than to nothing.
    ///
    /// A different venue changes those two values and nothing else. An engine that
    /// numbers from 0 leaves the offset empty and this becomes the identity map; a
    /// single-building organisation leaves the place id empty and the first floor at
    /// each level wins, because there is nothing to prefer it over. A number below
    /// the ground floor (engine 0 when the ground floor is 1) maps to nothing on
    /// purpose — `defaultFloorID` is a better answer than a wrong floor id.
    static func floorIDsByEngineNumber(
        _ floors: [ProximiioFloor],
        groundFloorNumber: Int,
        anchorPlaceID: String?
    ) -> [String: String] {
        func engineNumber(_ floor: ProximiioFloor) -> String {
            String(Int(floor.level.rounded()) + groundFloorNumber)
        }
        var map: [String: String] = [:]
        if let anchorPlaceID {
            for floor in floors where floor.placeId == anchorPlaceID {
                map[engineNumber(floor)] = floor.id
            }
        }
        for floor in floors where map[engineNumber(floor)] == nil {
            map[engineNumber(floor)] = floor.id
        }
        return map
    }

    /// The storey the dot falls back to when the relay names a number the venue has
    /// no floor for: the anchor building's ground floor, not whichever level 0 the
    /// sync listed first.
    static func groundFloorID(_ floors: [ProximiioFloor], anchorPlaceID: String?) -> String? {
        let ground = floors.filter { Int($0.level.rounded()) == 0 }
        guard let anchorPlaceID else { return ground.first?.id }
        return (ground.first { $0.placeId == anchorPlaceID } ?? ground.first)?.id
    }
}
