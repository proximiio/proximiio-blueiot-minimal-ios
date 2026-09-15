//
//  WristbandPrompt.swift
//  BlueiotMinimal
//
//  The one thing this app ever asks a person for.
//
//  It is shown full-screen on first run and as a sheet when somebody changes the
//  band — the same view either way, which is why there is no settings screen. See
//  `VenueMapScreen` for how the sheet is reached.
//
import ProximiioMap
import SwiftUI

struct WristbandPrompt: View {
    /// What is in the field when it opens: empty on first run, the current id when
    /// somebody is changing it.
    let current: String
    /// What the map would have shown behind its attribution ⓘ, which this app hides
    /// (`VenueMapScreen`): the loaded style's credits. Empty on first run — no map yet.
    let credits: [MapAttribution]
    /// `nil` on first run — there is nothing to go back to.
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
                    // The echo is the safety net, not the validator: "that is not an
                    // id" cannot tell you *which* tag was understood, and that is the
                    // question somebody who mistyped a digit actually has.
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

                // Nothing when the style declares nothing. MapLibre strips the leading
                // "©" from each credit on the way in; it goes back on here.
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
