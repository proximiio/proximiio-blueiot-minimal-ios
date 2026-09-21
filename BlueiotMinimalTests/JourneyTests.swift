//
//  JourneyTests.swift
//  BlueiotMinimalTests
//
//  Journey persistence and the amenity query. Both fail silently: a journey that
//  does not survive a launch is lost without an error, and an amenity query that
//  reads the venue data wrongly offers a wrong detour or none. The SwiftUI views
//  are not tested.
//
import XCTest
@testable import BlueiotMinimal
import Proximiio
import ProximiioMap

final class JourneyPersistenceTests: XCTestCase {

    /// A separate suite, so a test never writes the app's defaults.
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
            coordinate: MapCoordinate(latitude: 0, longitude: 0),
            floor: FloorKey(level: 1),
            poiID: id,
            kind: .planned,
            state: state
        )
    }

    /// The order and each stop's state are restored, so a visit resumes at the
    /// same stop after a relaunch.
    func testRoundTripKeepsOrderAndState() throws {
        let journey = Journey(stops: [
            stop("atrium", state: .done),
            stop("gallery", state: .skipped),
            stop("cafe", state: .active),
            stop("roof-terrace"),
        ])
        JourneyStore.save(journey, to: store)

        let restored = try XCTUnwrap(JourneyStore.load(from: store))
        XCTAssertEqual(restored, journey)
        XCTAssertEqual(restored.stops.map(\.id), ["atrium", "gallery", "cafe", "roof-terrace"])
        XCTAssertEqual(restored.stops.map(\.state), [.done, .skipped, .active, .pending])
        XCTAssertEqual(restored.stops[3].floor, FloorKey(level: 1))
        XCTAssertEqual(restored.stops[3].poiID, "roof-terrace")
    }

    func testNothingSavedIsNothingRestored() {
        XCTAssertNil(JourneyStore.load(from: store))
    }

    /// Ending a visit is the same call as saving one; the next launch must not
    /// resume it.
    func testEndingClears() {
        JourneyStore.save(Journey(stops: [stop("atrium")]), to: store)
        JourneyStore.save(nil, to: store)
        XCTAssertNil(JourneyStore.load(from: store))
    }

    /// A journey with no stops is stored as none, not restored as an empty bar.
    func testEmptyJourneyIsNotAVisit() {
        JourneyStore.save(Journey(stops: [stop("atrium")]), to: store)
        JourneyStore.save(Journey(stops: []), to: store)
        XCTAssertNil(JourneyStore.load(from: store))
    }

    /// A value another build wrote under the key is treated as no visit, not as
    /// a crash on launch.
    func testUnreadableValueIsNoVisit() {
        store.set(Data("not a journey".utf8), forKey: "BlueiotMinimal.journey")
        XCTAssertNil(JourneyStore.load(from: store))
    }
}

/// `VenuePOI.nearestByAmenity`: the kinds are read from the venue data, not from
/// a fixed category list.
final class AmenityQueryTests: XCTestCase {

    /// A POI as `Proximiio.features()` returns it. The coordinates are a fixture
    /// on the null meridian and the equator, not a venue: only the longitude
    /// varies, so a larger longitude is farther from `here`.
    private func poi(_ id: String, amenity: String?, longitude: Double) -> ProximiioFeature {
        var properties: [String: JSONValue] = [
            "type": .string("poi"),
            "title": .string(id),
            "level": .number(1),
        ]
        if let amenity { properties["amenity"] = .string(amenity) }
        return ProximiioFeature(
            id: id,
            geometry: .init(type: "Point", coordinates: .array([.number(longitude), .number(0)])),
            properties: .object(properties)
        )
    }

    private let here = ProximiioCoordinate(latitude: 0, longitude: 0)

    private func places(_ features: [ProximiioFeature]) -> [VenuePOI] {
        VenuePOI.all(in: features)
    }

    /// One result per kind, and it is the nearest, not the first in the array.
    func testNearestOfEachKind() {
        let pois = places([
            poi("far toilet", amenity: "sanitary:toilet", longitude: 0.0090),
            poi("near toilet", amenity: "sanitary:toilet", longitude: 0.0010),
            poi("cafe", amenity: "sustenance:cafe", longitude: 0.0050),
        ])
        let nearest = VenuePOI.nearestByAmenity(in: pois, from: here)

        XCTAssertEqual(nearest.count, 2)
        XCTAssertEqual(nearest["sanitary:toilet"]?.title, "near toilet")
        XCTAssertEqual(nearest["sustenance:cafe"]?.title, "cafe")
    }

    /// The kinds come from the data. A venue tagging only artworks offers
    /// artworks; a venue tagging nothing offers nothing.
    func testKindsComeFromTheDataNotFromUs() {
        let artworks = places([
            poi("Folded Light", amenity: "a1b2c3d4:artwork", longitude: 0.0020),
            poi("Paper Garden", amenity: "a1b2c3d4:artwork", longitude: 0.0040),
        ])
        XCTAssertEqual(Array(VenuePOI.nearestByAmenity(in: artworks, from: here).keys), ["a1b2c3d4:artwork"])

        let untagged = places([poi("a room", amenity: nil, longitude: 0.0020)])
        XCTAssertTrue(VenuePOI.nearestByAmenity(in: untagged, from: here).isEmpty)
        XCTAssertTrue(VenuePOI.nearestByAmenity(in: [], from: here).isEmpty)
    }

    /// An untagged place is searchable and routable; it is only excluded from
    /// the detour offers.
    func testUntaggedPlacesAreStillPlaces() {
        let pois = places([
            poi("a room", amenity: nil, longitude: 0.0020),
            poi("toilet", amenity: "sanitary:toilet", longitude: 0.0040),
        ])
        XCTAssertEqual(pois.count, 2)
        XCTAssertNil(pois.first { $0.title == "a room" }?.amenityID)
        XCTAssertEqual(VenuePOI.nearestByAmenity(in: pois, from: here).count, 1)
    }
}
