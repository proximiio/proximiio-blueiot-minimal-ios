//
//  JourneyTests.swift
//  BlueiotMinimalTests
//
//  The two pieces of the visit that fail silently.
//
//  A journey that does not survive a launch loses a visitor's afternoon without
//  anything on screen going wrong, and an amenity query that reads the venue's data
//  the wrong way offers a detour to nowhere — or, worse, offers nothing and looks
//  like a venue with no toilets. Neither shows up in a screenshot. The SwiftUI around
//  them is not tested, because a layout that is wrong is a layout you can see.
//
import XCTest
@testable import BlueiotMinimal
import Proximiio
import ProximiioMap

final class JourneyPersistenceTests: XCTestCase {

    /// A suite of its own, so a test never writes into the real app's defaults.
    private var store: UserDefaults!
    private let suite = "BlueiotMinimalTests.journey"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suite)
        store = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        store = nil
        super.tearDown()
    }

    private func stop(_ id: String, state: JourneyStop.State = .pending) -> JourneyStop {
        JourneyStop(
            id: id,
            title: id.capitalized,
            coordinate: MapCoordinate(latitude: 48.1486, longitude: 17.1077),
            floor: FloorKey(level: 1),
            poiID: id,
            kind: .planned,
            state: state
        )
    }

    /// The whole point: the order AND each stop's state come back, so a visitor who
    /// closed the app in the second gallery re-opens it in the second gallery rather
    /// than at the front door.
    func testRoundTripKeepsOrderAndState() throws {
        let journey = Journey(stops: [
            stop("atrium", state: .done),
            stop("zigzag", state: .skipped),
            stop("capsules", state: .active),
            stop("dividing-line"),
        ])
        JourneyStore.save(journey, to: store)

        let restored = try XCTUnwrap(JourneyStore.load(from: store))
        XCTAssertEqual(restored, journey)
        XCTAssertEqual(restored.stops.map(\.id), ["atrium", "zigzag", "capsules", "dividing-line"])
        XCTAssertEqual(restored.stops.map(\.state), [.done, .skipped, .active, .pending])
        XCTAssertEqual(restored.stops[3].floor, FloorKey(level: 1))
        XCTAssertEqual(restored.stops[3].poiID, "dividing-line")
    }

    func testNothingSavedIsNothingRestored() {
        XCTAssertNil(JourneyStore.load(from: store))
    }

    /// Ending a visit is the same call as saving one, so the next launch must not
    /// resume the afternoon the visitor just finished.
    func testEndingClears() {
        JourneyStore.save(Journey(stops: [stop("atrium")]), to: store)
        JourneyStore.save(nil, to: store)
        XCTAssertNil(JourneyStore.load(from: store))
    }

    /// An empty journey is not a journey. Saving one clears rather than restoring a
    /// bar with nothing in it.
    func testEmptyJourneyIsNotAVisit() {
        JourneyStore.save(Journey(stops: [stop("atrium")]), to: store)
        JourneyStore.save(Journey(stops: []), to: store)
        XCTAssertNil(JourneyStore.load(from: store))
    }

    /// Something else wrote to the key — an older build, a different shape. Treated
    /// as "no visit", never as a crash on launch.
    func testUnreadableValueIsNoVisit() {
        store.set(Data("not a journey".utf8), forKey: "BlueiotMinimal.journey")
        XCTAssertNil(JourneyStore.load(from: store))
    }
}

/// `VenuePOI.nearestByAmenity` — "find me a toilet", answered off the venue's own
/// data rather than off a list of categories somebody assumed.
final class AmenityQueryTests: XCTestCase {

    /// A POI as `Proximiio.features()` returns one. Longitudes only, at this
    /// latitude roughly 74 km per degree, so "further east" is "further away".
    private func poi(_ id: String, amenity: String?, longitude: Double) -> ProximiioFeature {
        var properties: [String: JSONValue] = [
            "type": .string("poi"),
            "title": .string(id),
            "level": .number(1),
        ]
        if let amenity { properties["amenity"] = .string(amenity) }
        return ProximiioFeature(
            id: id,
            geometry: .init(type: "Point", coordinates: .array([.number(longitude), .number(48.1486)])),
            properties: .object(properties)
        )
    }

    private let here = ProximiioCoordinate(latitude: 48.1486, longitude: 17.1000)

    private func places(_ features: [ProximiioFeature]) -> [VenuePOI] {
        VenuePOI.all(in: features)
    }

    /// One answer per kind, and it is the nearest one of that kind — not the first in
    /// the array, which is the mistake that looks right in a venue with one toilet.
    func testNearestOfEachKind() {
        let pois = places([
            poi("far toilet", amenity: "sanitary:toilet", longitude: 17.1090),
            poi("near toilet", amenity: "sanitary:toilet", longitude: 17.1010),
            poi("cafe", amenity: "sustenance:cafe", longitude: 17.1050),
        ])
        let nearest = VenuePOI.nearestByAmenity(in: pois, from: here)

        XCTAssertEqual(nearest.count, 2)
        XCTAssertEqual(nearest["sanitary:toilet"]?.title, "near toilet")
        XCTAssertEqual(nearest["sustenance:cafe"]?.title, "cafe")
    }

    /// A venue tags what it tags. Nothing here knows the word "toilet", so a venue
    /// whose POIs are all artworks offers artworks and a venue that tags nothing
    /// offers nothing — which is the honest answer, not an empty hard-coded list.
    func testKindsComeFromTheDataNotFromUs() {
        let artworks = places([
            poi("ZigZag Over Time", amenity: "bcdbffc2:artwork", longitude: 17.1020),
            poi("Time Capsules", amenity: "bcdbffc2:artwork", longitude: 17.1040),
        ])
        XCTAssertEqual(Array(VenuePOI.nearestByAmenity(in: artworks, from: here).keys), ["bcdbffc2:artwork"])

        let untagged = places([poi("a room", amenity: nil, longitude: 17.1020)])
        XCTAssertTrue(VenuePOI.nearestByAmenity(in: untagged, from: here).isEmpty)
        XCTAssertTrue(VenuePOI.nearestByAmenity(in: [], from: here).isEmpty)
    }

    /// An untagged place is still searchable and still routable — it is only not a
    /// detour offer.
    func testUntaggedPlacesAreStillPlaces() {
        let pois = places([
            poi("a room", amenity: nil, longitude: 17.1020),
            poi("toilet", amenity: "sanitary:toilet", longitude: 17.1040),
        ])
        XCTAssertEqual(pois.count, 2)
        XCTAssertNil(pois.first { $0.title == "a room" }?.amenityID)
        XCTAssertEqual(VenuePOI.nearestByAmenity(in: pois, from: here).count, 1)
    }
}
