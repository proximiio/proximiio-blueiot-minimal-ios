//
//  JourneyStore.swift
//  BlueiotMinimal
//
//  Persistence of the visit between launches, and the conversion of a picked
//  place into a stop.
//
//  `Journey` is `Codable` and each stop carries its state. Writing it on every
//  change restores the stops and their states on the next launch. The navigator
//  recomputes the leg from the first fix after launch, so the visit resumes from
//  the visitor's current position.
//
import Foundation
import ProximiioMap

enum JourneyStore {
    private static let key = "BlueiotMinimal.journey"

    /// The visit in progress, or `nil` when there is none. A value from an older
    /// build that no longer decodes is treated as `nil`, not as an error.
    static func load(from store: UserDefaults = .standard) -> Journey? {
        guard let data = store.data(forKey: key),
              let journey = try? JSONDecoder().decode(Journey.self, from: data),
              !journey.stops.isEmpty
        else { return nil }
        return journey
    }

    /// `nil` or a journey with no stops removes the stored value, so ending a
    /// visit uses the same call as saving one.
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
    /// A stop is a picked place. The POI id is used as both the stop id and
    /// `poiID`, so a stored journey still refers to a venue feature.
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
