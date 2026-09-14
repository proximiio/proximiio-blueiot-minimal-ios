//
//  WristbandID.swift
//  BlueiotMinimal
//
//  One spelling rule for the number printed on the band, and the one place it is
//  stored. Both are tiny, and both are tested, because a wristband id that is read
//  one way here and another way by the relay does not fail loudly — it just matches
//  nothing, and the dot never arrives.
//
import Foundation
import Proximiio

/// A Blueiot wristband (tag) id, once it is known to be one.
struct WristbandID: Equatable {

    /// The id as a number. `UInt64` because that is the width of the protocol: the
    /// cloud relay carries `tagId` as a decimal `u64`.
    let value: UInt64

    /// Reads whatever a person typed — or pasted out of a vendor screen — into the
    /// one tag it names.
    ///
    /// The rule is the SDK's own, `BlueiotCloudRelayMessage.decimalTagID(_:)`, which
    /// is the same function the relay client matches incoming ids with. Called rather
    /// than re-implemented, so this app cannot read an id differently from the relay
    /// that serves it.
    ///
    /// **A bare number is decimal.** That is what is printed on the band and what
    /// Blueiot's own tooling shows: `1000045550` is one thousand million and change,
    /// not a hex string that happens to have no letters in it. An explicit `0x` says
    /// hex, an id with letters in it is hex because it cannot be anything else, and
    /// the codec's 16-digit rendering (`0000000000001B59`) is hex too.
    ///
    /// `nil` only when the text names no number at all.
    init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let value = UInt64(BlueiotCloudRelayMessage.decimalTagID(trimmed))
        else { return nil }
        self.value = value
    }

    /// The canonical spelling: **decimal**, the same characters printed on the band.
    /// This is what is stored, what is shown back, and what the relay is configured
    /// with.
    var canonical: String { String(value) }

    /// The same tag on the wire, for the echo under the text field.
    var hexadecimal: String { "0x" + String(value, radix: 16).uppercased() }

    /// Whether `text` names a wristband at all — for a text field's inline validation.
    static func isValid(_ text: String) -> Bool { WristbandID(text: text) != nil }
}

/// Where the wristband id lives between launches.
///
/// `UserDefaults`, not the Keychain: a tag id is not a secret, it is printed in large
/// type on the band in the visitor's hand.
enum WristbandStore {
    private static let key = "WristbandID"

    /// The stored id, re-read through ``WristbandID/init(text:)`` rather than trusted
    /// as characters. That round trip is what lets the stored spelling change without
    /// moving anybody's band: any spelling an earlier build wrote still names the same
    /// tag under today's rule.
    static func load(from defaults: UserDefaults = .standard) -> WristbandID? {
        defaults.string(forKey: key).flatMap(WristbandID.init(text:))
    }

    static func save(_ id: WristbandID, to defaults: UserDefaults = .standard) {
        defaults.set(id.canonical, forKey: key)
    }
}
