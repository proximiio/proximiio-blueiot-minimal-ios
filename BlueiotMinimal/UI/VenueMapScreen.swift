//
//  VenueMapScreen.swift
//  BlueiotMinimal
//
//  Main screen: the venue map, place search, one route and the next instruction.
//
//  `ProximiioMapView` draws the venue style, the floors, the amenities, the
//  position marker and the route, split so the floor on screen shows its own
//  segment. This screen owns the picked place, the `computeRoute` call and the
//  `setRoute` hand-over. A place is picked in the search sheet or by a tap on
//  the map. The recentre button calls the library's follow camera.
//  Turn-by-turn is enabled with one assignment (`guidanceRules`); only the
//  instruction text belongs to the app.
//
//  The wristband session's state and the End visit action are at the top
//  (`WristbandStatus`). Product chrome goes in `bottomBar`. Product screens go
//  beside this one.
//
import Proximiio
import ProximiioMap
import SwiftUI

struct VenueMapScreen: View {
    let venue: Venue
    /// The wristband session. The sheet that connects another band opens on the
    /// long press below and also lists the map credits.
    @ObservedObject var wristband: WristbandSession

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
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init(venue: Venue, wristband: WristbandSession) {
        self.venue = venue
        self.wristband = wristband
        var options = MapOptions(
            // The library's floor picker. The app has no other.
            floorSelector: .trailing,
            // Draws a route when one is set and clears it when none is.
            route: .automatic
        )
        // Removes the attribution ⓘ, the MapLibre logo and the compass. The
        // credits the ⓘ presented must then be shown by the app; the long-press
        // sheet lists them.
        .with(chrome: .bare)
        // Draws the route line: a gradient from the visitor to the
        // destination, and the walked part in faded blue. The values are
        // from the app design.
        .with(routeLineStyle: RouteLineStyle(
            remaining: .gradient(from: MapColor(hex: 0x3F69FF), to: MapColor(hex: 0xED3731)),
            remainingOpacity: 1,
            completedColor: MapColor(hex: 0x3F69FF),
            completedOpacity: 0.3,
            widthPoints: 6,
            cap: .round
        ))
        // The "Smooth position" switch in the Settings app
        // (PositionSmoothingSetting.swift). Off draws the dot exactly on each fix.
        options.position.smoothing = PositionSmoothingSetting.smoothing()
        _session = StateObject(wrappedValue: ProximiioMapSession(sdk: venue.sdk, options: options))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ProximiioMapView(session: session)
                .ignoresSafeArea()
                // Connects another wristband without a settings screen: press and hold
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
        .overlay(alignment: .top) {
            WristbandStatus(session: wristband)
                .padding(.top, 8)
        }
        #if DEBUG
        // Debug builds only: the journey picker and playback controls
        // (JourneyPickerSheet.swift). Top-leading is the one corner the map
        // leaves free: the floor picker is trailing, and the bottom belongs to
        // the search bar and `JourneyBar`.
        .overlay(alignment: .topLeading) {
            JourneyPlaybackOverlay(venue: venue, playback: venue.playback)
        }
        #endif
        .task {
            // Enables turn-by-turn. The session then follows the route it draws
            // and publishes `guidance`: the next manoeuvre, the distance to it,
            // whether the visitor is off the route and whether they have arrived.
            // Guidance is off by default.
            session.guidanceRules = .venueWalk
            // The session reports the feature ids under a tap on a POI glyph or
            // label, on the main thread. A tap does not release the follow camera;
            // only a pan, pinch or rotate does.
            session.onFeatureTap = { identifiers, _ in pickTapped(identifiers) }
            // A local cache read, not a download: `Venue.start` fetched the features.
            places = VenuePOI.all(in: await venue.sdk.features())
        }
        .task { recordSmoothing() }
        // The "Smooth position" switch is changed in the Settings app, so the
        // app is in the background at that time. The new value is applied when
        // the app becomes active again; a relaunch is not needed.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            applySmoothingSetting()
        }
        .sheet(isPresented: $isSearching) {
            POISearchSheet(pois: places) { picked in
                guard let place = picked.first else { return }
                Task { await route(to: place) }
            }
        }
        .sheet(isPresented: $isPlanningVisit) {
            // The same search sheet in multi-select. The tap order is the
            // journey order until `JourneyBar` starts the visit; it then applies
            // the shortest order from the visitor's position.
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
                session: wristband,
                credits: session.attributions,
                onCancel: { isChangingWristband = false },
                onConnected: { isChangingWristband = false }
            )
        }
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuidanceLine(guidance: session.guidance)
            rerouteButton
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

    /// Shown while the visitor is off the single route. The session reports
    /// `isOffRoute` and leaves the drawn route as it is; a tap computes a new
    /// route to the same place from the current position, as a new pick does.
    @ViewBuilder private var rerouteButton: some View {
        if let destination, GuidanceLine.offersReroute(for: session.guidance) {
            Button("New route from here") { Task { await route(to: destination) } }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .font(.subheadline)
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

    /// Applies the stored "Smooth position" value to the map session when it
    /// differs from the session's. Assigning `session.options` takes effect
    /// from the next frame and does not reload the style.
    private func applySmoothingSetting() {
        let smoothing = PositionSmoothingSetting.smoothing()
        guard session.options.position.smoothing != smoothing else { return }
        session.options.position.smoothing = smoothing
        recordSmoothing()
    }

    /// Writes the map smoothing in use to the diagnostics log, so a log from a
    /// test with the switch off shows that the dot was drawn without smoothing.
    private func recordSmoothing() {
        let isOn = session.options.position.smoothing != .none
        Proximiio.recordDiagnosticsEvent(.state, "position smoothing: \(isOn ? "on" : "off")")
    }

    /// Picks a tapped place through `route(to:)`, the call a search pick makes:
    /// same destination, route and search-row text. A tap that hits no place
    /// changes nothing and does not clear the current pick. A tap during a visit
    /// is ignored: the single-destination search is not shown then, and
    /// `JourneyNavigator` owns the route.
    private func pickTapped(_ identifiers: [String]) {
        guard journey == nil,
              let place = VenuePOI.place(under: identifiers, in: places)
        else { return }
        Task { await route(to: place) }
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
