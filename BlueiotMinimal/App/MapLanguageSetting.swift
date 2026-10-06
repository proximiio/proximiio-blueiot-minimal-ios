//
//  MapLanguageSetting.swift
//  BlueiotMinimal
//
//  The "Map language" choice. It is in the system Settings app, under the
//  app's name, and is defined in Settings.bundle/Root.plist. It is for testing
//  the venue's translated titles; visitors keep Automatic.
//
//  The choice sets `MapOptions.language`: the language of the POI labels and
//  floor names on the map. The app's own place titles (search, the search row,
//  new visit stops) use the same language through `VenuePOI.all(in:language:)`.
//  A title without a translation in that language shows the default title.
//
//  Automatic, the default, stores an empty value and sets `language` to `nil`.
//  The map then uses `ProximiioLanguage.preferred`, the app's display
//  language. The app is localized in English only, so Automatic is `"en"`.
//
//  `VenueMapScreen` reads the choice when it creates the map session, and
//  again each time the app returns to the foreground. A visit already in
//  progress keeps the stop titles it was planned with.
//
import Foundation
import Proximiio
import ProximiioMap

enum MapLanguageSetting {
    /// The `UserDefaults` key. The same string is the `Key` of the
    /// multi-value item in Settings.bundle/Root.plist. Its `DefaultValue` is
    /// the empty string, Automatic.
    static let key = "mapLanguage"

    /// The `MapOptions.language` for the stored value: the language code, or
    /// `nil` for Automatic. An empty or blank value is Automatic.
    static func language(in defaults: UserDefaults = .standard) -> String? {
        guard let stored = defaults.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !stored.isEmpty
        else { return nil }
        return stored
    }

    /// The diagnostics log line for `options`: the language the map draws in,
    /// and whether it is the Automatic choice.
    static func summary(of options: MapOptions) -> String {
        "map language: \(options.resolvedLanguage)"
            + (options.language == nil ? " (automatic)" : "")
    }
}
