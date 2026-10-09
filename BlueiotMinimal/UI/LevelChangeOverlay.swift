//
//  LevelChangeOverlay.swift
//  BlueiotMinimal
//
//  The level change card over the map (`levelChangeCard(session:sdk:)`).
//
//  - During a lift ride (`LiftDetector`): "Going to level X" with an up or
//    down arrow when the route's next manoeuvre is a level change from this
//    floor, "In the lift" without one.
//  - On a floor change (`LevelChangeDetector`): "Level X". The map moves to
//    the visitor's floor (`followMyFloor()`), and the card closes after 2.8 s.
//
//  A tap closes the card.
//
import Proximiio
import ProximiioMap
import SwiftUI

extension View {
    /// Shows the level change card while the visitor rides a lift and when the
    /// session's position changes floor, and moves the map to the visitor's
    /// floor on the change.
    func levelChangeCard(session: ProximiioMapSession, sdk: Proximiio) -> some View {
        modifier(LevelChangeModifier(session: session, sdk: sdk))
    }
}

private struct LevelChangeModifier: ViewModifier {
    let session: ProximiioMapSession
    let sdk: Proximiio
    @State private var floors = LevelChangeDetector()
    @State private var lift = LiftDetector()
    @State private var lifts: [LiftArea] = []
    @State private var card: LevelChangeCard?

    func body(content: Content) -> some View {
        content
            // A local read: `Venue.start` loaded the features.
            .task { lifts = LiftArea.all(features: await sdk.features()) }
            .onReceive(session.$position) { position in
                if let position { update(with: position) }
            }
            .overlay {
                if let card {
                    LevelChangeCardView(card: card)
                        .onTapGesture { self.card = nil }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: card)
    }

    private func update(with position: VenuePosition) {
        let event = lift.update(inLift: lifts.contains { $0.contains(position.coordinate) }, at: .now)
        if let change = floors.update(level: position.floor?.level) {
            arrive(change)
            return
        }
        switch event {
        case .boarded:
            guard let from = floors.level else { return }
            card = LevelChangeCard(phase: .riding, from: from, to: routeTarget(from: from))
        case .left:
            if card?.phase == .riding { card = nil }
        case nil:
            break
        }
    }

    /// The target floor of the route's next manoeuvre when it is a level
    /// change from `from`.
    private func routeTarget(from: Int) -> Int? {
        guard case .levelChange(let change)? = session.guidance?.manoeuvre?.kind,
              Int(change.fromLevel.rounded()) == from
        else { return nil }
        return Int(change.toLevel.rounded())
    }

    private func arrive(_ change: LevelChange) {
        let arrived = LevelChangeCard(phase: .arrived, from: change.from, to: change.to)
        card = arrived
        session.followMyFloor()
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            if card == arrived { card = nil }
        }
    }
}

private struct LevelChangeCardView: View {
    let card: LevelChangeCard

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: card.symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color(red: 0x3F / 255, green: 0x69 / 255, blue: 1))
            Text(card.title)
                .font(.title2.bold())
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Closes the level change")
    }
}
