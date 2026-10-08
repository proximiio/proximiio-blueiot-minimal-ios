//
//  PassedStops.swift
//  BlueiotMinimal
//
//  Detects the stops the visitor walked past. The map library detects arrival
//  only at the active stop, and only after the visitor stays within the arrival
//  radius for the dwell time. A visitor who walks past a stop, or reaches a stop
//  out of order, gets no arrival.
//
//  A stop counts as passed when a fix lands within `enterMeters` of it on its
//  floor, and a later fix on that floor is more than `exitMeters` from it. A fix
//  with an accuracy worse than `maxAccuracyMeters` does not enter a stop.
//
import CoreLocation
import ProximiioMap

struct PassedStops {
    var enterMeters: Double = 5
    var exitMeters: Double = 9
    var maxAccuracyMeters: Double = 8

    /// The stops the visitor has come within `enterMeters` of and not yet left.
    private(set) var near: Set<String> = []

    /// Takes one fix. Returns the ids of the `openStops` the visitor has just
    /// walked past.
    mutating func update(
        coordinate: MapCoordinate,
        level: Double?,
        horizontalAccuracy: Double?,
        openStops: [JourneyStop]
    ) -> [String] {
        near.formIntersection(openStops.map(\.id))
        guard let level else { return [] }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let isPrecise = (horizontalAccuracy ?? 0) <= maxAccuracyMeters
        var passed: [String] = []
        for stop in openStops {
            guard let stopLevel = stop.floor?.level, Int(stopLevel.rounded()) == Int(level.rounded()) else { continue }
            let distance = here.distance(from: CLLocation(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude))
            if distance <= enterMeters {
                if isPrecise { near.insert(stop.id) }
            } else if distance > exitMeters, near.remove(stop.id) != nil {
                passed.append(stop.id)
            }
        }
        return passed
    }

    /// `journey` with the stops in `ids` set to `.done`.
    static func marking(_ ids: [String], doneIn journey: Journey) -> Journey {
        var journey = journey
        for index in journey.stops.indices where ids.contains(journey.stops[index].id) {
            journey.stops[index].state = .done
        }
        return journey
    }
}
