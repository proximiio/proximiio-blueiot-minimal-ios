//
//  GuidanceLine.swift
//  BlueiotMinimal
//
//  TURN-BY-TURN, IN ONE LINE.
//
//  The map library follows whatever route it is drawing and republishes a
//  `RouteGuidance` on every fix — which manoeuvre is next, how far is still to walk
//  to it, whether the visitor left the corridor, whether they arrived. One value
//  rather than six properties, so a view that reads four of them re-renders once.
//
//  A single route and a journey leg produce the same value, which is why this is a
//  view of its own rather than two copies of the same sentence.
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

    /// One sentence for one fix, in the order a walker needs them: arrival ends the
    /// walk, leaving the route interrupts it, and otherwise it is the turn in hand
    /// and the metres still to walk to it.
    ///
    /// `distanceToManoeuvreMeters` is the number that shrinks —
    /// `RouteManoeuvre.legMeters` is the planned length of the leg and never moves.
    ///
    /// Leaving the route is said, not acted on. The flag latches after three fixes
    /// beyond twelve metres and clears itself on the first fix back inside, so a
    /// detector of this app's own could only disagree with the one already running.
    static func sentence(for guidance: RouteGuidance) -> String {
        if guidance.hasArrived { return "You have arrived." }
        if guidance.isOffRoute { return "You have left the route." }
        let metres = Int(guidance.distanceToManoeuvreMeters.rounded())
        return "\(instruction(for: guidance.manoeuvre?.kind)) · \(metres) m"
    }

    /// `RouteManoeuvre.Kind` carries no display strings, and neither does the SDK's
    /// `RouteInstruction.Kind` underneath it: a library that shipped English would be
    /// shipping the wrong language to most venues. These sentences are the app's, and
    /// this is the one function to reach `NSLocalizedString` into.
    static func instruction(for kind: RouteManoeuvre.Kind?) -> String {
        switch kind {
        case .turnLeft: "Turn left"
        case .turnSlightLeft: "Bear left"
        case .turnSharpLeft: "Turn sharp left"
        case .turnRight: "Turn right"
        case .turnSlightRight: "Bear right"
        case .turnSharpRight: "Turn sharp right"
        // The changer the route actually uses, so the sentence and the pin on the
        // map name the same thing: "elevator", "escalator", "staircase", "ramp".
        case .levelChange(let change):
            "Take the \(change.featureType) to level \(MapLevelFormat.trimmed(change.toLevel))"
        case .arrive: "Arrive"
        default: "Continue straight"
        }
    }
}
