//
//  JourneyPickerTests.swift
//  BlueiotMinimalTests
//
//  Debug builds only, as the code under test. The journey picker's rows and
//  list states, the playback session state, and the launch arguments. A wrong
//  rule offers an unplayable journey, hides the reason a journey cannot play,
//  or leaves the playback controls in a state the provider is not in.
//
#if DEBUG
import XCTest
@testable import BlueiotMinimal
import Proximiio

final class JourneyPickerTests: XCTestCase {

    /// 111 m north, from level 0 to level 1, at 1 m/s.
    private let playable = ProximiioJourney(
        id: "org:one",
        name: "  Lobby to café  ",
        speed: 1,
        waypoints: [
            .init(latitude: 0, longitude: 0, level: 0),
            .init(latitude: 0.001, longitude: 0, level: 1),
        ]
    )

    private let oneWaypoint = ProximiioJourney(
        id: "org:two",
        name: "Stub",
        waypoints: [.init(latitude: 0, longitude: 0, level: 0)]
    )

    func testPlayableRowHasSummaryAndNoFailure() {
        let row = JourneyPickerRow.rows(for: [playable])[0]
        XCTAssertTrue(row.isPlayable)
        XCTAssertEqual(row.id, "org:one")
        XCTAssertEqual(row.title, "Lobby to café")
        XCTAssertNil(row.failure)
        XCTAssertEqual(row.summary, "111 m · 2 min · 2 waypoints · levels 0, 1")
    }

    func testUnplayableRowCarriesValidationFailure() {
        let row = JourneyPickerRow.rows(for: [oneWaypoint])[0]
        XCTAssertFalse(row.isPlayable)
        XCTAssertEqual(row.failure, oneWaypoint.validationFailure())
        XCTAssertNotNil(row.failure)
        XCTAssertNil(row.summary)
    }

    func testRowsKeepApiOrderAndIdentifyJourneysWithoutID() {
        var unnamed = playable
        unnamed.id = nil
        unnamed.name = " "
        let rows = JourneyPickerRow.rows(for: [oneWaypoint, unnamed, playable])
        XCTAssertEqual(rows.map(\.id), ["org:two", "journey-1", "org:one"])
        XCTAssertEqual(rows[1].title, "Untitled journey")
        XCTAssertFalse(rows[1].isPlayable, "a journey without a name does not validate")
    }

    func testSingleLevelSummary() {
        var flat = playable
        flat.waypoints[1].level = 0
        XCTAssertTrue(JourneyPickerRow.summary(of: flat).hasSuffix("· level 0"))
    }

    func testContentForEachResult() {
        struct Offline: LocalizedError { var errorDescription: String? { "offline" } }
        XCTAssertEqual(JourneyPickerContent.from(.success([])), .empty)
        XCTAssertEqual(JourneyPickerContent.from(.failure(Offline())), .failed("offline"))
        XCTAssertEqual(
            JourneyPickerContent.from(.success([playable, oneWaypoint])),
            .loaded(JourneyPickerRow.rows(for: [playable, oneWaypoint]))
        )
    }

    func testFormats() {
        XCTAssertEqual(JourneyFormat.distance(84.6), "85 m")
        XCTAssertEqual(JourneyFormat.distance(1234), "1.2 km")
        XCTAssertEqual(JourneyFormat.duration(45), "45 s")
        XCTAssertEqual(JourneyFormat.duration(365), "6 min")
        XCTAssertEqual(JourneyFormat.duration(3900), "1 h 5 min")
        XCTAssertEqual(JourneyFormat.clock(187), "3:07")
        XCTAssertEqual(JourneyFormat.clock(3725), "1:02:05")
        XCTAssertEqual(JourneyFormat.speed(2), "2x")
        XCTAssertEqual(JourneyFormat.speed(2.5), "2.5x")
    }
}

final class JourneyPlaybackSessionTests: XCTestCase {

    func testStartsOffWithoutControls() {
        let session = JourneyPlaybackSession()
        XCTAssertEqual(session.phase, .off)
        XCTAssertFalse(session.showsControls)
    }

    func testBeginAttachPauseResume() {
        var session = JourneyPlaybackSession()
        session.begin(title: "org:one")
        XCTAssertEqual(session.phase, .starting)
        XCTAssertTrue(session.showsControls)
        XCTAssertFalse(session.pause(), "nothing to pause before the provider is attached")

        session.attached(title: "Lobby", duration: 125)
        XCTAssertEqual(session.phase, .playing)
        XCTAssertEqual(session.title, "Lobby")
        XCTAssertEqual(session.status, "Playing · 0:00 / 2:05")

        XCTAssertTrue(session.pause())
        XCTAssertFalse(session.pause())
        XCTAssertEqual(session.phase, .paused)
        XCTAssertTrue(session.canResume)

        XCTAssertTrue(session.resume())
        XCTAssertFalse(session.resume())
        XCTAssertEqual(session.phase, .playing)
    }

    func testProviderStateDrivesProgressAndFinish() {
        var session = JourneyPlaybackSession()
        session.begin(title: "x")
        session.attached(title: "x", duration: 60)
        session.observe(.running, elapsed: 30)
        XCTAssertEqual(session.status, "Playing · 0:30 / 1:00")
        session.observe(.finished, elapsed: 60)
        XCTAssertEqual(session.phase, .finished)
        XCTAssertFalse(session.canPause)
        XCTAssertFalse(session.canResume)
        XCTAssertTrue(session.showsControls, "Stop stays available to re-attach the relay")
    }

    func testProviderStateIgnoredOutsidePlayback() {
        var session = JourneyPlaybackSession()
        session.observe(.finished, elapsed: 10)
        XCTAssertEqual(session.phase, .off)
        session.begin(title: "x")
        session.observe(.running, elapsed: 10)
        XCTAssertEqual(session.phase, .starting)
    }

    func testFailureOnlyWhileStartingAndEndClearsEverything() {
        var session = JourneyPlaybackSession()
        session.fail("late")
        XCTAssertEqual(session.phase, .off)
        session.begin(title: "org:bad")
        session.fail("not found")
        XCTAssertEqual(session.phase, .failed("not found"))
        XCTAssertEqual(session.status, "Failed: not found")
        session.attached(title: "x", duration: 1)
        XCTAssertEqual(session.phase, .failed("not found"), "a failed start does not become playing")
        session.end()
        XCTAssertEqual(session, JourneyPlaybackSession())
    }

    func testLaunchArguments() {
        XCTAssertNil(JourneyPlaybackLaunch.request(from: ["app"]))
        XCTAssertNil(JourneyPlaybackLaunch.request(from: ["app", "-journeyPlayback", "-journeyLoop"]))
        XCTAssertEqual(
            JourneyPlaybackLaunch.request(from: ["app", "-journeyPlayback", "org:one", "-journeySpeed", "5", "-journeyLoop"]),
            .init(journeyID: "org:one", options: .init(speed: 5, loops: true))
        )
        XCTAssertEqual(
            JourneyPlaybackLaunch.request(from: ["app", "-journeyPlayback", "org:one", "-journeyLoop", "NO"])?.options,
            JourneyPlaybackOptions()
        )
    }

    func testOptionsLogLine() {
        XCTAssertEqual(JourneyPlaybackOptions().logLine, "1x")
        XCTAssertEqual(JourneyPlaybackOptions(speed: 2, loops: true).logLine, "2x, looping")
        XCTAssertEqual(JourneyPlaybackOptions.pickerSpeeds, [1, 2, 5])
    }
}
#endif
