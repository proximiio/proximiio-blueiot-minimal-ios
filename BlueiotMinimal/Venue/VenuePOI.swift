//
//  VenuePOI.swift
//  BlueiotMinimal
//
//  A place the visitor can search for and route to.
//
//  Built from `Proximiio.features()`, the SDK's venue model, read from the local
//  cache that `Venue.start` fills with `loadRouteNetwork()`. There is no second
//  download and no further app-side place model. Add fields when the product
//  needs them.
//
import CoreLocation
import Foundation
import Proximiio

struct VenuePOI: Identifiable, Equatable {
    let id: String
    let title: String
    let coordinate: ProximiioCoordinate
    /// The floor level. `computeRoute` takes it as `toLevel`.
    let level: Double
    /// The amenity id from the venue data, or `nil` when the feature has none. A
    /// Proximi.io amenity id is `<category>:<amenity>`; it is the only field that
    /// distinguishes kinds of place.
    let amenityID: String?

    /// Every place in the venue, sorted by title.
    static func all(in features: [ProximiioFeature]) -> [VenuePOI] {
        features
            .compactMap(VenuePOI.init(feature:))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Substring match, case- and diacritic-insensitive. An empty query matches
    /// everything, so the search sheet opens on the full list.
    static func matching(_ query: String, in pois: [VenuePOI]) -> [VenuePOI] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return pois }
        return pois.filter {
            $0.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Returns `nil` for every feature that is not a point POI. Rooms, walls,
    /// level changers and the path network arrive in the same array.
    private init?(feature: ProximiioFeature) {
        guard feature.propertyType == "poi",
              let geometry = feature.geometry,
              geometry.type == "Point",
              let pair = geometry.coordinates.arrayValue,
              pair.count >= 2,
              // GeoJSON coordinate order is [longitude, latitude].
              let longitude = pair[0].doubleValue,
              let latitude = pair[1].doubleValue,
              longitude.isFinite, latitude.isFinite
        else { return nil }

        id = feature.id
        // Organisations label places with `title` or `name`. The id is the fallback,
        // so a mislabelled POI stays routable.
        title = Self.text(feature.properties?["title"])
            ?? Self.text(feature.properties?["name"])
            ?? feature.id
        coordinate = ProximiioCoordinate(latitude: latitude, longitude: longitude)
        level = feature.level ?? 0
        amenityID = Self.text(feature.properties?["amenity"])
    }

    /// The nearest place of each amenity kind from `coordinate`.
    ///
    /// The kinds come from the venue data, not from a list in the app: a venue
    /// that tags toilets and cafes offers toilets and cafes; one that tags
    /// nothing offers nothing. Distance is straight-line: it selects the place
    /// to route to, and the route gives the walking distance.
    static func nearestByAmenity(
        in pois: [VenuePOI],
        from coordinate: ProximiioCoordinate
    ) -> [String: VenuePOI] {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        func metres(_ poi: VenuePOI) -> CLLocationDistance {
            here.distance(from: CLLocation(
                latitude: poi.coordinate.latitude,
                longitude: poi.coordinate.longitude
            ))
        }
        var nearest: [String: VenuePOI] = [:]
        for poi in pois {
            guard let amenityID = poi.amenityID else { continue }
            if let held = nearest[amenityID], metres(held) <= metres(poi) { continue }
            nearest[amenityID] = poi
        }
        return nearest
    }

    private static func text(_ value: JSONValue?) -> String? {
        guard let text = value?.stringValue, !text.isEmpty else { return nil }
        return text
    }
}
