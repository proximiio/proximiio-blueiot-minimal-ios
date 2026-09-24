//
//  JourneyBar.swift
//  BlueiotMinimal
//
//  Journey UI: the active stop, the remaining visit and the controls that change
//  the plan.
//
//  `JourneyNavigator` owns the walking. It computes each leg from the live
//  position, draws and follows it through the map session and measures what
//  remains. With `deviationPolicy = .askApp` it does not re-route a visitor who
//  leaves the leg; this view asks the visitor instead (`DeviationPrompt`).
//  The library does not reorder a journey on its own. This view applies one
//  order without a tap: the shortest order from the visitor's position, once,
//  before a new visit starts. After that a reorder is proposed, or asked for,
//  and a tap applies it.
//
import Proximiio
import ProximiioMap
import SwiftUI

struct JourneyBar: View {
    let places: [VenuePOI]
    /// Called when the visit ends; the map screen restores its search bar.
    let onEnd: () -> Void

    @StateObject private var navigator: JourneyNavigator
    /// Detour offers by amenity. Rebuilt when the set of nearest places changes.
    /// Empty shows no button.
    @State private var detours: [Detour] = []
    @State private var isShowingPlan = false
    /// The open deviation prompt, or `nil`. Set from `navigator.events`.
    @State private var prompt: DeviationPrompt?

    @MainActor
    init(
        session: ProximiioMapSession,
        journey: Journey,
        places: [VenuePOI],
        onEnd: @escaping () -> Void
    ) {
        self.places = places
        self.onEnd = onEnd
        // No automatic re-route when the visitor leaves the leg. The drawn leg
        // stays until the visitor answers the prompt. The thresholds are the
        // library defaults (`JourneyDeviationRules`).
        _navigator = StateObject(wrappedValue: {
            let navigator = JourneyNavigator(session: session, journey: journey)
            navigator.deviationPolicy = .askApp
            return navigator
        }())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            GuidanceLine(guidance: navigator.guidance)
            if let prompt { deviationPrompt(prompt) }
            buttons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(16)
        .task {
            // A new visit is put in the shortest order from the visitor's
            // position before it starts. `proposeOrder(from: .visitor)` can move
            // the first pick; before `start()` it measures from the session's
            // latest fix. It returns `nil` without a fix, and the tap order is
            // kept. A restored visit that has already started is not reordered.
            if navigator.journey.stops.allSatisfy({ $0.state == .pending }),
               let order = await navigator.proposeOrder(from: .visitor),
               order.isImprovement {
                await navigator.apply(order)
            }
            // `start()` draws nothing until the first fix; the leg is computed
            // from the live position.
            await navigator.start()
            // The only additional download in the app, made when a visit starts.
            // `amenities()` reads the local store first: with a stored catalogue
            // it makes no network request and does not throw. On failure only
            // the detour offers are missing.
            _ = try? await navigator.session.sdk.amenities()
            detours = await offers()
        }
        .task(id: navigator.session.position?.coordinate) { detours = await offers() }
        // Each access to `events` is a new stream of the events emitted after
        // it. The stream ends when this task is cancelled with the view.
        .task {
            for await event in navigator.events {
                prompt = DeviationPrompt.after(event, showing: prompt)
            }
        }
        .onDisappear { navigator.end() }
        // `Journey` is `Codable` and each stop carries its state. Saving on every
        // change is what restores the visit on the next launch.
        .onChange(of: navigator.journey) { JourneyStore.save($1) }
        .sheet(isPresented: $isShowingPlan) {
            JourneyPlanSheet(navigator: navigator, places: places, onEnd: onEnd)
        }
    }

    /// The active stop and the remaining visit.
    ///
    /// `overview` is measured when the plan changes, so the total is complete
    /// before the visitor walks. A leg the router refused is counted as
    /// unreachable rather than omitted from the sum.
    @ViewBuilder private var header: some View {
        if let stop = navigator.activeStop {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(navigator.detourStop == nil ? stop.title : "\(stop.title) — on the way")
                        .lineLimit(1)
                    Text(remaining)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                planButton
            }
        } else if navigator.isFinished {
            HStack(spacing: 8) {
                Text("Your visit is done.")
                Spacer(minLength: 0)
                // Adding a stop to a finished journey makes it active again: the
                // library activates the new stop and draws its leg. The plan
                // button therefore stays visible after the last stop.
                planButton
                Button("Finish", action: onEnd)
            }
        } else {
            Text("Waiting for your wristband's first position.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var planButton: some View {
        Button { isShowingPlan = true } label: { Image(systemName: "list.bullet") }
            .accessibilityLabel("The plan")
    }

    private var remaining: String {
        let overview = navigator.overview
        var parts = [
            "\(overview.remainingStops.count) to go",
            "\(Int(overview.remainingMeters.rounded())) m",
            "\(max(1, Int((overview.etaSeconds / 60).rounded()))) min",
        ]
        // The library keeps a stop it cannot route to; the count is shown here.
        if !overview.unreachableStopIDs.isEmpty {
            parts.append("\(overview.unreachableStopIDs.count) unreachable")
        }
        return parts.joined(separator: " · ")
    }

    /// The visitor's two answers to a deviation. Both end a live detour first
    /// and clear the deviation. `resumeJourney()` routes to the stop the plan
    /// is on. `replanFromHere()` reorders the remaining stops from the
    /// visitor's position, applies the order and routes to its first stop.
    private func deviationPrompt(_ prompt: DeviationPrompt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt.message)
                .font(.subheadline)
            HStack(spacing: 16) {
                Button("Back to my route") {
                    self.prompt = nil
                    Task { await navigator.resumeJourney() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("New route from here") {
                    self.prompt = nil
                    Task { await navigator.replanFromHere() }
                }
                .font(.subheadline)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 16) {
            if navigator.hasArrived {
                // Arrival does not advance the journey: the advance rule is
                // `.manual`. This button calls `advance()`.
                Button("Continue") { Task { await navigator.advance() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            if navigator.detourStop == nil {
                detourMenu
                Button("Skip") { Task { await navigator.skip() } }
            } else {
                Button("Back to the plan") { Task { await navigator.cancelDetour() } }
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline)
    }

    /// `detour(to:)` inserts a stop before the active one and routes to it
    /// immediately. After the detour the plan resumes from the visitor's current
    /// position.
    @ViewBuilder private var detourMenu: some View {
        if !detours.isEmpty {
            Menu("Stop off") {
                ForEach(detours) { offer in
                    Button(offer.title) {
                        Task { await navigator.detour(to: JourneyStop(offer.poi)) }
                    }
                }
            }
        }
    }

    private struct Detour: Identifiable {
        let id: String
        let title: String
        let poi: VenuePOI
    }

    /// Builds the detour offers. The kinds of place come from the venue data
    /// (``VenuePOI/nearestByAmenity(in:from:)``). The name of each kind comes
    /// from the SDK amenity store: one local row per amenity id, read offline.
    /// An id the store cannot name is omitted. The app stores no titles of its own.
    private func offers() async -> [Detour] {
        guard let here = navigator.session.position else { return [] }
        var detours: [Detour] = []
        for (amenityID, poi) in VenuePOI.nearestByAmenity(in: places, from: ProximiioCoordinate(
            latitude: here.coordinate.latitude,
            longitude: here.coordinate.longitude
        )) {
            guard let title = await navigator.session.sdk.amenity(id: amenityID)?.title else { continue }
            detours.append(Detour(id: amenityID, title: title, poi: poi))
        }
        return detours.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

/// The prompt shown when the visitor has left the visit's route, and the rule
/// that opens and closes it.
///
/// Three `JourneyEvent`s open it: `farFromRoute`, `offRouteTooLong` and
/// `detourOverstayed`. `leftRoute` does not: a visitor a few metres off the
/// route is not asked. `returnedToRoute` and `journeyFinished` close it.
/// `detourEnded` closes a prompt opened by `detourOverstayed`. Other events
/// leave it as it is. Each event arrives once per episode.
struct DeviationPrompt: Equatable {
    enum Reason: Equatable {
        case farFromRoute
        case offRouteTooLong
        case detourOverstayed
    }

    let reason: Reason
    let message: String

    /// The prompt after `event`, given the prompt on screen. `nil` shows none.
    static func after(_ event: JourneyEvent, showing current: DeviationPrompt?) -> DeviationPrompt? {
        switch event {
        case .farFromRoute(let distance):
            DeviationPrompt(
                reason: .farFromRoute,
                message: "You are \(Int(distance.rounded())) m from your route."
            )
        case .offRouteTooLong(let duration):
            DeviationPrompt(
                reason: .offRouteTooLong,
                message: "You have been off your route for \(minutes(duration)) min."
            )
        case .detourOverstayed(let stop, let duration):
            DeviationPrompt(
                reason: .detourOverstayed,
                message: "You left your route for \(stop.title) \(minutes(duration)) min ago."
            )
        case .returnedToRoute, .journeyFinished:
            nil
        case .detourEnded:
            current?.reason == .detourOverstayed ? nil : current
        default:
            current
        }
    }

    /// Whole minutes, at least 1.
    private static func minutes(_ seconds: TimeInterval) -> Int {
        max(1, Int((seconds / 60).rounded()))
    }
}

/// The plan: the remaining stops in order, with reordering and adding.
struct JourneyPlanSheet: View {
    @ObservedObject var navigator: JourneyNavigator
    let places: [VenuePOI]
    let onEnd: () -> Void

    @State private var proposal: JourneyOrderProposal?
    @State private var showsWholePlan = false
    @State private var isAdding = false
    /// The places the last add could not insert. Replaced by the next add.
    @State private var note: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let proposal, proposal.isImprovement, navigator.canApply(proposal) {
                    Section {
                        Button("Save \(Int(proposal.savedMeters)) m by reordering") {
                            Task {
                                // `false`: the plan changed after the proposal was
                                // measured, and nothing was applied.
                                await navigator.apply(proposal)
                                self.proposal = nil
                            }
                        }
                    } footer: {
                        Text("Measured from where you are. Nothing moves until you tap it.")
                    }
                }

                if let note {
                    Section { Text(note).font(.caption).foregroundStyle(.secondary) }
                }

                Section("Still to walk") {
                    ForEach(navigator.reorderableStops) { stop in
                        row(stop)
                    }
                    .onMove(perform: move)
                }

                if !seen.isEmpty {
                    Section("Behind you") {
                        ForEach(seen) { stop in
                            row(stop)
                        }
                    }
                }

                Section {
                    // Off by default. When on, the remaining legs are drawn under
                    // the active leg (`journeyOverlayStyle = .venue`).
                    Toggle("Show the whole plan on the map", isOn: $showsWholePlan)
                    Button("End the visit", role: .destructive) {
                        dismiss()
                        onEnd()
                    }
                }
            }
            .navigationTitle("Your visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                        .disabled(places.isEmpty)
                        .accessibilityLabel("Add places")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            // The same search sheet used to plan the visit. `add` appends each pick
            // after the remaining stops and leaves the active leg unchanged. It
            // returns `false` for a stop the journey already holds; those are
            // listed in `note` rather than dropped.
            .sheet(isPresented: $isAdding) {
                POISearchSheet(pois: places, allowsMultiple: true, adds: true) { picked in
                    Task {
                        var already: [String] = []
                        for poi in picked {
                            if await navigator.add(JourneyStop(poi)) { continue }
                            already.append(poi.title)
                        }
                        note = already.isEmpty
                            ? nil
                            : "Already in your visit: \(already.joined(separator: ", "))."
                    }
                }
            }
            // `proposeOrder(from: .visitor)` measures the remaining stops from the
            // visitor's position, the stop being walked to included, and returns a
            // proposal. It does not apply it. Without a position it returns `nil`;
            // `.activeStop` then keeps the stop being walked to first and orders
            // the rest. `apply` refuses a proposal after the remaining stops or
            // their order change, or after the live stop changes, so the proposal
            // is measured again on each of those changes.
            .task(id: [navigator.activeStop?.id ?? ""] + navigator.reorderableStops.map(\.id)) {
                var measured = await navigator.proposeOrder(from: .visitor)
                if measured == nil { measured = await navigator.proposeOrder(from: .activeStop) }
                proposal = measured
            }
            .onChange(of: showsWholePlan) {
                navigator.session.journeyOverlayStyle = $1 ? .venue : nil
            }
        }
    }

    private var seen: [JourneyStop] {
        navigator.journey.stops.filter { $0.state == .done || $0.state == .skipped }
    }

    private func row(_ stop: JourneyStop) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.title)
                    .strikethrough(stop.state == .skipped)
                Text(label(for: stop))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func label(for stop: JourneyStop) -> String {
        if navigator.overview.unreachableStopIDs.contains(stop.id) { return "No route to this one" }
        return switch stop.state {
        case .active: "Walking there"
        case .reached: "You are here"
        case .done: "Seen"
        case .skipped: "Skipped"
        case .pending: stop.floor.map { "Level \(MapLevelFormat.trimmed($0))" } ?? "In the venue"
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let first = source.first else { return }
        let stops = navigator.reorderableStops
        guard first < stops.count else { return }
        // `onMove` passes the insertion index before the row is removed;
        // `move(stopID:toIndex:)` takes the final index.
        let index = destination > first ? destination - 1 : destination
        let stopID = stops[first].id
        Task { await navigator.move(stopID: stopID, toIndex: index) }
    }
}
