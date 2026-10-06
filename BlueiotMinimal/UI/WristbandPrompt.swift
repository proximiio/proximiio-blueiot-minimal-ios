//
//  WristbandPrompt.swift
//  BlueiotMinimal
//
//  Wristband prompt. Shown full-screen while no session is active, and as a
//  sheet to connect another band; the same view in both cases, so there is no
//  settings screen. `VenueMapScreen` opens the sheet.
//
//  Connect binds the typed label through `WristbandSession`. Before the bind it
//  asks for location when the relay-api needs the phone's location for a
//  take-over and iOS can still show the dialog.
//
import ProximiioMap
import SwiftUI

struct WristbandPrompt: View {
    @ObservedObject var session: WristbandSession
    /// Why the previous session ended, or `nil`.
    let notice: String?
    /// The credits of the loaded map style. The app hides the map's attribution ⓘ
    /// (`VenueMapScreen`), so they are listed here. Empty before a map exists.
    let credits: [MapAttribution]
    /// `nil` on the full-screen prompt; there is no previous screen.
    let onCancel: (() -> Void)?
    /// Called after a successful bind.
    let onConnected: () -> Void

    @State private var text: String
    @State private var pendingAsk: WristbandSession.LocationAsk?
    @State private var isConnecting = false
    @State private var failure: String?

    init(
        session: WristbandSession,
        notice: String? = nil,
        credits: [MapAttribution] = [],
        onCancel: (() -> Void)? = nil,
        onConnected: @escaping () -> Void = {}
    ) {
        self.session = session
        self.notice = notice
        self.credits = credits
        self.onCancel = onCancel
        self.onConnected = onConnected
        _text = State(initialValue: session.lastLabel)
    }

    private var label: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                if let notice {
                    Section {
                        Label(notice, systemImage: "info.circle")
                    }
                }

                Section {
                    TextField("1000045550", text: $text)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .submitLabel(.go)
                        .onSubmit(connect)
                        .disabled(isConnecting)
                } header: {
                    Text("Wristband number")
                } footer: {
                    if let pendingAsk {
                        Text(WristbandCopy.explanation(for: pendingAsk))
                    } else {
                        Text("The number printed on your band.")
                    }
                }

                if isConnecting {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Connecting…")
                        }
                    }
                } else if let failure {
                    Section {
                        Text(failure).foregroundStyle(.red)
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
                    Button("Connect", action: connect)
                        .disabled(label.isEmpty || isConnecting || session.binding == nil)
                }
            }
            // Reads `/v1/meta` (cached by the SDK) and the authorization, so the
            // footer names the dialog before Connect shows it.
            .task { pendingAsk = await session.locationAsk() }
        }
    }

    /// Asks for location when needed, then binds. A refused location does not
    /// stop the bind: a band at the reception desk binds without one.
    private func connect() {
        let label = label
        guard !label.isEmpty, !isConnecting else { return }
        isConnecting = true
        failure = nil
        Task {
            if let ask = await session.locationAsk() {
                await session.ask(ask)
            }
            pendingAsk = nil
            do {
                try await session.bind(label)
                isConnecting = false
                onConnected()
            } catch {
                isConnecting = false
                failure = WristbandCopy.message(for: error)
                pendingAsk = await session.locationAsk()
            }
        }
    }
}
