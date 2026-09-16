//
//  POISearchSheet.swift
//  BlueiotMinimal
//
//  Search over the venue's places; picks one place or several. Only the pick
//  leaves this view.
//
//  The single-destination search and the visit planner share this sheet. The
//  list, the matching and the rows are the same; the row accessory and the
//  dismissal differ by parameter.
//
//  Product-specific search features (categories, favourites, amenity icons,
//  nearest amenity) belong in this file, not in the SDK.
//
import ProximiioMap
import SwiftUI

struct POISearchSheet: View {
    let pois: [VenuePOI]
    /// Picks several places in tap order. The tap order is the journey order.
    var allowsMultiple = false
    /// Adds to a running visit instead of planning a new one. Same list and
    /// multi-select; different title and button label.
    var adds = false
    let onPick: ([VenuePOI]) -> Void

    @State private var query = ""
    @State private var picked: [VenuePOI] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(VenuePOI.matching(query, in: pois)) { poi in
                Button {
                    guard allowsMultiple else {
                        onPick([poi])
                        dismiss()
                        return
                    }
                    toggle(poi)
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(poi.title)
                                .foregroundStyle(.primary)
                            // `MapLevelFormat` is the map library's level formatter, also
                            // used by its floor picker, so "1" and "1.5" render
                            // identically in both.
                            Text("Level \(MapLevelFormat.trimmed(poi.level))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let stop = picked.firstIndex(of: poi) {
                            Text("\(stop + 1)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(.rect)
                }
            }
            .searchable(text: $query, prompt: "Search places")
            .navigationTitle(allowsMultiple ? (adds ? "Add to your visit" : "Plan a visit") : "Where to?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsMultiple {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(adds ? "Add" : "Start") {
                            onPick(picked)
                            dismiss()
                        }
                        .disabled(picked.isEmpty)
                    }
                }
            }
            .overlay {
                if pois.isEmpty {
                    ContentUnavailableView(
                        "No places yet",
                        systemImage: "mappin.slash",
                        description: Text("The venue is still downloading.")
                    )
                }
            }
        }
    }

    /// Tapping a picked place again removes it; the later numbers shift down.
    private func toggle(_ poi: VenuePOI) {
        if let stop = picked.firstIndex(of: poi) {
            picked.remove(at: stop)
        } else {
            picked.append(poi)
        }
    }
}
