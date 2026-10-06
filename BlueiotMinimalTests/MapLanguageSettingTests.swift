//
//  MapLanguageSettingTests.swift
//  BlueiotMinimalTests
//
//  The "Map language" choice, the `MapOptions.language` it sets, and the
//  place titles the app shows in that language. Automatic stores an empty
//  value and must set `nil`, so the map uses `ProximiioLanguage.preferred`.
//  The app's own titles must use the map's language and fall back to the
//  default title, so the search and the map labels agree.
//
import XCTest
@testable import BlueiotMinimal
import Proximiio
import ProximiioMap

final class MapLanguageSettingTests: XCTestCase {

    /// An empty defaults domain per test, so the simulator's stored value does
    /// not affect the result.
    private func freshDefaults() throws -> UserDefaults {
        let suite = "MapLanguageSettingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    // MARK: - Setting

    func testUnsetIsAutomatic() throws {
        XCTAssertNil(MapLanguageSetting.language(in: try freshDefaults()))
    }

    func testEmptyValueIsAutomatic() throws {
        let defaults = try freshDefaults()
        defaults.set("", forKey: MapLanguageSetting.key)
        XCTAssertNil(MapLanguageSetting.language(in: defaults))
        defaults.set("  ", forKey: MapLanguageSetting.key)
        XCTAssertNil(MapLanguageSetting.language(in: defaults))
    }

    func testChosenLanguageSetsMapLanguage() throws {
        let defaults = try freshDefaults()
        defaults.set("ar", forKey: MapLanguageSetting.key)
        let language = MapLanguageSetting.language(in: defaults)
        XCTAssertEqual(language, "ar")
        XCTAssertEqual(MapOptions().with(language: language).resolvedLanguage, "ar")
    }

    /// Automatic leaves `language` `nil`; the map then draws in the app
    /// language.
    func testAutomaticResolvesToAppLanguage() {
        let options = MapOptions().with(language: nil)
        XCTAssertNil(options.language)
        XCTAssertEqual(options.resolvedLanguage, ProximiioLanguage.preferred)
        XCTAssertTrue(MapLanguageSetting.summary(of: options).hasSuffix("(automatic)"))
    }

    /// Settings.bundle is in the app, which hosts these tests. Its item must
    /// use the same key, default to Automatic and offer Automatic, English
    /// and Arabic.
    func testSettingsBundleOffersAutomaticEnglishArabic() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Root", withExtension: "plist", subdirectory: "Settings.bundle"))
        let root = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
        let specifiers = try XCTUnwrap(root["PreferenceSpecifiers"] as? [[String: Any]])
        let item = try XCTUnwrap(specifiers.first { $0["Key"] as? String == MapLanguageSetting.key })
        XCTAssertEqual(item["Type"] as? String, "PSMultiValueSpecifier")
        XCTAssertEqual(item["DefaultValue"] as? String, "")
        XCTAssertEqual(item["Titles"] as? [String], ["Automatic", "English", "Arabic"])
        XCTAssertEqual(item["Values"] as? [String], ["", "en", "ar"])
    }

    // MARK: - App titles

    private func poi(_ id: String, title: String, translations: [String: String]?) -> ProximiioFeature {
        var properties: [String: JSONValue] = [
            "type": .string("poi"),
            "title": .string(title),
            "level": .number(0),
        ]
        if let translations {
            properties["title_i18n"] = .object(translations.mapValues(JSONValue.string))
        }
        return ProximiioFeature(
            id: id,
            geometry: .init(type: "Point", coordinates: .array([.number(0), .number(0)])),
            properties: .object(properties)
        )
    }

    func testPlaceTitleUsesLanguage() {
        let places = VenuePOI.all(
            in: [poi("cafe", title: "Cafe", translations: ["en": "Cafe", "ar": "مقهى"])],
            language: "ar"
        )
        XCTAssertEqual(places.map(\.title), ["مقهى"])
    }

    /// A place without a translation in the language shows its `title`.
    func testPlaceTitleFallsBackToDefaultTitle() {
        let places = VenuePOI.all(
            in: [
                poi("cafe", title: "Cafe", translations: ["en": "Cafe"]),
                poi("shop", title: "Shop", translations: nil),
            ],
            language: "ar"
        )
        XCTAssertEqual(places.map(\.title), ["Cafe", "Shop"])
    }

    func testPlaceTitleInEnglish() {
        let places = VenuePOI.all(
            in: [poi("cafe", title: "Café", translations: ["en": "Cafe", "ar": "مقهى"])],
            language: "en"
        )
        XCTAssertEqual(places.map(\.title), ["Cafe"])
    }
}
