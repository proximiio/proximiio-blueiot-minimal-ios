//
//  VenueConfiguration.swift
//  BlueiotMinimal
//
//  Build-time configuration: two credentials and the relay-api URL. They are set
//  in Config/App.xcconfig and the untracked Config/Secrets.xcconfig, written into
//  Info.plist and read here once. None of them is editable at runtime; the app
//  has no settings screen.
//
import Foundation
import Proximiio

enum VenueConfiguration {
    /// Proximi.io application token — `PROXIMIIO_APPLICATION_TOKEN`.
    static let token = value("ProximiioApplicationToken")

    /// The relay-api base URL as configured — `BLUEIOT_RELAY_URL`. Kept as text;
    /// `BlueiotCloudRelayEndpoint(text:)` parses it. A bare host becomes
    /// `https://…`.
    static let relayURL = value("BlueiotRelayURL")

    /// The relay-api app token — `BLUEIOT_RELAY_APP_TOKEN`. Sent as
    /// `Authorization: Bearer` to the relay-api.
    static let relayAppToken = value("BlueiotRelayAppToken")

    /// The two credentials, passed to the diagnostics recorder for redaction.
    static var secrets: [String] { [token, relayAppToken].compactMap { $0 } }

    /// The wristband binding configuration, or `nil` while the relay URL or the
    /// app token is missing or the URL does not parse.
    ///
    /// `runsInBackground: true` keeps the position stream open after the app
    /// leaves the screen. Without it the SDK pauses the provider on
    /// backgrounding, regardless of the process's own background permission.
    static var binding: BlueiotBindingConfiguration? {
        guard let relayURL, let relayAppToken,
              let endpoint = BlueiotCloudRelayEndpoint(text: relayURL)
        else { return nil }
        return BlueiotBindingConfiguration(relayURL: endpoint, appToken: relayAppToken, runsInBackground: true)
    }

    /// The empty or invalid keys in one sentence, or `nil` when all three are set
    /// and the URL parses.
    static var missing: String? {
        var keys = [
            ("PROXIMIIO_APPLICATION_TOKEN", token),
            ("BLUEIOT_RELAY_URL", relayURL),
            ("BLUEIOT_RELAY_APP_TOKEN", relayAppToken),
        ].filter { $0.1 == nil }.map(\.0)
        if let relayURL, BlueiotCloudRelayEndpoint(text: relayURL) == nil {
            keys.append("a valid BLUEIOT_RELAY_URL")
        }
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
