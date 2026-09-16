//
//  WristbandPrompt.swift
//  BlueiotMinimal
//
//  Wristband prompt. Shown full-screen on the first run and as a sheet when the
//  id is changed; the same view in both cases, so there is no settings screen.
//  `VenueMapScreen` opens the sheet.
//
import ProximiioMap
import SwiftUI

struct WristbandPrompt: View {
    /// Initial text: empty on the first run, the current id when changing it.
    let current: String
    /// The credits of the loaded map style. The app hides the map's attribution ⓘ
    /// (`VenueMapScreen`), so they are listed here. Empty on the first run, before a map exists.
    let credits: [MapAttribution]
    /// `nil` on the first run; there is no previous screen.
    let onCancel: (() -> Void)?
    let onSave: (WristbandID) -> Void

    @State private var text: String

    init(
        current: String = "",
        credits: [MapAttribution] = [],
        onCancel: (() -> Void)? = nil,
        onSave: @escaping (WristbandID) -> Void
    ) {
        self.current = current
        self.credits = credits
        self.onCancel = onCancel
        self.onSave = onSave
        _text = State(initialValue: current)
    }

    private var parsed: WristbandID? { WristbandID(text: text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("1000045550", text: $text)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Wristband number")
                } footer: {
                    // The footer shows which tag the text parsed to. A validity error
                    // alone would not reveal a mistyped digit.
                    if let parsed {
                        Text("Following tag \(parsed.canonical) (\(parsed.hexadecimal)).")
                    } else {
                        Text("The number printed on your band.")
                    }
                }

                if let hint = VenueConfiguration.missing {
                    Section {
                        Text(hint).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                // Empty when the style declares no credits. MapLibre strips the leading
                // "©" from each credit; it is added back here.
                if !credits.isEmpty {
                    Section("Map credits") {
                        ForEach(credits, id: \.self) { credit in
                            if let url = credit.url {
                                Link("© " + credit.title, destination: url)
                            } else {
                                Text("© " + credit.title)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Your wristband")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { if let parsed { onSave(parsed) } }
                        .disabled(parsed == nil)
                }
            }
        }
    }
}
