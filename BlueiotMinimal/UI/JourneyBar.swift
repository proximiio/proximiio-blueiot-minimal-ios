//
//  JourneyBar.swift
//  BlueiotMinimal
//
//  A VISIT: several places, in an order, one leg at a time.
//
//  `JourneyNavigator` owns the walking. It computes each leg from the visitor's live
//  position, draws and follows it through the same session the map is already using,
//  re-routes it when they wander, and measures what is left. None of that is here.
//
//  What is here is the visitor's side: which stop is in hand, how much of the visit
//  is left, and the handful of buttons that change the plan. The library never
//  reorders a visit on its own, and neither does this screen — it proposes, and a tap
//  applies.
//
import Proximiio
import ProximiioMap
import SwiftUI

struct JourneyBar: View {
    let places: [VenuePOI]
    /// Called when the visit is over, so the map screen can put its search bar back.
    let onEnd: () -> Void

    @StateObject private var navigator: JourneyNavigator
    /// The detours on offer, named. Rebuilt only when the set of nearest places
    /// changes; empty is survivable and shows no button.
    @State private var detours: [Detour] = []
    @State private var isShowingPlan = false

    @MainActor
    init(
        session: ProximiioMapSession,
        journey: Journey,
        places: [VenuePOI],
        onEnd: @escaping () -> Void
    ) {
        self.places = places
        self.onEnd = onEnd
        _navigator = StateObject(wrappedValue: JourneyNavigator(session: session, journey: journey))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            GuidanceLine(guidance: navigator.guidance)
            buttons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(16)
        .task {
            // Starting is one call. Nothing is drawn until the first fix, because the
            // leg is computed from where the visitor actually is.
            await navigator.start()
            // The one extra download in the app, and only for a visitor who started
            // a visit. Store-first: with a catalogue stored it reaches no network and
            // cannot throw, and failing it costs the detours and nothing else.
            _ = try? await navigator.session.sdk.amenities()
            detours = await offers()
        }
        .task(id: navigator.session.position?.coordinate) { detours = await offers() }
        .onDisappear { navigator.end() }
        // `Journey` is Codable and carries each stop's state, so this one line is the
        // whole of "the visit survived the app being closed".
        .onChange(of: navigator.journey) { JourneyStore.save($1) }
        .sheet(isPresented: $isShowingPlan) {
            JourneyPlanSheet(navigator: navigator, onEnd: onEnd)
        }
    }

    /// The stop in hand, and what is left of the visit.
    ///
    /// `overview` is measured as soon as the plan changes, so the total is a total
    /// rather than a number that fills in as the visitor walks — and a leg routing
    /// refused is named rather than quietly left out of the sum.
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
                Button { isShowingPlan = true } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("The plan")
            }
        } else if navigator.isFinished {
            HStack(spacing: 8) {
                Text("Your visit is done.")
                Spacer(minLength: 0)
                Button("Finish", action: onEnd)
            }
        } else {
            Text("Waiting for your wristband's first position.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var remaining: String {
        let overview = navigator.overview
        var parts = [
            "\(overview.remainingStops.count) to go",
            "\(Int(overview.remainingMeters.rounded())) m",
            "\(max(1, Int((overview.etaSeconds / 60).rounded()))) min",
        ]
        // The library never drops a stop it could not route to, so saying so is this
        // app's job rather than a silently shorter list.
        if !overview.unreachableStopIDs.isEmpty {
            parts.append("\(overview.unreachableStopIDs.count) unreachable")
        }
        return parts.joined(separator: " · ")
    }

    private var buttons: some View {
        HStack(spacing: 16) {
            if navigator.hasArrived {
                // The one thing a visit deliberately does not do by itself. A visitor
                // stands in front of an exhibit for a length of time nobody can
                // guess, so the rule is `.manual` and this is what moves them on.
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

    /// "Something else first." `detour(to:)` puts a stop in front of the one being
    /// walked to and routes there now; the plan resumes afterwards from wherever the
    /// visitor ends up, not from where they stepped out.
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

    /// WHICH kinds of place a venue has is the app's question —
    /// ``VenuePOI/nearestByAmenity(in:from:)`` reads them off the venue's own data.
    /// WHAT each kind is called is the SDK's: one stored row per amenity id, local
    /// and offline. An id the catalogue cannot name is left out rather than shown as
    /// a uuid, and this app keeps no titles of its own.
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

/// The plan itself: what is left, in what order, and the two ways to change it.
struct JourneyPlanSheet: View {
    @ObservedObject var navigator: JourneyNavigator
    let onEnd: () -> Void

    @State private var proposal: JourneyOrderProposal?
    @State private var showsWholePlan = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let proposal, proposal.isImprovement {
                    Section {
                        Button("Save \(Int(proposal.savedMeters)) m by reordering") {
                            Task {
                                await navigator.apply(proposal)
                                self.proposal = nil
                            }
                        }
                    } footer: {
                        Text("Measured, not applied. Nothing moves until you tap it, and the stop you are walking to stays where it is.")
                    }
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
                    // Opt in, and off by default: the leg in hand is what a visitor
                    // is walking, and the rest of the afternoon under it is a choice
                    // rather than a default.
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
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            // Measures every walk between the remaining stops and returns a value;
            // it never applies itself. Re-measured whenever those stops change,
            // because a proposal describes the order it was measured against and
            // `apply` ignores one that no longer does — a button that silently does
            // nothing is worse than no button.
            .task(id: navigator.reorderableStops.map(\.id)) {
                proposal = await navigator.proposeOrder()
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
        // `onMove` gives the insertion point in the list before the row is taken out;
        // `move(stopID:toIndex:)` wants the index it ends up at.
        let index = destination > first ? destination - 1 : destination
        let stopID = stops[first].id
        Task { await navigator.move(stopID: stopID, toIndex: index) }
    }
}
