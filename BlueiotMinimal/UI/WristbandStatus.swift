//
//  WristbandStatus.swift
//  BlueiotMinimal
//
//  The wristband session on the map: its state from `stateChanges()` and the
//  End visit action. `VenueMapScreen` shows it at the top of the map.
//
import Proximiio
import SwiftUI

struct WristbandStatus: View {
    @ObservedObject var session: WristbandSession

    @State private var confirmsEnd = false
    @State private var isEnding = false
    @State private var failure: String?

    var body: some View {
        if let status = WristbandCopy.status(of: session.state) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isOnline ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(status)
                    .font(.subheadline)
                Button("End visit") { confirmsEnd = true }
                    .font(.subheadline.weight(.semibold))
                    .disabled(isEnding)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .confirmationDialog("End your visit?", isPresented: $confirmsEnd, titleVisibility: .visible) {
                Button("End visit", role: .destructive, action: end)
            } message: {
                Text("This phone stops following the wristband.")
            }
            .alert("The visit was not ended", isPresented: .constant(failure != nil)) {
                Button("OK") { failure = nil }
            } message: {
                Text(failure ?? "")
            }
        }
    }

    /// Online with the band heard by the venue.
    private var isOnline: Bool {
        if case .active(_, .online, .ok) = session.state { return true }
        return false
    }

    /// Ends the session. On success the state becomes `.ended(.userEnded)` and
    /// `RootView` shows the wristband prompt.
    private func end() {
        isEnding = true
        Task {
            do {
                try await session.end()
            } catch {
                failure = WristbandCopy.message(for: error)
            }
            isEnding = false
        }
    }
}
