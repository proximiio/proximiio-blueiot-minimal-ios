//
//  JourneyStore.swift
//  BlueiotMinimal
//
//  Where a visit is kept between launches, and how a picked place becomes a stop.
//
//  `Journey` is `Codable` and each stop carries its own state, so writing it whenever
//  it changes is the whole of "my afternoon survived the app being closed": the stops
//  come back with the ones already seen marked, and the navigator recomputes the leg
//  from the first fix after launch. A visitor who closed the app in one gallery is
//  routed onward from wherever they re-open it.
//
import Foundation
import ProximiioMap

enum JourneyStore {
    private static let key = "BlueiotMinimal.journey"

    /// The visit in progress, or `nil` when there is none. A value written by an
    /// older build that no longer decodes is treated as none rather than as a crash.
    static func load(from store: UserDefaults = .standard) -> Journey? {
        guard let data = store.data(forKey: key),
              let journey = try? JSONDecoder().decode(Journey.self, from: data),
              !journey.stops.isEmpty
        else { return nil }
        return journey
    }

    /// `nil`, or a journey with no stops, clears it — so ending a visit is the same
    /// call as saving one.
    static func save(_ journey: Journey?, to store: UserDefaults = .standard) {
        guard let journey, !journey.stops.isEmpty,
              let data = try? JSONEncoder().encode(journey)
        else {
            store.removeObject(forKey: key)
            return
        }
        store.set(data, forKey: key)
    }
}

extension JourneyStop {
    /// A stop is a place the visitor picked. The POI's own id is used both as the
    /// stop id and as `poiID`, so a journey read back off disk still points at
    /// somewhere in the venue rather than at a coordinate nobody can name.
    init(_ poi: VenuePOI) {
        self.init(
            id: poi.id,
            title: poi.title,
            coordinate: MapCoordinate(
                latitude: poi.coordinate.latitude,
                longitude: poi.coordinate.longitude
            ),
            floor: FloorKey(poi.level),
            poiID: poi.id
        )
    }
}
