//
//  JourneyPlayback.swift
//  BlueiotMinimal
//
//  Debug builds only. The rules behind the journey picker and its playback
//  controls: the picker's rows and list states, the playback options, and the
//  playback session state. The views are in JourneyPickerSheet.swift; the
//  attach and detach calls are in Venue.swift. Release and TestFlight builds do
//  not contain this code.
//
#if DEBUG
import Foundation
import Proximiio

/// How a journey is played. Both the launch arguments and the picker produce
/// one.
struct JourneyPlaybackOptions: Equatable {
    /// The speeds the picker offers, in journey seconds per real second.
    static let pickerSpeeds: [Double] = [1, 2, 5]

    var speed: Double = 1
    var loops = false

    /// The diagnostics log text, for example `2x, looping`.
    var logLine: String {
        "\(JourneyFormat.speed(speed))\(loops ? ", looping" : "")"
    }
}

/// One journey in the picker.
struct JourneyPickerRow: Identifiable, Equatable {
    let id: String
    let journey: ProximiioJourney
    let title: String
    /// Distance, duration, waypoint count and levels. `nil` for a journey that
    /// cannot be played; its timeline is not meaningful.
    let summary: String?
    /// `validationFailure()` of the journey. `nil` for a playable journey.
    let failure: String?

    var isPlayable: Bool { failure == nil }

    /// One row per journey, in the order given. A journey without an id is
    /// identified by its position.
    static func rows(for journeys: [ProximiioJourney]) -> [JourneyPickerRow] {
        journeys.enumerated().map { index, journey in
            let failure = journey.validationFailure()
            let name = journey.displayName
            return JourneyPickerRow(
                id: journey.id ?? "journey-\(index)",
                journey: journey,
                title: name.isEmpty ? "Untitled journey" : name,
                summary: failure == nil ? summary(of: journey) : nil,
                failure: failure
            )
        }
    }

    /// For example `412 m · 6 min · 9 waypoints · levels 0, 1`.
    static func summary(of journey: ProximiioJourney) -> String {
        let timeline = ProximiioJourneyTimeline(journey: journey)
        let levels = Set(journey.waypoints.compactMap { $0.level.map(Int.init) }).sorted()
        let levelText = levels.count == 1
            ? "level \(levels[0])"
            : "levels " + levels.map(String.init).joined(separator: ", ")
        return [
            JourneyFormat.distance(timeline.totalDistance),
            JourneyFormat.duration(timeline.duration),
            "\(journey.waypoints.count) waypoints",
            levelText,
        ].joined(separator: " · ")
    }
}

/// What the picker shows: a spinner, a message or the list.
enum JourneyPickerContent: Equatable {
    case loading
    case empty
    case failed(String)
    case loaded([JourneyPickerRow])

    /// The content for the result of `Proximiio.journeys()`.
    static func from(_ result: Result<[ProximiioJourney], any Error>) -> JourneyPickerContent {
        switch result {
        case .success(let journeys) where journeys.isEmpty: .empty
        case .success(let journeys): .loaded(JourneyPickerRow.rows(for: journeys))
        case .failure(let error): .failed(error.localizedDescription)
        }
    }
}

/// The playback controls' state. A value type without SDK calls;
/// `JourneyPlaybackController` applies it to the provider.
///
/// `off` shows no controls. `begin` → `starting` → `attached` → `playing`;
/// `pause` and `resume` switch between `playing` and `paused`; the provider's
/// `finished` or `stopped` state ends in `finished`; a failed fetch ends in
/// `failed`. `end` returns to `off` from every state.
struct JourneyPlaybackSession: Equatable {
    enum Phase: Equatable {
        case off, starting, playing, paused, finished
        case failed(String)
    }

    private(set) var phase: Phase = .off
    private(set) var title = ""
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    /// Whether the controls are on screen. When `false` the picker button is.
    var showsControls: Bool { phase != .off }
    var canPause: Bool { phase == .playing }
    var canResume: Bool { phase == .paused }

    /// The second line of the controls.
    var status: String {
        switch phase {
        case .off: ""
        case .starting: "Starting…"
        case .playing: "Playing · \(progress)"
        case .paused: "Paused · \(progress)"
        case .finished: "Finished"
        case .failed(let reason): "Failed: \(reason)"
        }
    }

    private var progress: String {
        "\(JourneyFormat.clock(elapsed)) / \(JourneyFormat.clock(duration))"
    }

    mutating func begin(title: String) {
        self = JourneyPlaybackSession(phase: .starting, title: title)
    }

    mutating func attached(title: String, duration: TimeInterval) {
        guard phase == .starting else { return }
        phase = .playing
        self.title = title
        self.duration = duration
    }

    mutating func fail(_ reason: String) {
        guard phase == .starting else { return }
        phase = .failed(reason)
    }

    /// `true` when the provider is to be paused.
    mutating func pause() -> Bool {
        guard phase == .playing else { return false }
        phase = .paused
        return true
    }

    /// `true` when the provider is to be resumed.
    mutating func resume() -> Bool {
        guard phase == .paused else { return false }
        phase = .playing
        return true
    }

    /// Applies the provider's diagnostics. Only a running or paused session
    /// follows them; `off`, `starting` and `failed` belong to the app.
    mutating func observe(_ state: JourneyPlaybackState, elapsed: TimeInterval) {
        guard phase == .playing || phase == .paused else { return }
        self.elapsed = elapsed
        if state == .finished || state == .stopped { phase = .finished }
    }

    mutating func end() {
        self = JourneyPlaybackSession()
    }
}

/// The playback that is attached, and its session for the views. Owned by
/// `Venue`, which attaches and detaches the provider.
@MainActor
final class JourneyPlaybackController: ObservableObject {
    @Published private(set) var session = JourneyPlaybackSession()
    private var provider: JourneyPlaybackProvider?

    /// Shows `Starting…`. The provider attached before stays until `end()` or
    /// `attached(_:)`.
    func begin(title: String) {
        session.begin(title: title)
    }

    func attached(_ provider: JourneyPlaybackProvider) {
        self.provider = provider
        session.attached(title: provider.journey.displayName, duration: provider.timeline.duration)
    }

    func fail(_ reason: String) {
        session.fail(reason)
    }

    func togglePause() async {
        if session.pause() {
            await provider?.pausePlayback()
        } else if session.resume() {
            await provider?.resumePlayback()
        }
    }

    /// Reads the provider's elapsed time and state. The controls call it once a
    /// second.
    func refresh() async {
        guard let provider else { return }
        let diagnostics = await provider.diagnostics
        // The provider may have been replaced during the read.
        guard provider === self.provider else { return }
        session.observe(diagnostics.state, elapsed: diagnostics.elapsed)
    }

    /// Ends the provider's sample streams and clears the session. Call after
    /// detaching.
    func end() async {
        let provider = self.provider
        self.provider = nil
        session.end()
        await provider?.finish()
    }
}

/// The picker's and the controls' number formats.
enum JourneyFormat {
    /// `85 m`, `1.2 km`.
    static func distance(_ metres: Double) -> String {
        metres < 1000
            ? "\(Int(metres.rounded())) m"
            : String(format: "%.1f km", metres / 1000)
    }

    /// `45 s`, `6 min`, `1 h 5 min`.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let minutes = (total + 30) / 60
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    /// `3:07`, `1:02:05`.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// `1x`, `2.5x`.
    static func speed(_ speed: Double) -> String {
        speed.rounded() == speed ? "\(Int(speed))x" : "\(speed)x"
    }
}
#endif
