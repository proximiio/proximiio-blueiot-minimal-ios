//
//  WristbandID.swift
//  BlueiotMinimal
//
//  Parsing of the number printed on the wristband, and its storage. Both are
//  tested: an id parsed differently here and by the relay does not fail with an
//  error, it matches no tag and no position arrives.
//
import Foundation
import Proximiio

/// A BlueIoT wristband (tag) id after parsing.
struct WristbandID: Equatable {

    /// The id as a number. `UInt64` matches the protocol: the cloud relay
    /// carries `tagId` as a decimal `u64`.
    let value: UInt64

    /// Parses typed or pasted text into a tag id.
    ///
    /// The rule is the SDK's `BlueiotCloudRelayMessage.decimalTagID(_:)`, the
    /// same function the relay client matches incoming ids with. It is called
    /// rather than re-implemented so the app and the relay parse identically.
    ///
    /// A bare number is decimal: `1000045550` is the number printed on the band
    /// and shown by BlueIoT tooling. A `0x` prefix means hexadecimal, as does
    /// any letter A–F. The codec's 16-digit form (`0000000000001B59`) is also
    /// hexadecimal.
    ///
    /// Returns `nil` when the text contains no number.
    init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let value = UInt64(BlueiotCloudRelayMessage.decimalTagID(trimmed))
        else { return nil }
        self.value = value
    }

    /// The canonical spelling: decimal, the characters printed on the band. It is
    /// stored, displayed and passed to the relay configuration.
    var canonical: String { String(value) }

    /// The same tag in hexadecimal, shown under the text field.
    var hexadecimal: String { "0x" + String(value, radix: 16).uppercased() }

    /// Whether `text` parses to a wristband id; for inline field validation.
    static func isValid(_ text: String) -> Bool { WristbandID(text: text) != nil }
}

/// Storage of the wristband id between launches.
///
/// `UserDefaults`, not the Keychain: a tag id is printed on the band and is not
/// a secret.
enum WristbandStore {
    private static let key = "WristbandID"

    /// The stored id, re-parsed through ``WristbandID/init(text:)`` rather than
    /// used as stored. Any spelling an earlier build wrote parses to the same tag
    /// under the current rule.
    static func load(from defaults: UserDefaults = .standard) -> WristbandID? {
        defaults.string(forKey: key).flatMap(WristbandID.init(text:))
    }

    static func save(_ id: WristbandID, to defaults: UserDefaults = .standard) {
        defaults.set(id.canonical, forKey: key)
    }
}
