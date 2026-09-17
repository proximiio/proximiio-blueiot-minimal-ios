# Proximi.io BlueIoT — minimal reference app

A complete venue app in 1535 lines of Swift across thirteen files. It asks for
the visitor's wristband number once, shows the venue map, searches the venue's
places, routes to the picked place, shows the next turn, posts a notification
for each place entered or left, and walks a planned visit of several places in
order, with adding, reordering and detours. Positioning continues with the phone
in a pocket. The visitor is positioned by the venue's BlueIoT anchors through
the Proximi.io cloud relay; the phone scans nothing.

The app is meant to be read. Every file is short, and the comments mark where
product code goes. The comments and this README follow the rules in
[docs/STYLE.md](docs/STYLE.md).

## What it deliberately is NOT

No settings screen. No diagnostics UI. No staff mode, engine switches, event
log, offline package or step list. Nothing reorders a visit on its own. Each of
these exists in the SDK and is omitted here; every additional setting is one
more to read, decide about and maintain.

The full demo app (`proximiio-blueiot-ios`) shows all of them at once. It is a
field-debugging tool for the Proximi.io team, not a starting point for a product.

Positioning continues with the phone in a pocket or the screen locked. The
visitor answers one location prompt and one notification prompt, both on the
first launch. The developer's part is under **In a pocket**
and **Geofence notifications** below.

## Fill in the configuration

Three values, all build-time, none editable at runtime:

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
$EDITOR Config/Secrets.xcconfig
```

| Key | What it is |
| --- | --- |
| `PROXIMIIO_APPLICATION_TOKEN` | Your Proximi.io application token (Proximi.io Portal → organisation → Application token) |
| `BLUEIOT_CLOUD_RELAY_URL` | The Proximi.io cloud relay carrying this venue's wristband positions. A bare host is enough |
| `BLUEIOT_CLOUD_RELAY_TOKEN` | That relay's stream token, sent as `Authorization: Bearer` |

`Config/Secrets.xcconfig` is gitignored and is the only place for a real
credential. `Config/App.xcconfig` is tracked, leaves those three keys empty and
`#include?`s your copy last, so your values win. It carries one non-secret venue
value; see **Floor numbers** below. With any key empty the app still builds and
runs, and shows on screen which key is missing.

## Run it

```sh
brew install xcodegen          # once
xcodegen generate
open BlueiotMinimal.xcodeproj
```

Or from the command line:

```sh
xcodebuild -project BlueiotMinimal.xcodeproj -scheme BlueiotMinimal \
  -destination 'generic/platform=iOS' build
xcodebuild -project BlueiotMinimal.xcodeproj -scheme BlueiotMinimal \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Dependencies are the published binary distributions, pinned to exact versions in
`project.yml`; the same artefacts a customer resolves. There are no local
package paths.

## Where things are

| File | What it owns |
| --- | --- |
| `App/BlueiotMinimalApp.swift` | The launch order: wristband → location → notifications → map. The SDK starts after location |
| `App/VenueConfiguration.swift` | The build-time values |
| `Venue/WristbandID.swift` | The parsing rule for a wristband id, and its storage |
| `Venue/Venue.swift` | SDK start, cloud relay attachment for one wristband, and a notification per geofence event |
| `Venue/VenuePOI.swift` | The venue's features as searchable places |
| `UI/WristbandPrompt.swift` | The wristband prompt, and the map credits |
| `UI/LocationPrompt.swift` | The location prompt, and the rule for when it is shown |
| `UI/NotificationPrompt.swift` | The notification prompt and the rule for when it is shown, the notification text, and the delegate that shows notifications in the foreground |
| `Venue/JourneyStore.swift` | Persistence of a visit across launches, and the conversion of a picked place into a stop |
| `UI/VenueMapScreen.swift` | Map, search button, route, and the start of a visit |
| `UI/POISearchSheet.swift` | The search list: one place, or several |
| `UI/GuidanceLine.swift` | The turn-by-turn sentence, in the app's language |
| `UI/JourneyBar.swift` | The visit: the active stop, the plan, adding, detours, reordering |
| `Assets.xcassets/AppIcon.appiconset` | The app icon, a **placeholder**; see below |

**The icon is a placeholder.** `AppIcon-1024.png` is a flat Proximi.io stand-in
labelled as such. It is present because App Store validation rejects an archive
without an icon (no 120 px iPhone icon, no 152 px iPad icon, no
`CFBundleIconName`). Replace that one file with your product's 1024×1024 PNG
(opaque, sRGB, square corners; iOS applies the mask) and keep the name, or
update `Contents.json` next to it. Xcode derives every other size from it;
nothing else in the project refers to the image.

## Before you change anything

**Changing the wristband.** A returning visitor is not asked again. The number
can be changed without reinstalling: press and hold the map for 1.5 seconds and
the same prompt opens as a sheet. There is intentionally no visible control; a
visitor does not need it, and staff are told once. For a visible control,
`VenueMapScreen.isChangingWristband` is the single switch.

The same sheet lists the **map credits**. The map hides MapLibre's attribution ⓘ
(`.with(chrome: .bare)` on the `MapOptions` in `VenueMapScreen`). Hiding it
moves the OpenStreetMap (ODbL) and MapLibre credits into the app: they are
`ProximiioMapSession.attributions`, and an app that hides the ⓘ must show them
somewhere reachable from the map. Here that is the long-press sheet.

**Floor numbers.** The relay reports the venue engine's floor numbers, and the
SDK resolves them to Proximi.io floor ids against the floor levels it synced.
The app passes no mapping table; passing one switches that derivation off. A
number the venue has no floor for is logged, not drawn on a blank level.

One integer, in `Config/App.xcconfig`, states the engine's numbering convention:

| Key | What it is |
| --- | --- |
| `BLUEIOT_GROUND_FLOOR_NO` | The floor number the engine reports for the ground floor. A LocalSense engine numbers floors from 1 with no 0 and basements negative; Proximi.io numbers the ground floor 0, so the value is `1`. The SDK applies the shift above ground only: engine 1 is level 0, engine 2 is level 1, engine −1 stays level −1. Empty = `0`, no shift |

It is a venue setting, not a credential, so it is tracked with this venue's value.

**In a pocket.** Positioning continues when the screen locks. It requires four
settings, and each one missing has the same symptom: positioning stops 30
seconds after backgrounding, as if the relay had disconnected. Two are code, in
`Venue.swift`: `relayOnly(token:runsInBackground: true)` for the SDK, and
`runsInBackground: true` on the relay provider configuration, without which the
SDK pauses the provider. Two are in `project.yml` and must survive your edits:
`UIBackgroundModes: [location]`, which lets iOS keep the process running off
screen, and `NSLocationWhenInUseUsageDescription`, the text iOS shows in the
location dialog. `Info.plist` is generated from that file; change them there or
lose them on the next `xcodegen generate`.

The fourth is location authorization. Without it CoreLocation runs no session
and iOS suspends the app after its 30-second grace period. `LocationPrompt` asks
once, between the wristband prompt and the notification prompt, and the iOS
dialog follows.
*While Using the App* is sufficient; the app does not request Always. A denial
is not asked about again, and the map works in the foreground. The phone's
location never enters the position: the venue's anchors position the wristband,
and the location session only keeps the process scheduled.

**Geofence notifications.** Every geofence the wristband enters or leaves
produces a local notification, in the foreground and in the background. The
location mode above keeps the process alive, and a local notification needs no
background mode or purpose string of its own. The geofences are the ones defined
in Proximi.io Portal: `authenticate()` syncs them, the SDK engine decides the
transitions with its own enter/exit tolerance (the app adds no policy), and
`Venue.announceGeofences` posts one notification per transition.

`NotificationPrompt` is shown on launch, after `LocationPrompt` and before the
map, and the iOS dialog follows its button. It is shown while notification
authorization is `.notDetermined`, so an install updated from a build without
the step is asked on its next launch. A denial is not asked about again. The map
works with or without authorization; without it, no notification is posted.

iOS shows no banner for a notification posted while the app is in the
foreground unless the notification center's delegate returns presentation
options. `ForegroundNotificationPresenter` returns
`[.banner, .list, .sound]`; `BlueiotMinimalApp.init` installs it before anything
is posted. The center holds its delegate weakly, so the presenter is kept in a
`static let`.

Each transition is also a line in the diagnostics log: `geofence enter · Lobby ·
notified`, or `· not authorized`. The authorization status at launch is one line,
in iOS's spelling: `notifications: authorized`, `denied` or `notDetermined`.

**Picking a place.** A tap on a place's glyph or label on the map picks it as a
search pick does, through `route(to:)` in `VenueMapScreen`, after
`VenuePOI.place(under:in:)` matches the feature ids
`ProximiioMapSession.onFeatureTap` reports; a tap on no place, or during a
visit, changes nothing.

**Turn-by-turn.** `session.guidanceRules = .venueWalk` in `VenueMapScreen`
enables it. The map library then follows the route it draws and republishes
`session.guidance` on every fix; the bottom bar shows the next manoeuvre, the
metres left to it, and, once, that the visitor has arrived. The instruction
sentences belong to the app, in `GuidanceLine.instruction(for:)`, because
`RouteManoeuvre.Kind` carries no display strings.

Leaving the route is reported, not acted on: `isOffRoute` becomes `true` after
three fixes more than twelve metres from the route and returns to `false` on
the first fix back on it. The bar shows it; the app adds no detector and no
re-routing of its own.

**A visit.** The list button next to the search opens the same search sheet in
multi-select; the places tapped, in that order, become a `Journey`. From there
`JourneyNavigator` owns every route computation: it draws and follows one leg at
a time through the map session and re-routes a leg when the visitor leaves it,
which a single route does not do.

The bar shows the active stop, what is left (`overview.remainingMeters`, its
ETA and any leg the router refused), and **Continue** once the visitor has
arrived. Arrival does not advance the journey; the advance rule is `.manual`.

**Your visit**, the list button on the bar, is where the plan is changed:

| | |
| --- | --- |
| **+** | Opens the same multi-select search used to plan the visit. `JourneyNavigator.add` appends each pick after the remaining stops; the active leg is unchanged. A place the plan already holds is named on the sheet, not dropped. **+** is available when the visit is done too: adding makes the journey active again, and the new stop becomes the active one |
| **Drag** | Reorders the remaining stops. The rows are `JourneyNavigator.reorderableStops`, the array `move(stopID:toIndex:)` indexes into; the app holds no second copy of which stops may move |
| **Save N m by reordering** | A shorter order, measured. Neither the library nor the sheet applies it; a tap does. It is re-measured whenever the stops change, because `apply` ignores a proposal that no longer describes the journey |
| **Show the whole plan on the map** | Draws the remaining legs under the active leg. Off by default |

"Stop off" is a detour. The kinds of place come from the venue's amenity tags,
not from a category list in the app. The name of each kind comes from the SDK
amenity store: `amenities()` when a visit starts (a download only while nothing
is stored), then `amenity(id:)`, a local row read. The app stores no titles of
its own, so an amenity renamed on the server is renamed here without a release.

The visit is written to `UserDefaults` on every change and restored on launch,
so it survives the app being closed: `Journey` is `Codable` and each stop
carries its state.

**Following the visitor.** The button at the right of the bottom bar recentres
the map on the wristband. It is one call into the map library's follow camera
(`ProximiioMapSession.recentre()` plus `followMyFloor()`); the app writes no
camera of its own. Panning, pinching or rotating the map releases the follow;
the library detects the gesture and publishes it through
`ProximiioMapSession.cameraMode`, which fills or outlines the button's symbol.

## The diagnostics log

From its first statement (`BlueiotMinimalApp.init`; the comment there says why
it must be first) the app has the SDK record everything positioning sees: fixes,
floors, relay connection state, the SDK's own warnings, the notification
authorization status at launch, each geofence transition and whether it was
notified, and `scene: background` / `scene: foreground` as
the app leaves and returns to the screen. The file is
`Documents/proximiio-diagnostics/proximiio-diagnostics.log` in the app
container. For a problem nobody can reproduce, Proximi.io support may ask for
that folder; on a development build, Xcode's Devices and Simulators window
downloads the container.

The log carries no credential. The SDK redacts the shapes it recognises (bearer
tokens, `token=` values, JWTs, passwords in URLs, e-mail addresses) and, because
`VenueConfiguration.secrets` passes them in, the application token and the relay
token wherever they appear. The wristband number is written; it is printed on
the band. The log rotates at 2 MB on the next launch and keeps one previous
generation; an export is capped at 10 MB.

Crash logs from a TestFlight build symbolicate the app's own code. The
`MapLibre`, `ProximiioBinary` and `ProximiioMapBinary` frameworks are SwiftPM
binary targets whose dSYMs are not in the archive by design; App Store Connect
reports "Upload Symbols Failed" for each, which is expected. Proximi.io support
has the dSYMs for the pinned versions (SDK 6.0.0-beta.41, map 6.0.0-beta.15)
from the GitHub source releases.

## Tests

```sh
xcodebuild -project BlueiotMinimal.xcodeproj -scheme BlueiotMinimal \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Twenty-nine tests, in seven subjects chosen for the same reason: each fails
without anything on screen looking wrong. A wristband parsed one way by the app
and another by the relay matches nothing, and the symptom is a position that
never arrives. A visit that does not survive a launch is lost silently. An
amenity query that reads the venue data wrongly makes a venue with toilets look
like one without. A background setting left at its default, or a location
prompt that repeats or never fires, stops positioning thirty seconds after the
screen locks. A credential written into the diagnostics log verbatim travels
with every export. A notification that says *arrived* on the way out, a
launch order without the notification prompt, or a notification posted while
the app is on screen with no delegate to present it, is wrong in the same
silent way. A map tap matched against the wrong ids picks nothing, and
the map reads as one without tap selection. The views are not tested; a wrong
layout is visible.
