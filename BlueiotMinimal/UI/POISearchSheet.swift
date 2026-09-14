//
//  POISearchSheet.swift
//  BlueiotMinimal
//
//  Search the venue's places; pick one. The pick is the only thing that leaves here.
//
//  This is where a real product diverges first — categories, favourites, amenity
//  icons, "nearest toilet". All of it belongs in this file's place, and none of it
//  belongs in the SDK.
//
import ProximiioMap
import SwiftUI

struct POISearchSheet: View {
    let pois: [VenuePOI]
    let onPick: (VenuePOI) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(VenuePOI.matching(query, in: pois)) { poi in
                Button {
                    onPick(poi)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(poi.title)
                            .foregroundStyle(.primary)
                        // `MapLevelFormat` is the map library's — the same rendering
                        // its own floor picker uses, so "1" and "1.5" read the same
                        // in both places.
                        Text("Level \(MapLevelFormat.trimmed(poi.level))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search places")
            .navigationTitle("Where to?")
            .navigationBarTitleDisplayMode(.inline)
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
}
