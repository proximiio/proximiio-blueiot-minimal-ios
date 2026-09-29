//
//  VenueConfiguration.swift
//  BlueiotMinimal
//
//  Build-time configuration: three credentials and one venue value. They are set
//  in Config/App.xcconfig and the untracked Config/Secrets.xcconfig, written into
//  Info.plist and read here once. None of them is editable at runtime; the app
//  has no settings screen.
//
import Foundation

enum VenueConfiguration {
    /// Proximi.io application token — `PROXIMIIO_APPLICATION_TOKEN`.
    static let token = value("ProximiioApplicationToken")

    /// The cloud relay address as configured — `BLUEIOT_CLOUD_RELAY_URL`. A bare
    /// host is accepted. Kept as text; the SDK's `BlueiotCloudRelayEndpoint`
    /// normalises it into `https://…` and `wss://…/stream`.
    static let relayHost = value("BlueiotCloudRelayURL")

    /// The relay stream token, sent as `Authorization: Bearer` —
    /// `BLUEIOT_CLOUD_RELAY_TOKEN`. Without it the relay answers HTTP 401.
    static let relayToken = value("BlueiotCloudRelayToken")

    /// The two credentials, passed to the diagnostics recorder for redaction.
    static var secrets: [String] { [token, relayToken].compactMap { $0 } }

    /// The floor number the venue's BlueIoT engine reports for the ground floor —
    /// `BLUEIOT_GROUND_FLOOR_NO`. Not a credential. Empty means 0 (no shift); a
    /// LocalSense engine requires 1. See ``Venue/follow(_:)``.
    static let groundFloorNumber = value("BlueiotGroundFloorNo").flatMap(Int.init) ?? 0

    /// The empty required keys in one sentence, or `nil` when all three are set.
    /// `BLUEIOT_GROUND_FLOOR_NO` has a default and is not checked.
    static var missing: String? {
        let keys = [
            ("PROXIMIIO_APPLICATION_TOKEN", token),
            ("BLUEIOT_CLOUD_RELAY_URL", relayHost),
            ("BLUEIOT_CLOUD_RELAY_TOKEN", relayToken),
        ].filter { $0.1 == nil }.map(\.0)
        guard !keys.isEmpty else { return nil }
        return "Set \(keys.joined(separator: ", ")) in Config/Secrets.xcconfig, then rebuild."
    }

    /// Thrown instead of crashing, so a clone without a secrets file runs and
    /// reports the missing keys.
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
