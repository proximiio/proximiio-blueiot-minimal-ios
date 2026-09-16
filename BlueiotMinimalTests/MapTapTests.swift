//
//  MapTapTests.swift
//  BlueiotMinimalTests
//
//  The resolution of a map tap to a place. `ProximiioMapSession.onFeatureTap`
//  reports the feature ids under the tap; `VenuePOI.place(under:in:)` selects
//  the place among them. A wrong resolution fails silently: the tap picks
//  nothing, and the map reads as one without tap selection. The gesture is not
//  tested.
//
import XCTest
@testable import BlueiotMinimal
import Proximiio

final class MapTapTests: XCTestCase {

    /// A point feature as `Proximiio.features()` returns it. A place has type
    /// `poi`; a level changer has its own type and is not a place.
    private func feature(_ id: String, type: String) -> ProximiioFeature {
        ProximiioFeature(
            id: id,
            geometry: .init(type: "Point", coordinates: .array([.number(17.1077), .number(48.1486)])),
            properties: .object(["type": .string(type), "title": .string(id), "level": .number(0)])
        )
    }

    /// The cafe and the toilet; the elevator is not a place.
    private var places: [VenuePOI] {
        VenuePOI.all(in: [
            feature("cafe", type: "poi"),
            feature("toilet", type: "poi"),
            feature("elevator-1", type: "elevator"),
        ])
    }

    /// A tap on a place's glyph selects that place.
    func testTapOnPlaceSelectsIt() {
        XCTAssertEqual(VenuePOI.place(under: ["cafe"], in: places)?.id, "cafe")
    }

    /// A tap on a feature that is not a place selects nothing.
    func testTapOnFeatureThatIsNotAPlaceSelectsNothing() {
        XCTAssertEqual(places.map(\.id), ["cafe", "toilet"])
        XCTAssertNil(VenuePOI.place(under: ["elevator-1"], in: places))
        XCTAssertNil(VenuePOI.place(under: ["not-in-the-venue"], in: places))
    }

    /// Several ids under one tap: the first id that is a place wins, after a
    /// level changer drawn above it. A glyph and its label report one id twice.
    func testFirstPlaceAmongSeveralIdentifiersWins() {
        XCTAssertEqual(
            VenuePOI.place(under: ["elevator-1", "toilet", "toilet"], in: places)?.id,
            "toilet"
        )
        XCTAssertEqual(VenuePOI.place(under: ["elevator-1", "toilet", "cafe"], in: places)?.id, "toilet")
    }

    /// A tap on no symbol reports no ids and selects nothing. Neither does a tap
    /// before the places are loaded.
    func testEmptyTapSelectsNothing() {
        XCTAssertNil(VenuePOI.place(under: [], in: places))
        XCTAssertNil(VenuePOI.place(under: ["cafe"], in: []))
    }
}
