//
//  VenueConfiguration.swift
//  BlueiotMinimal
//
//  The whole of the app's configuration: three build-time values, injected through
//  Config/App.xcconfig (plus the untracked Config/Secrets.xcconfig) into Info.plist
//  and read here once. None of them is editable at runtime, because a visitor has no
//  business editing them and this app has no settings screen for staff to get lost in.
//
import Foundation

enum VenueConfiguration {
    /// Proximi.io application token — `PROXIMIIO_APPLICATION_TOKEN`.
    static let token = value("ProximiioApplicationToken")

    /// The cloud relay's address as typed — `BLUEIOT_CLOUD_RELAY_URL`. A bare host is
    /// fine. Kept as text so the SDK's `BlueiotCloudRelayEndpoint` does the one
    /// normalisation into `https://…` and `wss://…/stream`.
    static let relayHost = value("BlueiotCloudRelayURL")

    /// The relay's stream token, sent as `Authorization: Bearer` —
    /// `BLUEIOT_CLOUD_RELAY_TOKEN`. Without it the relay answers HTTP 401.
    static let relayToken = value("BlueiotCloudRelayToken")

    /// Which keys are still empty, in one sentence, or `nil` when none are.
    static var missing: String? {
        let keys = [
            ("PROXIMIIO_APPLICATION_TOKEN", token),
            ("BLUEIOT_CLOUD_RELAY_URL", relayHost),
            ("BLUEIOT_CLOUD_RELAY_TOKEN", relayToken),
        ].filter { $0.1 == nil }.map(\.0)
        guard !keys.isEmpty else { return nil }
        return "Set \(keys.joined(separator: ", ")) in Config/Secrets.xcconfig, then rebuild."
    }

    /// Thrown rather than crashing, so a fresh clone with no secrets file still runs
    /// and says what is missing.
    struct SetupIncomplete: LocalizedError {
        var errorDescription: String? {
            VenueConfiguration.missing ?? "Configuration is incomplete."
        }
    }

    /// An Info.plist string, or `nil` when the xcconfig left it empty.
    private static func value(_ key: String) -> String? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
