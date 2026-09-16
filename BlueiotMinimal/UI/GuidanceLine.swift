//
//  GuidanceLine.swift
//  BlueiotMinimal
//
//  One-line turn-by-turn instruction.
//
//  The map library follows the route it draws and publishes a `RouteGuidance` on
//  every position fix: the next manoeuvre, the distance to it, whether the
//  visitor is off the route and whether they have arrived. A single route and a
//  journey leg publish the same type, so both use this view.
//
import ProximiioMap
import SwiftUI

struct GuidanceLine: View {
    let guidance: RouteGuidance?

    var body: some View {
        if let guidance {
            Text(Self.sentence(for: guidance))
                .font(.subheadline)
                .lineLimit(1)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// One sentence for one fix. Arrival takes precedence, then off-route, then
    /// the next manoeuvre with the remaining distance in metres.
    ///
    /// `distanceToManoeuvreMeters` decreases as the visitor walks;
    /// `RouteManoeuvre.legMeters` is the planned leg length and does not change.
    ///
    /// Leaving the route is reported, not acted on. `isOffRoute` becomes `true`
    /// after three fixes more than twelve metres from the route and returns to
    /// `false` on the first fix back on it. The app adds no detector of its own.
    static func sentence(for guidance: RouteGuidance) -> String {
        if guidance.hasArrived { return "You have arrived." }
        if guidance.isOffRoute { return "You have left the route." }
        let metres = Int(guidance.distanceToManoeuvreMeters.rounded())
        return "\(instruction(for: guidance.manoeuvre?.kind)) · \(metres) m"
    }

    /// `RouteManoeuvre.Kind` and the SDK's `RouteInstruction.Kind` beneath it
    /// carry no display strings. The sentences below belong to the app; localise
    /// them here with `NSLocalizedString`.
    static func instruction(for kind: RouteManoeuvre.Kind?) -> String {
        switch kind {
        case .turnLeft: "Turn left"
        case .turnSlightLeft: "Bear left"
        case .turnSharpLeft: "Turn sharp left"
        case .turnRight: "Turn right"
        case .turnSlightRight: "Bear right"
        case .turnSharpRight: "Turn sharp right"
        // `featureType` is the level changer the route uses ("elevator",
        // "escalator", "staircase", "ramp"); the map marks the same feature.
        case .levelChange(let change):
            "Take the \(change.featureType) to level \(MapLevelFormat.trimmed(change.toLevel))"
        case .arrive: "Arrive"
        default: "Continue straight"
        }
    }
}
