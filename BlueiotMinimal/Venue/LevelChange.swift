//
//  LevelChange.swift
//  BlueiotMinimal
//
//  The rules behind the level change card (LevelChangeOverlay.swift).
//
//  Relay positions stay on the old floor while a lift moves, then move to the
//  new floor. `LiftDetector` reports a ride: fixes inside a lift area for
//  `dwell` seconds. `LevelChangeDetector` reports the floor change.
//
import Foundation
import Proximiio
import ProximiioMap

struct LevelChange: Equatable {
    var from: Int
    var to: Int
    var isUp: Bool { to > from }
}

struct LevelChangeDetector {
    /// The number of consecutive fixes on a new floor that confirm the change.
    /// With 1, the change is reported on the first fix on the new floor.
    var confirmations = 1
    private(set) var level: Int?
    private var candidate: Int?
    private var candidateFixes = 0

    /// Takes the floor of one fix. Returns the change once the new floor is
    /// confirmed. The first floor is no change. A fix without a floor is ignored.
    mutating func update(level fixLevel: Double?) -> LevelChange? {
        guard let fixLevel else { return nil }
        let next = Int(fixLevel.rounded())
        guard let current = level else {
            level = next
            return nil
        }
        guard next != current else {
            candidate = nil
            candidateFixes = 0
            return nil
        }
        if candidate == next {
            candidateFixes += 1
        } else {
            candidate = next
            candidateFixes = 1
        }
        guard candidateFixes >= confirmations else { return nil }
        level = next
        candidate = nil
        candidateFixes = 0
        return LevelChange(from: current, to: next)
    }
}

/// A lift cabin outline: a venue polygon feature of type `elevator`. The
/// outline is drawn on one floor and applies on every floor.
struct LiftArea {
    let ring: [MapCoordinate]

    /// The lift areas among `features`. A feature without a Polygon or
    /// MultiPolygon geometry is skipped.
    static func all(features: [ProximiioFeature]) -> [LiftArea] {
        features.compactMap { feature in
            guard feature.propertyType == "elevator", let geometry = feature.geometry,
                  let ring = outerRing(type: geometry.type, coordinates: geometry.coordinates)
            else { return nil }
            return LiftArea(ring: ring)
        }
    }

    /// The outer ring of a GeoJSON Polygon, or of the first polygon of a
    /// MultiPolygon. `nil` for another type or fewer than three points.
    static func outerRing(type: String, coordinates: JSONValue) -> [MapCoordinate]? {
        let rings: JSONValue? = switch type {
        case "Polygon": coordinates.arrayValue?.first
        case "MultiPolygon": coordinates.arrayValue?.first?.arrayValue?.first
        default: nil
        }
        let ring = rings?.arrayValue?.compactMap { pair -> MapCoordinate? in
            guard let pair = pair.arrayValue, pair.count >= 2,
                  let longitude = pair[0].doubleValue, let latitude = pair[1].doubleValue
            else { return nil }
            return MapCoordinate(latitude: latitude, longitude: longitude)
        }
        guard let ring, ring.count >= 3 else { return nil }
        return ring
    }

    /// Ray casting on the longitude axis.
    func contains(_ coordinate: MapCoordinate) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.latitude > coordinate.latitude) != (b.latitude > coordinate.latitude) {
                let x = (b.longitude - a.longitude) * (coordinate.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                if coordinate.longitude < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

/// Reports a lift ride. The visitor counts as in the lift after `dwell` seconds
/// of fixes inside a lift area, so walking through a lift area is no ride. The
/// ride ends after `exitFixes` consecutive fixes outside.
struct LiftDetector {
    enum Event: Equatable { case boarded, left }

    var dwell: TimeInterval = 3
    var exitFixes = 2
    private(set) var isRiding = false
    private var insideSince: Date?
    private var outsideFixes = 0

    mutating func update(inLift: Bool, at time: Date) -> Event? {
        if inLift {
            outsideFixes = 0
            let since = insideSince ?? time
            insideSince = since
            guard !isRiding, time.timeIntervalSince(since) >= dwell else { return nil }
            isRiding = true
            return .boarded
        }
        outsideFixes += 1
        guard outsideFixes >= exitFixes else { return nil }
        insideSince = nil
        guard isRiding else { return nil }
        isRiding = false
        return .left
    }
}

/// What the level change card shows: the ride, then the arrival on the new floor.
struct LevelChangeCard: Equatable {
    enum Phase: Equatable { case riding, arrived }

    var phase: Phase
    var from: Int
    /// The floor the visitor goes to. During a ride it is the target of the
    /// route's level change at this lift, or `nil` without a route.
    var to: Int?

    /// The card's text.
    var title: String {
        switch (phase, to) {
        case (.arrived, let to?): "Level \(to)"
        case (.riding, let to?): "Going to level \(to)"
        default: "In the lift"
        }
    }

    /// An SF Symbol: an arrow towards the target floor, or a lift without one.
    var symbol: String {
        guard let to else { return "arrow.up.arrow.down" }
        return to > from ? "arrow.up" : "arrow.down"
    }
}
