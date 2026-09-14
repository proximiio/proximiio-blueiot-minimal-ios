//
//  VenueMapScreen.swift
//  BlueiotMinimal
//
//  THE APP, ONCE IT KNOWS THE WRISTBAND: a venue map, a search, and a route.
//
//  Nothing here draws on the map. `ProximiioMapView` owns the venue style, the
//  floors, the amenities, the blue dot and — given a route — the drawing of it, split
//  so the floor on screen shows its own segment. What this screen owns is three
//  lines of app: which place the visitor picked, asking the SDK for a route to it,
//  and handing that route over.
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(16)
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
