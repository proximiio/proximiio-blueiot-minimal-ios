//
//  VenueMapScreen.swift
//  BlueiotMinimal
//
//  THE APP, ONCE IT KNOWS THE WRISTBAND: a venue map, a search, a route, and the
//  turn to take next.
//
//  Nothing here draws on the map. `ProximiioMapView` owns the venue style, the
//  floors, the amenities, the blue dot and — given a route — the drawing of it, split
//  so the floor on screen shows its own segment. What this screen owns is three
//  lines of app: which place the visitor picked, asking the SDK for a route to it,
//  and handing that route over. The recentre button is a fourth, and it is one call
//  into the library's own follow camera rather than a camera this app wrote.
//  Turn-by-turn is a fifth: one line opts in, and the only thing left to the app is
//  the English the instruction is said in.
//
//  Your product's chrome goes in `bottomBar`. Your product's screens go beside this
//  one.
//
import Proximiio
import ProximiioMap
import SwiftUI

struct VenueMapScreen: View {
    let venue: Venue
    /// Presented by `RootView`; see the long press below for why it exists.
    let onChangeWristband: () -> Void

    /// The map session, named here rather than left to `ProximiioMapView(sdk:)`,
    /// because naming it is what gives this screen something to call `setRoute` on.
    @StateObject private var session: ProximiioMapSession

    @State private var places: [VenuePOI] = []
    @State private var destination: VenuePOI?
    @State private var note: String?
    @State private var isSearching = false

    @MainActor
    init(venue: Venue, onChangeWristband: @escaping () -> Void) {
        self.venue = venue
        self.onChangeWristband = onChangeWristband
        _session = StateObject(wrappedValue: ProximiioMapSession(
            sdk: venue.sdk,
            options: MapOptions(
                // The library's own floor picker. This app has no other, so there is
                // no risk of two.
                floorSelector: .trailing,
                // Draw a route whenever one is set, and clear it when one is not.
                route: .automatic
            )
        ))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ProximiioMapView(session: session)
                .ignoresSafeArea()
                // Changing the wristband without a settings screen: press and hold
                // the map. `simultaneousGesture` so the map keeps its own pan, pinch
                // and rotate. Undiscoverable on purpose — a visitor is handed a band
                // and never needs this; staff are told about it once.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 1.5)
                        .onEnded { _ in onChangeWristband() }
                )

            bottomBar
        }
        .task {
            // One line turns turn-by-turn on, and the session follows the route it
            // is already drawing: which turn is next, how far is left to it, whether
            // the visitor has walked off it, whether they have arrived. Off by
            // default, so an app that does not want it writes nothing.
            session.guidanceRules = .venueWalk
            // A local cache read, not a download: `Venue.start` already fetched it.
            places = VenuePOI.all(in: await venue.sdk.features())
        }
        .sheet(isPresented: $isSearching) {
            POISearchSheet(pois: places) { place in
                Task { await route(to: place) }
            }
        }
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            guidanceLine
            searchRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(16)
    }

    /// Turn-by-turn, one instruction at a time.
    ///
    /// `session.guidance` is a single value republished on every fix, so this reads
    /// four of its properties and the view re-renders once. It is `nil` until the
    /// first position after a route is set, and setting a route clears it — which is
    /// why there is nothing here to reset.
    ///
    /// Off-route is a latched state the library reports and clears by itself on the
    /// first fix back inside the corridor. Saying so is the whole response this app
    /// has: a detector of its own would only disagree with the one already running,
    /// and re-routing a single route is a product decision rather than a default.
    @ViewBuilder private var guidanceLine: some View {
        if let guidance = session.guidance {
            Text(Self.line(for: guidance))
                .font(.subheadline)
                .lineLimit(1)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Button { isSearching = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(destination?.title ?? "Search places")
                            .lineLimit(1)
                        if let note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if destination != nil {
                Button {
                    destination = nil
                    note = nil
                    session.clearRoute()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear route")
            }

            recentreButton
        }
    }

    /// One sentence for one fix, in the order a walker needs them: arrival ends the
    /// walk, leaving the route interrupts it, and otherwise it is the turn in hand
    /// and the metres still to walk to it. `distanceToManoeuvreMeters` is the number
    /// that shrinks — `RouteManoeuvre.legMeters` is the planned length of the leg and
    /// never moves.
    private static func line(for guidance: RouteGuidance) -> String {
        if guidance.hasArrived { return "You have arrived." }
        if guidance.isOffRoute { return "You have left the route." }
        let metres = Int(guidance.distanceToManoeuvreMeters.rounded())
        return "\(instruction(for: guidance.manoeuvre?.kind)) · \(metres) m"
    }

    /// `RouteManoeuvre.Kind` carries no display strings, and neither does the SDK's
    /// `RouteInstruction.Kind` underneath it: a library that shipped English would be
    /// shipping the wrong language to most venues. These sentences are the app's, and
    /// this is the one function to reach `NSLocalizedString` into.
    private static func instruction(for kind: RouteManoeuvre.Kind?) -> String {
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

    /// "Show me where I am", and nothing else is needed to make it work.
    ///
    /// `ProximiioMapSession` owns the follow camera (`MapOptions.camera` defaults to
    /// `.follow`, so the map is already following when the first fix lands).
    /// `recentre()` re-arms that camera and eases the zoom back in;
    /// `followMyFloor()` unpins the storey, because a visitor who taps this while
    /// looking at another floor means "take me back", and taking them back to a
    /// storey they are not on would not.
    ///
    /// Panning, pinching or rotating the map drops the camera to `.free` on its own —
    /// the library watches for the hand and publishes the change through
    /// ``ProximiioMapSession/cameraMode``. This screen only reads that, and must not
    /// add gesture handling of its own.
    ///
    /// Filled symbol while following, outline while free. Disabled until there is a
    /// position at all: with the wristband silent or the relay down there is nowhere
    /// to centre on, and a button that looks live and does nothing is worse than one
    /// that says so.
    private var recentreButton: some View {
        Button {
            session.followMyFloor()
            session.recentre()
        } label: {
            Image(systemName: session.cameraMode == .free ? "location" : "location.fill")
        }
        .disabled(session.position == nil)
        .accessibilityLabel("Centre on me")
        .accessibilityAddTraits(session.cameraMode == .free ? [] : .isSelected)
    }

    /// The only wayfinding in the app: from wherever the wristband says the visitor
    /// is, to the place they picked. The SDK computes it on-device off the network it
    /// already downloaded; the map splits and draws it.
    private func route(to place: VenuePOI) async {
        destination = place
        guard let here = session.position else {
            note = "Waiting for your wristband's first position."
            session.clearRoute()
            return
        }
        do {
            let route = try await venue.sdk.computeRoute(
                from: ProximiioCoordinate(
                    latitude: here.coordinate.latitude,
                    longitude: here.coordinate.longitude
                ),
                fromLevel: here.floor?.level ?? 0,
                to: place.coordinate,
                toLevel: place.level
            )
            session.setRoute(route)
            note = nil
        } catch {
            session.clearRoute()
            note = "No route from here."
        }
    }
}
