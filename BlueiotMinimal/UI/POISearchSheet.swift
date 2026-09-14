//
//  POISearchSheet.swift
//  BlueiotMinimal
//
//  Search the venue's places; pick one, or pick several. The pick is the only thing
//  that leaves here.
//
//  There is one search in this app and this is it. "Where to?" and "plan my
//  afternoon" are the same list, the same matching and the same rows — only the row's
//  accessory and the way the sheet closes differ, which is a parameter rather than a
//  second screen.
//
//  This is where a real product diverges first — categories, favourites, amenity
//  icons, "nearest toilet". All of it belongs in this file's place, and none of it
//  belongs in the SDK.
//
import ProximiioMap
import SwiftUI

struct POISearchSheet: View {
    let pois: [VenuePOI]
    /// Several places instead of one, in the order they are tapped, because that
    /// order is the order the visitor walks.
    var allowsMultiple = false
    /// Adding to a visit that is already running rather than planning a new one.
    /// Same list, same multi-select, the words that screen needs.
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
                            // `MapLevelFormat` is the map library's — the same
                            // rendering its own floor picker uses, so "1" and "1.5"
                            // read the same in both places.
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

    /// Tapping a picked place again takes it back out, and the numbers close up.
    private func toggle(_ poi: VenuePOI) {
        if let stop = picked.firstIndex(of: poi) {
            picked.remove(at: stop)
        } else {
            picked.append(poi)
        }
    }
}
