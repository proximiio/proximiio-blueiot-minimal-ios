//
//  FloorMappingTests.swift
//  BlueiotMinimalTests
//
//  `Venue.floorIDsByEngineNumber` and its two knobs. Worth testing for the same
//  reason `WristbandID` is: it fails silently. A wrong offset or a wrong anchor puts
//  the dot on a real floor of a real building, so there is no error to read — only a
//  visitor standing in the lobby watching a dot on the first floor of somewhere else.
//
//  The fixture below is this venue, as `Proximiio.floors()` returns it: nine places,
//  twelve floors, levels 0, 1 and 3.
//
import XCTest
@testable import BlueiotMinimal
import Proximiio

/// `@MainActor` only because `Venue` is: the two functions under test are pure and
/// touch nothing, but they inherit the class's isolation.
@MainActor
final class FloorMappingTests: XCTestCase {

    // MARK: - The venue

    /// The anchor: Department of Culture and Tourism, `GF` at level 0, `FF` at 1.
    private static let anchor = "dct"

    private static func floor(_ id: String, _ level: Double, place: String) -> ProximiioFloor {
        ProximiioFloor(id: id, name: id, placeId: place, level: level)
    }

    /// Deliberately NOT in anchor-first order: the anchor's storeys sit behind two
    /// other buildings' level 0, which is exactly the order that made the naive map
    /// pick the wrong building.
    private static let venue: [ProximiioFloor] = [
        floor("airbnb-ground", 0, place: "piestany-airbnb"),
        floor("mall-ground", 0, place: "dubai-hills"),
        floor("nest-first", 1, place: "nest"),
        floor("GF", 0, place: anchor),
        floor("FF", 1, place: anchor),
        floor("lake-ground", 0, place: "lake-view"),
        floor("lake-first", 1, place: "lake-view"),
        floor("305", 3, place: "guggenheim"),
    ]

    // MARK: - The offset

    /// This venue. The engine calls the ground floor 1, so every level shifts up one
    /// and the map reads `1→GF, 2→FF, 4→305` — the line the demo app logs at attach.
    func testVenueNumberedFromOne() {
        let map = Venue.floorIDsByEngineNumber(
            Self.venue,
            groundFloorNumber: 1,
            anchorPlaceID: Self.anchor
        )
        XCTAssertEqual(map["1"], "GF")
        XCTAssertEqual(map["2"], "FF")
        XCTAssertEqual(map["4"], "305")
        XCTAssertEqual(map.count, 3, "levels 0, 1 and 3 — three numbers, no more")
    }

    /// An engine that numbers storeys the way Proximi.io does. The offset is 0 and
    /// the map is the identity: the number on the wire *is* the level.
    func testVenueNumberedFromZero() {
        let map = Venue.floorIDsByEngineNumber(
            Self.venue,
            groundFloorNumber: 0,
            anchorPlaceID: Self.anchor
        )
        XCTAssertEqual(map["0"], "GF")
        XCTAssertEqual(map["1"], "FF")
        XCTAssertEqual(map["3"], "305")
    }

    /// A number the venue has no storey for is absent rather than guessed.
    ///
    /// With the ground floor at 1 there is no engine floor 0, and level 2 does not
    /// exist in this organisation at all. Both are misses, and a miss sends the
    /// provider to `defaultFloorID` — which is a better answer than a wrong floor id.
    func testLevelTheVenueLacksIsAbsent() {
        let map = Venue.floorIDsByEngineNumber(
            Self.venue,
            groundFloorNumber: 1,
            anchorPlaceID: Self.anchor
        )
        XCTAssertNil(map["0"], "a basement this organisation does not have")
        XCTAssertNil(map["3"], "level 2 — no storey, no key")
        XCTAssertNil(map["9"])
    }

    // MARK: - The anchor place

    /// The anchor wins every storey it has, whatever order the sync returned.
    ///
    /// Three buildings have a floor at level 1 here. Without the anchor the first one
    /// in the array wins, and in this fixture that is The NEST — a different building.
    func testAnchorWinsEveryStoreyItHas() {
        let map = Venue.floorIDsByEngineNumber(
            Self.venue,
            groundFloorNumber: 1,
            anchorPlaceID: Self.anchor
        )
        XCTAssertEqual(map["1"], "GF", "not airbnb-ground, which comes first in the array")
        XCTAssertEqual(map["2"], "FF", "not nest-first, which comes first in the array")
    }

    /// …and only the storeys it has. Level 3 belongs to no building but Guggenheim,
    /// and dropping it would leave a real engine floor unmapped.
    func testOtherPlacesFillTheNumbersTheAnchorLacks() {
        let map = Venue.floorIDsByEngineNumber(
            Self.venue,
            groundFloorNumber: 1,
            anchorPlaceID: Self.anchor
        )
        XCTAssertEqual(map["4"], "305")
    }

    /// The anchor is what makes the map stable. Re-order the sync and it does not
    /// move; take the anchor away and it does.
    func testAnchorMakesTheMapIndependentOfSyncOrder() {
        let forwards = Venue.floorIDsByEngineNumber(
            Self.venue,
            groundFloorNumber: 1,
            anchorPlaceID: Self.anchor
        )
        let backwards = Venue.floorIDsByEngineNumber(
            Self.venue.reversed(),
            groundFloorNumber: 1,
            anchorPlaceID: Self.anchor
        )
        XCTAssertEqual(forwards, backwards)
    }

    /// A single-building organisation leaves the place id empty: there is nothing to
    /// prefer, so the first floor at each level wins.
    func testNoAnchorFallsBackToFirstWins() {
        let single = [
            Self.floor("ground", 0, place: "only"),
            Self.floor("first", 1, place: "only"),
        ]
        let map = Venue.floorIDsByEngineNumber(single, groundFloorNumber: 1, anchorPlaceID: nil)
        XCTAssertEqual(map, ["1": "ground", "2": "first"])
    }

    // MARK: - The fallback floor

    /// `defaultFloorID` is the anchor's ground floor, not whichever level 0 came
    /// first — the same rule as the map, or an unmapped number lands in a different
    /// building from every mapped one.
    func testDefaultFloorIsTheAnchorsGround() {
        XCTAssertEqual(Venue.groundFloorID(Self.venue, anchorPlaceID: Self.anchor), "GF")
        XCTAssertEqual(
            Venue.groundFloorID(Self.venue, anchorPlaceID: nil),
            "airbnb-ground",
            "no anchor, so first-wins"
        )
    }

    /// An organisation whose anchor has no level 0 still gets an answer.
    func testDefaultFloorFallsBackWhenTheAnchorHasNoGround() {
        let upstairsOnly = [
            Self.floor("nest-first", 1, place: "nest"),
            Self.floor("lake-ground", 0, place: "lake-view"),
        ]
        XCTAssertEqual(Venue.groundFloorID(upstairsOnly, anchorPlaceID: "nest"), "lake-ground")
    }

    /// No floors synced yet: an empty map, not a crash and not a wrong default.
    func testNoFloorsYet() {
        XCTAssertTrue(
            Venue.floorIDsByEngineNumber([], groundFloorNumber: 1, anchorPlaceID: Self.anchor).isEmpty
        )
        XCTAssertNil(Venue.groundFloorID([], anchorPlaceID: Self.anchor))
    }
}
