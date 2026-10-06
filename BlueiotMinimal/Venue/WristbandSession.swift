//
//  WristbandSession.swift
//  BlueiotMinimal
//
//  The visitor's wristband session, held by the SDK's `BlueiotWristbandBinding`.
//
//  The binding client stores the session in the Keychain and confirms it with
//  the relay-api at launch (`restore()`). The app stores no wristband id of its
//  own: the binding state is the only record of which band this phone follows.
//  A bind of a band another phone follows is a take-over; the relay-api decides
//  whether it is allowed and the other phone's session ends with `.superseded`.
//
//  The SDK never asks for location permission. When the relay-api needs the
//  phone's location for a take-over, `locationReadiness()` says so and
//  `LocationAccess` asks before the bind.
//
import CoreLocation
import Foundation
import Proximiio

@MainActor
final class WristbandSession: ObservableObject {

    /// What the app asks for before a bind.
    enum LocationAsk: Equatable {
        /// "While Using the App" authorization. Asked only while it is undetermined.
        case permission
        /// Temporary full accuracy, when the visitor allowed approximate location only.
        case preciseLocation
    }

    /// The binding client, or `nil` while `VenueConfiguration.binding` is
    /// incomplete. Created once per process.
    let binding: BlueiotWristbandBinding?

    /// The latest binding state. `nil` until the first value arrives from
    /// `stateChanges()`.
    @Published private(set) var state: BlueiotBindingState?

    /// `true` while a session is active. A bind in progress does not change it,
    /// so the map stays on screen while another band is connected from the sheet.
    @Published private(set) var isFollowing = false

    /// The label of the last successful bind in this process. Fills the prompt's
    /// field after a session ends. Not stored.
    private(set) var lastLabel = ""

    private let location = LocationAccess()

    init(configuration: BlueiotBindingConfiguration? = VenueConfiguration.binding) {
        binding = configuration.map(BlueiotWristbandBinding.init(configuration:))
        if binding == nil { state = .unbound }
    }

    /// The notice for an ended session, or `nil` while none has ended.
    var endNotice: String? {
        if case .ended(let reason) = state { return WristbandCopy.notice(for: reason) }
        return nil
    }

    /// Follows the binding state and confirms a stored session with the
    /// relay-api. Call once at launch; returns when the calling task is
    /// cancelled.
    func run() async {
        guard let binding else { return }
        Task { await binding.restore() }
        for await state in binding.stateChanges() {
            apply(state)
        }
    }

    /// What to ask for before a bind, or `nil` when nothing can or needs to be
    /// asked. A denied permission returns `nil`: iOS shows no second dialog, and
    /// the bind is sent without a location.
    func locationAsk() async -> LocationAsk? {
        guard let binding else { return nil }
        switch await binding.locationReadiness() {
        case .permissionNeeded: return location.canAskForPermission ? .permission : nil
        case .preciseLocationNeeded: return .preciseLocation
        case .ready, .notRequired: return nil
        @unknown default: return nil
        }
    }

    /// Shows the iOS dialog for `ask` and returns when it is answered.
    func ask(_ ask: LocationAsk) async {
        switch ask {
        case .permission: await location.requestWhenInUse()
        case .preciseLocation: await location.requestFullAccuracy()
        }
    }

    /// Binds this phone to the band with `label`, as typed. The relay-api
    /// resolves every label format. The new session replaces any current one.
    ///
    /// - Throws: `BlueiotBindingError`, or `VenueConfiguration.SetupIncomplete`
    ///   without a binding configuration.
    func bind(_ label: String) async throws {
        guard let binding else { throw VenueConfiguration.SetupIncomplete() }
        try await binding.bind(tagID: label)
        lastLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ends the visit. The state becomes `.ended(.userEnded)`.
    /// - Throws: `BlueiotBindingError` when the relay-api cannot be reached; the
    ///   session is kept.
    func end() async throws {
        try await binding?.end()
    }

    private func apply(_ state: BlueiotBindingState) {
        self.state = state
        switch state {
        case .active: isFollowing = true
        case .unbound, .ended: isFollowing = false
        case .binding: break
        @unknown default: isFollowing = false
        }
        Proximiio.recordDiagnosticsEvent(.state, "wristband: \(WristbandCopy.logLine(for: state))")
    }
}

/// The two location dialogs a bind can need. CoreLocation reports the answer to
/// a delegate; this class turns it into an `await`.
@MainActor
final class LocationAccess: NSObject, CLLocationManagerDelegate {

    /// The key in `NSLocationTemporaryUsageDescriptionDictionary` (`project.yml`).
    static let purposeKey = "WristbandTakeover"

    private let manager = CLLocationManager()
    private var answer: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    /// `true` while authorization is undetermined: iOS shows its dialog once.
    var canAskForPermission: Bool { manager.authorizationStatus == .notDetermined }

    /// Asks for "While Using the App" and returns when the visitor answers.
    func requestWhenInUse() async {
        guard canAskForPermission, answer == nil else { return }
        await withCheckedContinuation { continuation in
            answer = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Asks for full accuracy until the app leaves the foreground. Returns at
    /// once when full accuracy is already granted.
    func requestFullAccuracy() async {
        guard manager.accuracyAuthorization == .reducedAccuracy else { return }
        try? await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.purposeKey)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.resumeIfAnswered() }
    }

    private func resumeIfAnswered() {
        guard manager.authorizationStatus != .notDetermined, let answer else { return }
        self.answer = nil
        answer.resume()
    }
}
