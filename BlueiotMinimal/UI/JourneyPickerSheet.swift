//
//  JourneyPickerSheet.swift
//  BlueiotMinimal
//
//  Debug builds only. The journey picker and the playback controls, in the
//  top-leading corner of the map. The picker lists the organisation's journeys
//  (`Proximiio.journeys()`) and plays one in place of the cloud relay; the
//  controls pause, resume and stop it. Stop attaches the relay again. The rules
//  are in JourneyPlayback.swift. Release and TestFlight builds do not contain
//  this code.
//
#if DEBUG
import Proximiio
import SwiftUI

/// The picker button, or the playback controls while a journey plays.
struct JourneyPlaybackOverlay: View {
    let venue: Venue
    @ObservedObject var playback: JourneyPlaybackController
    @State private var isPicking = false

    var body: some View {
        Group {
            if playback.session.showsControls {
                controls
            } else {
                Button { isPicking = true } label: {
                    Image(systemName: "figure.walk.motion")
                        .padding(10)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Play a journey")
            }
        }
        .padding(.leading, 16)
        .padding(.top, 8)
        .sheet(isPresented: $isPicking) {
            JourneyPickerSheet(sdk: venue.sdk) { journey, options in
                isPicking = false
                Task { await venue.playJourney(journey, options: options) }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(playback.session.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(playback.session.status)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if playback.session.canPause || playback.session.canResume {
                Button {
                    Task { await playback.togglePause() }
                } label: {
                    Image(systemName: playback.session.canPause ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(playback.session.canPause ? "Pause journey" : "Resume journey")
            }
            Button {
                Task { await venue.stopJourney() }
            } label: {
                Image(systemName: "stop.fill")
            }
            .accessibilityLabel("Stop journey")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 260, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        // Elapsed time and the finished state come from the provider's
        // diagnostics; the task ends with the controls.
        .task {
            while !Task.isCancelled {
                await playback.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// The organisation's journeys. A playable one opens the speed and loop
/// options; an unplayable one is disabled and shows its `validationFailure()`.
struct JourneyPickerSheet: View {
    let sdk: Proximiio
    let onPlay: (ProximiioJourney, JourneyPlaybackOptions) -> Void

    @State private var content = JourneyPickerContent.loading
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch content {
                case .loading:
                    ProgressView()
                case .empty:
                    ContentUnavailableView(
                        "No journeys",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text("The organisation has no journeys. Draw one in MapTap.")
                    )
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Cannot load journeys", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                case .loaded(let rows):
                    List(rows) { row in
                        NavigationLink(value: row.id) { label(for: row) }
                            .disabled(!row.isPlayable)
                    }
                    .navigationDestination(for: String.self) { id in
                        if let row = rows.first(where: { $0.id == id }) {
                            JourneyPlaybackOptionsView(row: row) { options in
                                onPlay(row.journey, options)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Play a journey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func label(for row: JourneyPickerRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
                .foregroundStyle(row.isPlayable ? .primary : .secondary)
            if let summary = row.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let failure = row.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func load() async {
        content = .loading
        do {
            content = .from(.success(try await sdk.journeys()))
        } catch {
            content = .from(.failure(error))
        }
    }
}

/// Speed and loop for one journey, and the Play button.
private struct JourneyPlaybackOptionsView: View {
    let row: JourneyPickerRow
    let onPlay: (JourneyPlaybackOptions) -> Void
    @State private var options = JourneyPlaybackOptions()

    var body: some View {
        Form {
            Section {
                if let summary = row.summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Speed") {
                Picker("Speed", selection: $options.speed) {
                    ForEach(JourneyPlaybackOptions.pickerSpeeds, id: \.self) { speed in
                        Text(JourneyFormat.speed(speed)).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Loop", isOn: $options.loops)
            }
            Section {
                Button("Play") { onPlay(options) }
            } footer: {
                Text("Replaces the cloud relay until Stop. Stop attaches the relay again.")
            }
        }
        .navigationTitle(row.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
