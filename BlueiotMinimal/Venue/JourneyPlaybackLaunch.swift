//
//  JourneyPlaybackLaunch.swift
//  BlueiotMinimal
//
//  Debug builds only. Plays a journey stored on Proximi.io in place of the cloud
//  relay, for testing the app away from the venue. Launch arguments:
//
//    -journeyPlayback <id>   the journey, `<organisation uuid>:<uuid>`
//    -journeySpeed <x>       optional, 0.5 to 10, default 1
//    -journeyLoop            optional, start again after the last waypoint
//
//  The journey is fetched once with the application token; the positions are
//  generated on the phone. The journey picker (JourneyPickerSheet.swift) starts
//  playback through the same `Venue.playJourney` call. Release and TestFlight
//  builds do not contain this code.
//
#if DEBUG
import Foundation
import Proximiio

enum JourneyPlaybackLaunch {

    /// The playback the launch arguments request.
    struct Request: Equatable {
        let journeyID: String
        let options: JourneyPlaybackOptions
    }

    /// Reads the launch arguments. `nil` when `-journeyPlayback` is absent or has
    /// no value.
    static func request(from arguments: [String]) -> Request? {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            let value = arguments[index + 1]
            return value.hasPrefix("-") ? nil : value
        }
        guard let id = value(after: "-journeyPlayback") else { return nil }
        let loopValue = value(after: "-journeyLoop")?.lowercased()
        return Request(
            journeyID: id,
            options: JourneyPlaybackOptions(
                speed: value(after: "-journeySpeed").flatMap(Double.init) ?? 1,
                loops: arguments.contains("-journeyLoop") && !["no", "0", "false"].contains(loopValue ?? "")
            )
        )
    }

    /// The playback provider for `journey`. The launch argument and the picker
    /// both attach this provider.
    static func provider(for journey: ProximiioJourney, options: JourneyPlaybackOptions) -> JourneyPlaybackProvider {
        JourneyPlaybackProvider(
            journey: journey,
            configuration: JourneyPlaybackConfiguration(
                speed: options.speed,
                loops: options.loops,
                // As for the relay: keep playing with the screen locked.
                runsInBackground: true
            )
        )
    }
}
#endif
