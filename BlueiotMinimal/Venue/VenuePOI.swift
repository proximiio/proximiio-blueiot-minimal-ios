//
//  VenuePOI.swift
//  BlueiotMinimal
//
//  One place a visitor can search for and be routed to.
//
//  Built from `Proximiio.features()` — the SDK's own venue model, read out of its
//  local cache, which `Venue.start` filled with `loadRouteNetwork()`. There is no
//  second download and no app-side place model beyond these four fields; add to it
//  when your product needs an opening time or a photo, not before.
//
import CoreLocation
import Foundation
import Proximiio

struct VenuePOI: Identifiable, Equatable {
    let id: String
    let title: String
    let coordinate: ProximiioCoordinate
    /// The floor it is on. `computeRoute` takes this as `toLevel`.
    let level: Double
    /// What kind of place the venue says this is, and `nil` when it says nothing.
    /// A Proximi.io amenity id is `<category>:<amenity>` — the only thing in the
    /// data that tells a toilet from an exhibit.
    let amenityID: String?

    /// Every place in the venue, alphabetically.
    static func all(in features: [ProximiioFeature]) -> [VenuePOI] {
        features
            .compactMap(VenuePOI.init(feature:))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Substring match, case- and diacritic-insensitive. An empty query matches
    /// everything, which is what lets the search sheet open on the full list.
    static func matching(_ query: String, in pois: [VenuePOI]) -> [VenuePOI] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return pois }
        return pois.filter {
            $0.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// `nil` for every feature that is not a searchable place: the venue's rooms,
    /// walls, level changers and its walkable path network all arrive in the same
    /// array.
    private init?(feature: ProximiioFeature) {
        guard feature.propertyType == "poi",
              let geometry = feature.geometry,
              geometry.type == "Point",
              let pair = geometry.coordinates.arrayValue,
              pair.count >= 2,
              // GeoJSON is [longitude, latitude] — the reverse of how it is spoken.
              let longitude = pair[0].doubleValue,
              let latitude = pair[1].doubleValue,
              longitude.isFinite, latitude.isFinite
        else { return nil }

        id = feature.id
        // Organisations label places `title` or `name`; either is the visitor's word
        // for the place. Falling back to the id keeps a mislabelled POI routable
        // rather than invisible.
        title = Self.text(feature.properties?["title"])
            ?? Self.text(feature.properties?["name"])
            ?? feature.id
        coordinate = ProximiioCoordinate(latitude: latitude, longitude: longitude)
        level = feature.level ?? 0
        amenityID = Self.text(feature.properties?["amenity"])
    }

    /// The nearest place of every kind the venue tags, from where the visitor is
    /// standing — which is the whole of "find me a toilet".
    ///
    /// The kinds are read off the venue's own data rather than listed here. A venue
    /// that tags toilets and cafes offers toilets and cafes; one that tags only its
    /// artworks offers those; one that tags nothing offers nothing, which is a
    /// better answer than a hard-coded category no POI carries. Straight-line
    /// distance, deliberately: this picks which place to ask for a route to, and the
    /// route itself is the SDK's answer to how far it really is.
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
