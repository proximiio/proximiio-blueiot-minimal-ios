//
//  VenueMapScreen.swift
//  BlueiotMinimal
//
//  Main screen: the venue map, place search, one route and the next instruction.
//
//  `ProximiioMapView` draws the venue style, the floors, the amenities, the
//  position marker and the route, split so the floor on screen shows its own
//  segment. This screen owns the picked place, the `computeRoute` call and the
//  `setRoute` hand-over. The recentre button calls the library's follow camera.
//  Turn-by-turn is enabled with one assignment (`guidanceRules`); only the
//  instruction text belongs to the app.
//
//  Product chrome goes in `bottomBar`. Product screens go beside this one.
//
import Proximiio
import ProximiioMap
import SwiftUI

struct VenueMapScreen: View {
    let venue: Venue
    /// The followed wristband id and the save callback for a new one. The sheet
    /// that changes it opens on the long press below and also lists the map credits.
    let wristband: String
    let onSaveWristband: (WristbandID) -> Void

    /// The map session is created here rather than by `ProximiioMapView(sdk:)`
    /// so this screen can call `setRoute` on it.
    @StateObject private var session: ProximiioMapSession

    @State private var places: [VenuePOI] = []
    @State private var destination: VenuePOI?
    @State private var note: String?
    @State private var isSearching = false
    /// The visit in progress, restored from disk on the first body evaluation.
    /// `nil` is single-destination mode: a search bar and one route.
    @State private var journey: Journey? = JourneyStore.load()
    @State private var isPlanningVisit = false
    @State private var isChangingWristband = false

    @MainActor
    init(venue: Venue, wristband: String, onSaveWristband: @escaping (WristbandID) -> Void) {
        self.venue = venue
        self.wristband = wristband
        self.onSaveWristband = onSaveWristband
        _session = StateObject(wrappedValue: ProximiioMapSession(
            sdk: venue.sdk,
            options: MapOptions(
                // The library's floor picker. The app has no other.
                floorSelector: .trailing,
                // Draws a route when one is set and clears it when none is.
                route: .automatic
            )
            // Removes the attribution ⓘ, the MapLibre logo and the compass. The
            // credits the ⓘ presented must then be shown by the app; the long-press
            // sheet lists them.
            .with(chrome: .bare)
        ))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ProximiioMapView(session: session)
                .ignoresSafeArea()
                // Changes the wristband without a settings screen: press and hold
                // the map for 1.5 s. `simultaneousGesture` keeps the map's own pan,
                // pinch and rotate. There is intentionally no visible control; a
                // visitor does not need it, and staff are told once.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 1.5)
                        .onEnded { _ in isChangingWristband = true }
                )

            if let journey {
                // The journey uses the same session as the map: one map, one
                // camera and one drawn route in either mode.
                JourneyBar(session: session, journey: journey, places: places, onEnd: endVisit)
            } else {
                bottomBar
            }
        }
        .task {
            // Enables turn-by-turn. The session then follows the route it draws
            // and publishes `guidance`: the next manoeuvre, the distance to it,
            // whether the visitor is off the route and whether they have arrived.
            // Guidance is off by default.
            session.guidanceRules = .venueWalk
            // A local cache read, not a download: `Venue.start` fetched the features.
            places = VenuePOI.all(in: await venue.sdk.features())
        }
        .sheet(isPresented: $isSearching) {
            POISearchSheet(pois: places) { picked in
                guard let place = picked.first else { return }
                Task { await route(to: place) }
            }
        }
        .sheet(isPresented: $isPlanningVisit) {
            // The same search sheet in multi-select. The tap order is the
            // journey order.
            POISearchSheet(pois: places, allowsMultiple: true) { picked in
                guard !picked.isEmpty else { return }
                session.clearRoute()
                destination = nil
                note = nil
                journey = Journey(stops: picked.map(JourneyStop.init))
            }
        }
        .sheet(isPresented: $isChangingWristband) {
            // `session.attributions` is read on each body evaluation, so the
            // sheet lists the credits of the loaded style.
            WristbandPrompt(
                current: wristband,
                credits: session.attributions,
                onCancel: { isChangingWristband = false },
                onSave: { isChangingWristband = false; onSaveWristband($0) }
            )
        }
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuidanceLine(guidance: session.guidance)
            searchRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(16)
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

            visitButton
            recentreButton
        }
    }

    /// Opens the multi-select search. Hidden while a visit is running;
    /// `JourneyBar` replaces this bar.
    private var visitButton: some View {
        Button { isPlanningVisit = true } label: { Image(systemName: "list.bullet") }
            .disabled(places.isEmpty)
            .accessibilityLabel("Plan a visit")
    }

    /// `JourneyNavigator.end()` clears the route, the journey overlay and
    /// `guidanceRules`, which a journey owns while it runs. Setting
    /// `guidanceRules` again restores the single-route guidance this screen had
    /// before the visit.
    private func endVisit() {
        journey = nil
        JourneyStore.save(nil)
        session.guidanceRules = .venueWalk
    }

    /// Recentres the map on the wristband.
    ///
    /// `ProximiioMapSession` owns the follow camera; `MapOptions.camera` defaults
    /// to `.follow`, so the map follows from the first fix. `recentre()` re-arms
    /// that camera and restores the zoom. `followMyFloor()` unpins the floor, so
    /// a tap while viewing another floor returns to the visitor's floor.
    ///
    /// Panning, pinching or rotating the map sets the camera to `.free`. The
    /// library detects the gesture and publishes the change through
    /// ``ProximiioMapSession/cameraMode``. This screen reads that value and adds
    /// no gesture handling of its own.
    ///
    /// Filled symbol while following, outline while free. Disabled while
    /// `session.position` is `nil`: no fix has arrived from the wristband or the
    /// relay, so there is nothing to centre on.
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

    /// Computes the route from the current wristband position to the picked
    /// place. The SDK computes it on-device from the downloaded route network;
    /// the map splits and draws it.
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
