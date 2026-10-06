//
//  PositionSmoothingSetting.swift
//  BlueiotMinimal
//
//  The "Smooth position" switch. It is in the system Settings app, under the
//  app's name, and is defined in Settings.bundle/Root.plist. The app has no
//  settings screen of its own.
//
//  On, the default: the map smooths the dot (`PositionSmoothing.adaptive`).
//  Off: the map draws the dot exactly on each fix (`PositionSmoothing.none`).
//  Use off to compare positions with the venue's own RTLS viewer. The dot then
//  jumps between fixes, so leave it on for visitors.
//
//  The switch changes the map only. The SDK does not smooth fixes from the
//  binding's position provider: they reach `positions()` unchanged. The SDK
//  route snapping would move them, but it is off unless
//  `enableRouteSnapping()` is called, and this app does not call it.
//
//  `VenueMapScreen` reads the value when it creates the map session, and again
//  each time the app returns to the foreground.
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

    /// Registers `defaultValue`. Call before the first read; `BlueiotMinimalApp`
    /// calls it at launch. Registered values are not stored and must be
    /// registered on every launch.
    static func register(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [key: defaultValue])
    }

    /// The map smoothing for the stored value: `.adaptive` when the switch is
    /// on, `.none` when it is off.
    static func smoothing(in defaults: UserDefaults = .standard) -> PositionSmoothing {
        defaults.bool(forKey: key) ? .adaptive : .none
    }
}
