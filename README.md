# Proximi.io BlueIoT — minimal reference app

A venue app for a visitor the venue positions. The venue's BlueIoT anchors locate
a wristband and report to a Proximi.io cloud relay; the phone scans nothing and
contributes no position of its own.

It asks for the visitor's wristband number once, shows the venue map, searches
the venue's places, routes to a picked place, shows the next manoeuvre, posts a
local notification for each geofence entered or left, and walks a planned visit
of several places in order, with adding, reordering and detours. Positioning
continues with the phone in a pocket or the screen locked.

1615 lines of Swift in fourteen files. The comments mark where product code goes.
The comments and this README are documentation: each states what the code does
and what a reader has to do about it, not how it came to be written. Keep that
register when you extend the app.

## What the app does not do

No settings screen, no diagnostics UI, no staff mode, no engine switch, no event
log, no offline package, no step list. Nothing reorders a visit without a tap.
The SDK provides each of these; this app omits them.

## Requirements

`project.yml` declares `xcodeVersion: "16.0"` and the committed project is in the
Xcode 16 format (`objectVersion = 77`). The deployment target is iOS 17.0. The
simulator named in the commands below, `iPhone 17`, ships with Xcode 26;
substitute one your Xcode installs.

`project.yml` carries Proximi.io's signing: `bundleIdPrefix: io.proximi` and
`DEVELOPMENT_TEAM: 2ULWCJMDBJ`. Replace both with your own identifier and team
before you sign, then run `xcodegen generate` again. Signing with the values in
this repository fails outside Proximi.io's account.

From Proximi.io you need the three values in the next section and one wristband
number registered in the venue. The venue's floors, places and geofences come
from Proximi.io Portal; the app reads them and defines none of its own.

## Configuration

Three values, all build-time, none editable at runtime:

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
$EDITOR Config/Secrets.xcconfig
```

| Key | Value |
| --- | --- |
| `PROXIMIIO_APPLICATION_TOKEN` | The Proximi.io application token (Proximi.io Portal → organisation → Application token) |
| `BLUEIOT_CLOUD_RELAY_URL` | The Proximi.io cloud relay carrying this venue's wristband positions. A bare host is enough; the SDK derives `https://…` and `wss://…/stream` from it |
| `BLUEIOT_CLOUD_RELAY_TOKEN` | That relay's stream token, sent as `Authorization: Bearer` |

`Config/Secrets.xcconfig` is gitignored and is the only place for a real
credential. `Config/App.xcconfig` is tracked, leaves those three keys empty and
`#include?`s your copy last, so your values win. It carries one non-secret venue
value; see **Floor numbers** below.

An empty key neither fails the build nor crashes the app.
`VenueConfiguration.missing` names every empty key in one sentence, which
`WristbandPrompt` shows under the number field. Past that point the effects
differ:

| Empty key | Effect |
| --- | --- |
| `PROXIMIIO_APPLICATION_TOKEN` | `RootView.connect()` throws `VenueConfiguration.SetupIncomplete` before the SDK starts; the map step shows "Cannot reach the venue" with the same sentence |
| `BLUEIOT_CLOUD_RELAY_URL` | The SDK starts, `Venue.follow(_:)` attaches no position provider and no position arrives |
| `BLUEIOT_CLOUD_RELAY_TOKEN` | The provider is attached and the relay answers HTTP 401 |

## Build and run

```sh
brew install xcodegen          # once
xcodegen generate
open BlueiotMinimal.xcodeproj
```

`BlueiotMinimal.xcodeproj` is committed; `xcodegen generate` is needed again only
after `project.yml` changes.

From the command line:

```sh
xcodebuild -project BlueiotMinimal.xcodeproj -scheme BlueiotMinimal \
  -destination 'generic/platform=iOS' build
xcodebuild -project BlueiotMinimal.xcodeproj -scheme BlueiotMinimal \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Dependencies are the published binary distributions, pinned to exact versions in
`project.yml`: the Proximi.io SDK at `6.0.0-beta.41` and the Proximi.io map at
`6.0.0-beta.15`. MapLibre (`6.29.0`) arrives through the map package and must not
be declared separately. There are no local package paths.

## Where things are

| File | What it owns |
| --- | --- |
| `App/BlueiotMinimalApp.swift` | The launch order: wristband → location → notifications → map. The SDK starts after the location step |
| `App/VenueConfiguration.swift` | The build-time values |
| `Venue/WristbandID.swift` | The parsing rule for a wristband id, and its storage |
| `Venue/Venue.swift` | SDK start, cloud relay attachment for one wristband, and a notification per geofence event |
| `Venue/VenuePOI.swift` | The venue's features as searchable places |
| `Venue/JourneyStore.swift` | Persistence of a visit across launches, and the conversion of a picked place into a stop |
| `UI/WristbandPrompt.swift` | The wristband prompt, and the map credits |
| `UI/LocationPrompt.swift` | The location prompt, and the rule for when it is shown |
| `UI/NotificationPrompt.swift` | The notification prompt and the rule for when it is shown, the notification text, and the delegate that shows notifications in the foreground |
| `UI/VenueMapScreen.swift` | Map, search button, route, and the start of a visit |
| `UI/POISearchSheet.swift` | The search list: one place, or several |
| `UI/GuidanceLine.swift` | The turn-by-turn sentence, in the app's language |
| `UI/JourneyBar.swift` | The visit: the active stop, the plan, adding, detours, reordering |
| `Assets.xcassets/AppIcon.appiconset` | The app icon, a **placeholder**; see below |

**The icon is a placeholder.** `AppIcon-1024.png` is a flat Proximi.io stand-in
labelled as such. It is present because App Store validation rejects an archive
without an icon (no 120 px iPhone icon, no 152 px iPad icon, no
`CFBundleIconName`). Replace that one file with your product's 1024×1024 PNG
(opaque, sRGB, square corners; iOS applies the mask) and keep the name, or update
`Contents.json` next to it. Xcode derives every other size from it; nothing else
in the project refers to the image.

## Behaviour and extension points

**Onboarding.** `LaunchStep.current(hasWristband:owesLocationAsk:owesNotificationAsk:)`
picks the screen: wristband, location, notifications, map. A prompt is shown only
while its answer is owed, so a returning visitor opens the map directly.

| Step | What it does |
| --- | --- |
| `WristbandPrompt` | Takes the number printed on the band, parses it with `WristbandID(text:)` and saves it through `WristbandStore`. Shown while no id is stored |
| `LocationPrompt` | Explains why location is needed and has one **Continue** button. It calls no CoreLocation API itself; answering it lets `Venue.start` run. Shown while location authorization is `.notDetermined` |
| `NotificationPrompt` | **Continue** calls `requestAuthorization(options: [.alert, .sound])`, so the iOS dialog follows the button. Shown while notification authorization is `.notDetermined`, so an install updated from a build without this step is asked on its next launch |
| `VenueMapScreen` | The map. Shown when no prompt is owed |

The SDK starts when the location step is answered, not before: the `.task(id:)`
key in `RootView` is `nil` while `LocationPrompt` is on screen. `Venue.start`
calls `sdk.requestPermissions()`, so the iOS location dialog appears over
`NotificationPrompt`. A denial of either prompt is not asked about again.

**Changing the wristband.** The number can be changed without reinstalling:
press and hold the map for 1.5 seconds and the same prompt opens as a sheet.
There is no visible control; for one, `VenueMapScreen.isChangingWristband` is the
single switch. Saving a different id re-attaches the position provider; it does
not restart the SDK or rebuild the map.

The same sheet lists the **map credits**. The map hides MapLibre's attribution ⓘ,
its logo and the compass (`.with(chrome: .bare)` on the `MapOptions` in
`VenueMapScreen`). Hiding the ⓘ moves the OpenStreetMap (ODbL) and MapLibre
credits into the app: they are `ProximiioMapSession.attributions`, and an app
that hides the ⓘ must show them somewhere reachable from the map. Here that is
the long-press sheet.

**Floor numbers.** The relay reports the venue engine's floor numbers, and the
SDK resolves them to Proximi.io floor ids against the floor levels it synced. The
app passes no `floorNoMap`; passing one switches that derivation off. A number
the venue has no floor for is logged, not drawn on a blank level.

One integer, in `Config/App.xcconfig`, states the engine's numbering convention:

| Key | Value |
| --- | --- |
| `BLUEIOT_GROUND_FLOOR_NO` | The floor number the engine reports for the ground floor, passed to `BlueiotCloudRelayConfiguration.engineGroundFloorNumber`. A LocalSense engine numbers floors from 1 with no 0 and basements negative; Proximi.io numbers the ground floor 0, so the value is `1`. The SDK applies the shift above ground only: engine 1 is level 0, engine 2 is level 1, engine −1 stays level −1. Empty = `0`, no shift |

It is a venue setting, not a credential, so it is tracked with this venue's value.

**Background positioning.** Positioning continues when the screen locks. It
requires four settings, and each one missing has the same symptom: positioning
stops 30 seconds after backgrounding, as if the relay had disconnected.

| Setting | Where | Without it |
| --- | --- | --- |
| `relayOnly(token:runsInBackground: true)` | `Venue.configuration(token:)` | The SDK does not set `allowsBackgroundLocationUpdates` |
| `runsInBackground: true` on `BlueiotCloudRelayConfiguration` | `Venue.follow(_:)` | The SDK pauses the provider on backgrounding |
| `UIBackgroundModes: [location]` and `NSLocationWhenInUseUsageDescription` | `project.yml` | iOS does not honour the background location session |
| Location authorization, *While Using the App* | `LocationPrompt`, then `sdk.requestPermissions()` in `Venue.start` | CoreLocation runs no session |

`BlueiotMinimal/Info.plist` is generated from `project.yml`; change the two keys
there or lose them on the next `xcodegen generate`.

The app does not request Always authorization. A denial leaves the map working in
the foreground. The phone's location never enters the position: the venue's
anchors position the wristband, and the location session only keeps the process
scheduled.

**Geofence notifications.** Every geofence the wristband enters or leaves
produces a local notification, in the foreground and in the background. The
location mode above keeps the process alive, and a local notification needs no
background mode or purpose string of its own. The geofences are the ones defined
in Proximi.io Portal: `authenticate()` syncs them, the SDK engine decides the
transitions with its own enter/exit tolerance (the app adds no policy), and
`Venue.announceGeofences` posts one notification per transition, with a new
identifier each time so notifications do not replace each other. Privacy zones
are not announced. Nothing is posted unless notification authorization is
`.authorized`; the map works either way.

iOS shows no banner for a notification posted while the app is in the foreground
unless the notification center's delegate returns presentation options.
`ForegroundNotificationPresenter` returns `[.banner, .list, .sound]`;
`BlueiotMinimalApp.init` installs it before anything is posted. The center holds
its delegate weakly, so the presenter is kept in a `static let`.

Each transition is also a line in the diagnostics log: `geofence enter · Lobby ·
notified`, or `· not authorized`. The authorization status at launch is one line,
in iOS's spelling: `notifications: authorized`, `denied` or `notDetermined`.

**Picking a place on the map.** A tap on a place's glyph or label picks it as a
search pick does, through `route(to:)` in `VenueMapScreen`, after
`VenuePOI.place(under:in:)` matches the feature ids
`ProximiioMapSession.onFeatureTap` reports. The first id that matches a place
wins. A tap on no place, or during a visit, changes nothing.

**Turn-by-turn.** `session.guidanceRules = .venueWalk` in `VenueMapScreen`
enables it; guidance is off by default. The map library then follows the route it
draws and republishes `session.guidance` on every fix; the bottom bar shows the
next manoeuvre, the metres left to it, and, once, that the visitor has arrived.
The instruction sentences belong to the app, in `GuidanceLine.instruction(for:)`,
because `RouteManoeuvre.Kind` carries no display strings.

Leaving the route is reported, not acted on: `isOffRoute` becomes `true` after
three fixes more than twelve metres from the route and returns to `false` on the
first fix back on it. The bar shows it; the app adds no detector and no
re-routing of its own.

**A visit.** The list button next to the search opens the same search sheet in
multi-select; the places tapped, in that order, become a `Journey`. From there
`JourneyNavigator` owns every route computation: it draws and follows one leg at
a time through the map session and re-routes a leg when the visitor leaves it,
which a single route does not do.

The bar shows the active stop, what is left (`overview.remainingStops.count`,
`overview.remainingMeters`, its ETA and any leg the router refused), and
**Continue** once the visitor has arrived. Arrival does not advance the journey;
the advance rule is `.manual`, and **Continue** calls `advance()`.

**Your visit**, the list button on the bar, is where the plan is changed:

| Control | Effect |
| --- | --- |
| **+** | Opens the same multi-select search used to plan the visit. `JourneyNavigator.add` appends each pick after the remaining stops; the active leg is unchanged. A place the plan already holds is named on the sheet, not dropped. **+** is available when the visit is done too: adding makes the journey active again, and the new stop becomes the active one |
| **Drag** | Reorders the remaining stops. The rows are `JourneyNavigator.reorderableStops`, the array `move(stopID:toIndex:)` indexes into; the app holds no second copy of which stops may move |
| **Save N m by reordering** | `proposeOrder()` measures a shorter order and returns a proposal; neither the library nor the sheet applies it, a tap does. It is re-measured whenever the stops change, because `apply` ignores a proposal that no longer describes the journey |
| **Show the whole plan on the map** | Sets `journeyOverlayStyle = .venue`, which draws the remaining legs under the active leg. Off by default |

"Stop off" is a detour: `detour(to:)` inserts a stop before the active one and
routes to it immediately, and the plan resumes from the visitor's position
afterwards. The kinds of place come from the venue's amenity tags
(`VenuePOI.nearestByAmenity(in:from:)`), not from a category list in the app. The
name of each kind comes from the SDK amenity store: `amenities()` when a visit
starts, which downloads only while nothing is stored, then `amenity(id:)`, a
local row read. The app stores no titles of its own, so an amenity renamed on the
server is renamed here without a release.

The visit is written to `UserDefaults` on every change and restored on launch, so
it survives the app being closed: `Journey` is `Codable` and each stop carries
its state. A stored value that no longer decodes is treated as no visit.

**Following the visitor.** The button at the right of the bottom bar recentres
the map on the wristband. It is one call into the map library's follow camera
(`ProximiioMapSession.recentre()` plus `followMyFloor()`); the app writes no
camera of its own. Panning, pinching or rotating the map releases the follow; the
library detects the gesture and publishes it through
`ProximiioMapSession.cameraMode`, which fills or outlines the button's symbol.

## Diagnostics log

`BlueiotMinimalApp.init` calls `Proximiio.startDiagnosticsRecording` as its first
statement; lines emitted before that call returns are dropped. With
`capturesSDKLog: true` the log records fixes, floors, relay connection state, the
SDK's own warnings, the notification authorization status at launch, the followed
wristband id, each geofence transition and whether it was notified, and
`scene: background` / `scene: foreground` as the app leaves and returns to the
screen. The file is
`Documents/proximiio-diagnostics/proximiio-diagnostics.log` in the app container.
If the log cannot be written, the app runs without one.

The log carries no credential. The SDK redacts the shapes it recognises (URL
userinfo, `token=` and `api_key=` query values, `Authorization: Bearer` and
`password:` assignments, JWTs, e-mail addresses) and, because
`VenueConfiguration.secrets` passes them in, the application token and the relay
token wherever they appear. The wristband number is written; it is printed on the
band. The log rotates at 2 MB, on open and never mid-session, and keeps one
previous generation, `proximiio-diagnostics-previous.log`. A report bundle is
capped at 10 MB (`maximumBundleBytes`).

This app has no export. It calls no report API and declares no file sharing, so
on a development build Xcode's Devices and Simulators window is the only way to
download the container; from a TestFlight or App Store build the log cannot be
retrieved at all. Add a report call if the product needs one in the field.

Crash logs from a TestFlight build symbolicate the app's own code. The
`MapLibre`, `ProximiioBinary` and `ProximiioMapBinary` frameworks are SwiftPM
binary targets whose dSYMs are not in the archive by design; App Store Connect
reports "Upload Symbols Failed" for each, which is expected. Proximi.io support
has the dSYMs for the pinned versions (SDK 6.0.0-beta.41, map 6.0.0-beta.15) from
the GitHub source releases.

## Tests

```sh
xcodebuild -project BlueiotMinimal.xcodeproj -scheme BlueiotMinimal \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Twenty-nine tests in seven classes. Each covers behaviour that fails without
anything on screen looking wrong. The views are not tested; a wrong layout is
visible.

| Class | Tests | Covers |
| --- | --- | --- |
| `WristbandIDTests` | 9 | Every spelling of a tag id through `BlueiotCloudRelayMessage.decimalTagID(_:)`, the canonical decimal form, and `WristbandStore` round-trips. An id parsed one way here and another by the relay matches no tag and no position arrives |
| `JourneyPersistenceTests` | 5 | `JourneyStore` round-trip with stop order and state, clearing, and a stored value that no longer decodes |
| `AmenityQueryTests` | 3 | `VenuePOI.nearestByAmenity(in:from:)`: the nearest place per amenity id, kinds taken from the venue data, untagged places kept as places |
| `MapTapTests` | 4 | `VenuePOI.place(under:in:)` against the feature ids `onFeatureTap` reports, including a tap that matches no place |
| `GeofenceNotificationTests` | 5 | `NotificationPrompt.note(name:entered:)` title, body and log line; the `.notDetermined` ask rule; the launch order; and the foreground presentation options |
| `BackgroundPositioningTests` | 2 | `LocationPrompt.isOwed(_:)` and `runsInBackground` on `Venue.configuration(token:)` |
| `DiagnosticsTests` | 1 | No configured secret reaches the log verbatim |
