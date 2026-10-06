//
//  PositionSmoothingSetting.swift
//  BlueiotMinimal
//
//  The "Smooth position" switch and the "Smoothing" values. They are in the
//  system Settings app, under the app's name, and are defined in
//  Settings.bundle/Root.plist. The app has no settings screen of its own.
//
//  On, the default: the map smooths the dot (`PositionSmoothing.adaptive`).
//  Off: the map draws the dot exactly on each fix (`PositionSmoothing.none`).
//  Use off to compare positions with the venue's own RTLS viewer. The dot then
//  jumps between fixes, so leave it on for visitors.
//
//  The "Smoothing" values set `PositionStyle.smoothingTuning`. The map reads
//  them only while the switch is on. An empty field, or text that is not a
//  number, keeps the map default. A comma is accepted as the decimal
//  separator. The map clamps each value (`PositionSmoothingTuning.init`), so a
//  negative value becomes 0. The values are for testers who compare tunings on
//  one venue; visitors keep the defaults.
//
//  The switch changes the map only. The SDK does not smooth fixes from the
//  binding's position provider: they reach `positions()` unchanged. The SDK
//  route snapping would move them, but it is off unless
//  `enableRouteSnapping()` is called, and this app does not call it.
//
//  `VenueMapScreen` reads the values when it creates the map session, and
//  again each time the app returns to the foreground.
//
import Foundation
import ProximiioMap

enum PositionSmoothingSetting {
    /// The `UserDefaults` key. The same string is the `Key` of the switch in
    /// Settings.bundle/Root.plist.
    static let key = "smoothPosition"

    /// The value until the visitor changes the switch. The same value is the
    /// `DefaultValue` in Settings.bundle/Root.plist. iOS does not write that
    /// value into `UserDefaults`, so `register(in:)` must.
    static let defaultValue = true

    /// The key of the "Reset to defaults" switch. A Settings bundle has no
    /// buttons. When the switch is on, `resetTuningIfRequested(in:)` removes
    /// every `Knob` value and turns the switch off again.
    static let resetKey = "smoothingReset"

    /// One text field in the "Smoothing" group. The raw value is the
    /// `UserDefaults` key and the `Key` of the field in
    /// Settings.bundle/Root.plist. The field has no `DefaultValue`, so it is
    /// empty until a tester enters a value.
    enum Knob: String, CaseIterable {
        case windowSeconds = "smoothingWindowSeconds"
        case stillSpeedMetersPerSecond = "smoothingStillSpeed"
        case walkSpeedMetersPerSecond = "smoothingWalkSpeed"
        case stillSmoothingSeconds = "smoothingStillSeconds"
        case walkSmoothingSeconds = "smoothingWalkSeconds"
        case deadBandMeters = "smoothingDeadBand"
        case positionSettlingSeconds = "smoothingPositionSettling"
        case headingSettlingSeconds = "smoothingHeadingSettling"

        /// The value in `PositionSmoothingTuning.default`. The field title in
        /// Settings.bundle shows the same value.
        var defaultValue: Double {
            value(in: .default)
        }

        /// This knob's value in `tuning`.
        func value(in tuning: PositionSmoothingTuning) -> Double {
            switch self {
            case .windowSeconds: tuning.windowSeconds
            case .stillSpeedMetersPerSecond: tuning.stillSpeedMetersPerSecond
            case .walkSpeedMetersPerSecond: tuning.walkSpeedMetersPerSecond
            case .stillSmoothingSeconds: tuning.stillSmoothingSeconds
            case .walkSmoothingSeconds: tuning.walkSmoothingSeconds
            case .deadBandMeters: tuning.deadBandMeters
            case .positionSettlingSeconds: tuning.positionSettlingSeconds
            case .headingSettlingSeconds: tuning.headingSettlingSeconds
            }
        }
    }

    /// Registers `defaultValue` and an off reset switch. Call before the first
    /// read; `BlueiotMinimalApp` calls it at launch. Registered values are not
    /// stored and must be registered on every launch.
    static func register(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [key: defaultValue, resetKey: false])
    }

    /// The map smoothing for the stored value: `.adaptive` when the switch is
    /// on, `.none` when it is off.
    static func smoothing(in defaults: UserDefaults = .standard) -> PositionSmoothing {
        defaults.bool(forKey: key) ? .adaptive : .none
    }

    /// The tuning from the "Smoothing" fields. A field that is empty or not a
    /// number uses its default. The map clamps the result.
    static func tuning(in defaults: UserDefaults = .standard) -> PositionSmoothingTuning {
        func value(_ knob: Knob) -> Double {
            number(from: defaults.object(forKey: knob.rawValue)) ?? knob.defaultValue
        }
        return PositionSmoothingTuning(
            windowSeconds: value(.windowSeconds),
            stillSpeedMetersPerSecond: value(.stillSpeedMetersPerSecond),
            walkSpeedMetersPerSecond: value(.walkSpeedMetersPerSecond),
            stillSmoothingSeconds: value(.stillSmoothingSeconds),
            walkSmoothingSeconds: value(.walkSmoothingSeconds),
            deadBandMeters: value(.deadBandMeters),
            positionSettlingSeconds: value(.positionSettlingSeconds),
            headingSettlingSeconds: value(.headingSettlingSeconds)
        )
    }

    /// The number in a stored field value, or `nil`. The Settings app stores
    /// a text field as a `String`. Surrounding spaces are ignored and a comma
    /// is read as the decimal separator. Text that is not a finite number
    /// returns `nil`.
    static func number(from stored: Any?) -> Double? {
        let parsed: Double?
        switch stored {
        case let text as String:
            let normalized = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            parsed = Double(normalized)
        case let number as NSNumber:
            parsed = number.doubleValue
        default:
            parsed = nil
        }
        guard let parsed, parsed.isFinite else { return nil }
        return parsed
    }

    /// Removes every `Knob` value and turns the reset switch off, when the
    /// switch is on. Returns `true` when it reset the values. Call before
    /// `tuning(in:)`.
    @discardableResult
    static func resetTuningIfRequested(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: resetKey) else { return false }
        for knob in Knob.allCases {
            defaults.removeObject(forKey: knob.rawValue)
        }
        defaults.set(false, forKey: resetKey)
        return true
    }

    /// The diagnostics log line for `style`: "on" with each tuning value, or
    /// "off".
    static func summary(of style: PositionStyle) -> String {
        guard style.smoothing != .none else { return "position smoothing: off" }
        let tuning = style.smoothingTuning
        return "position smoothing: on"
            + ", window \(tuning.windowSeconds) s"
            + ", still speed \(tuning.stillSpeedMetersPerSecond) m/s"
            + ", walk speed \(tuning.walkSpeedMetersPerSecond) m/s"
            + ", still smoothing \(tuning.stillSmoothingSeconds) s"
            + ", walk smoothing \(tuning.walkSmoothingSeconds) s"
            + ", dead band \(tuning.deadBandMeters) m"
            + ", dot settling \(tuning.positionSettlingSeconds) s"
            + ", heading settling \(tuning.headingSettlingSeconds) s"
            + (tuning == .default ? " (defaults)" : "")
    }
}
