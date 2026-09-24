//
//  VisitRules.swift
//  BlueiotMinimal
//
//  The rules behind the visit's text and controls: when a new visit is put in
//  the shortest order, what the plan says about the order, and what the bar
//  says during a stop-off. `JourneyBar` and `JourneyPlanSheet` call these and
//  hold no rule of their own.
//
import ProximiioMap

/// The shortest order applied once to a new visit, without a tap.
enum StartOrder {
    /// Whether a visit can still be put in the shortest order without a tap.
    ///
    /// `true` while no stop is reached, done or skipped and no stop-off is in
    /// the plan. The stop being walked to may still move. A visit restored from
    /// disk is not checked here: `JourneyBar` orders only a visit it created.
    static func isOwed(_ journey: Journey) -> Bool {
        journey.stops.count > 1 && journey.stops.allSatisfy {
            ($0.state == .pending || $0.state == .active) && $0.kind == .planned
        }
    }

    /// Shown on the bar while no fix has arrived. The order is measured on the
    /// first fix.
    static let waitingNote = "Your stops are put in the shortest order when your position arrives."

    /// The note on the bar after the order was measured.
    ///
    /// - Parameters:
    ///   - proposal: the result of `proposeOrder(from: .visitor)`.
    ///   - applied: whether `apply(_:)` took it.
    /// - Returns: `nil` when nothing was measured, or when a shorter order was
    ///   refused as stale.
    static func note(for proposal: JourneyOrderProposal?, applied: Bool) -> String? {
        guard let proposal else { return nil }
        let meters = Int(proposal.savedMeters.rounded())
        guard proposal.isImprovement, meters >= 1 else {
            return "Your stops are already in the shortest order."
        }
        return applied ? "Stops put in the shortest order: \(meters) m less to walk." : nil
    }

    /// The note on the bar once the first fix has been handled: ordered, found
    /// not owed, not measured, or refused.
    ///
    /// - Parameters:
    ///   - current: the note on the bar.
    ///   - result: the note from `note(for:applied:)`, or `nil`.
    /// - Returns: `result` when there is one. Otherwise `current`, except the
    ///   waiting note, which is cleared: no position is awaited any more.
    static func noteAfterFirstFix(current: String?, result: String?) -> String? {
        result ?? (current == waitingNote ? nil : current)
    }
}

/// The order row in **Your visit**.
enum OrderAdvice: Equatable {
    /// Fewer than two stops can move. No row is shown.
    case none
    /// A proposal is being measured, or the one held no longer matches the plan
    /// and is measured again.
    case measuring
    /// `proposeOrder` returned `nil`: a stop in the current order has no route.
    case unmeasurable
    /// No order is at least 1 m shorter.
    case alreadyShortest
    /// A shorter order, `meters` less to walk. A tap applies it.
    case save(meters: Int)

    static func of(
        _ proposal: JourneyOrderProposal?,
        movableStops: Int,
        isMeasuring: Bool,
        canApply: Bool
    ) -> OrderAdvice {
        guard movableStops > 1 else { return .none }
        if isMeasuring { return .measuring }
        guard let proposal else { return .unmeasurable }
        guard canApply else { return .measuring }
        let meters = Int(proposal.savedMeters.rounded())
        return proposal.isImprovement && meters >= 1 ? .save(meters: meters) : .alreadyShortest
    }

    /// The row's text. `.save` is a button label; the others are plain text.
    var text: String? {
        switch self {
        case .none: nil
        case .measuring: "Measuring the shortest order…"
        case .unmeasurable: "The order cannot be measured: a stop has no route."
        case .alreadyShortest: "Your stops are already in the shortest order."
        case .save(let meters): "Save \(meters) m by reordering"
        }
    }
}

/// The text of a stop-off: a stop at the nearest place of one kind, inserted
/// before the planned stop by `JourneyNavigator.detour(to:)`.
enum StopOff {
    /// The header of the **Stop off** menu.
    static func menuHeader(goingTo planned: String?) -> String {
        guard let planned else { return "Go to the nearest one first. Your plan continues afterwards." }
        return "Go to the nearest one before \(planned). Your plan continues afterwards."
    }

    /// The bar's title during a stop-off.
    static func title(_ stop: JourneyStop) -> String {
        "Stop off: \(stop.title)"
    }

    /// The line under the title during a stop-off.
    ///
    /// - Parameters:
    ///   - hasArrived: whether the visitor has reached the stop-off.
    ///   - next: the planned stop the visit returns to, or `nil` when none is left.
    static func status(hasArrived: Bool, next: String?) -> String {
        let then = next.map { "then on to \($0)" } ?? "then the visit ends"
        return hasArrived
            ? "Tap Continue when you are done, \(then)."
            : "On the way, \(then). Back to the plan cancels the stop-off."
    }
}
