# Proximi.io BlueIoT — minimal reference app

A venue app for a visitor the venue positions. The venue's BlueIoT anchors locate
a wristband and report to the Proximi.io relay-api; the phone scans nothing and
contributes no position of its own.

It binds the phone to the visitor's wristband through the SDK's wristband
binding client, shows the venue map, searches
the venue's places, routes to a picked place, shows the next manoeuvre, posts a
local notification for each geofence entered or left, and walks a planned visit
of several places in order, with adding, reordering and detours. Positioning
continues with the phone in a pocket or the screen locked.

2890 lines of Swift in nineteen files, and one Node script,
`scripts/journey-run.mjs`, for tests through the sandbox relay-api. Three of the
Swift files are compiled into debug builds only (see "Playing a journey on the
phone"). The comments mark where product code goes.
The comments and this README are documentation: each states what the code does
and what a reader has to do about it, not how it came to be written. Keep that
register when you extend the app.

## What the app does not do

No settings screen, no diagnostics UI, no staff mode, no engine switch, no event
log, no offline package, no step list. Nothing reorders a started visit without a tap.
The SDK provides each of these; this app omits them.

The **Smooth position** switch is in the system Settings app, under the
app's name (`Settings.bundle`): off draws the dot exactly on each relay fix
(`PositionStyle.smoothing = .none`) for comparison with the venue's RTLS, and
applies when the app returns to the foreground.

The **Smoothing** group under it sets `PositionStyle.smoothingTuning`, for
testers who compare tunings on one venue. Each field title shows the unit and
the map default. The values apply only while Smooth position is on, when the
app returns to the foreground. An empty or invalid field uses the default; a
comma is accepted as the decimal separator; the map clamps out-of-range values.
**Reset to defaults** is a switch, because a Settings bundle has no buttons: the
app empties every field and turns the switch off when it returns to the
foreground. The diagnostics log records the values in use.

## Requirements

`project.yml` declares `xcodeVersion: "16.0"` and the committed project is in the
Xcode 16 format (`objectVersion = 77`). The deployment target is iOS 17.0. The
simulator named in the commands below, `iPhone 17`, ships with Xcode 26;
substitute one your Xcode installs.

`project.yml` carries Proximi.io's signing: `bundleIdPrefix: io.proximi` and
`DEVELOPMENT_TEAM: 2ULWCJMDBJ`. Replace both with your own identifier and team
before you sign, then run `xcodegen generate` again. Signing with the values in
this repository fails outside Proximi.io's account.

From Proximi.io you need the credentials in the next section and one wristband
number registered in the venue's relay-api. The venue's floors, places and geofences come
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
| `BLUEIOT_RELAY_URL` | The relay-api base URL. Default in `Config/App.xcconfig`: `https://relay-api-sandbox.proximi.fi`, the Proximi.io sandbox. For production, the venue's own relay-api URL |
| `BLUEIOT_RELAY_APP_TOKEN` | The app token of that relay-api install, sent as `Authorization: Bearer`. Each install has its own token; it comes from your Proximi.io contact |

In an xcconfig file `//` starts a comment. Write the URL as
`https:/$()/relay-api-sandbox.proximi.fi`, without quotes. Rebuild after
changing a key.

`Config/Secrets.xcconfig` is gitignored and is the only place for a real
credential. `Config/App.xcconfig` is tracked, leaves both tokens empty, sets the
sandbox URL and `#include?`s your copy last, so your values win.

An empty key neither fails the build nor crashes the app.
`VenueConfiguration.missing` names every empty key, and a URL that does not
parse, in one sentence, which `WristbandPrompt` shows under the number field.
Past that point the effects differ:

| Empty key | Effect |
| --- | --- |
| `PROXIMIIO_APPLICATION_TOKEN` | `RootView.connect()` throws `VenueConfiguration.SetupIncomplete` before the SDK starts; the map step shows "Cannot reach the venue" with the same sentence |
| `BLUEIOT_RELAY_URL` or `BLUEIOT_RELAY_APP_TOKEN` | No binding client is created. **Connect** is disabled |

A wrong app token fails each bind with `BlueiotBindingError.appTokenRejected`.
A URL that is not a relay-api install fails with `.notARelayAPI`. The prompt
names the key to check.

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

`project.yml` pins the published binary distributions to exact versions: the
Proximi.io SDK at `6.0.0-beta.52` and the Proximi.io map at `6.0.0-beta.32`.
MapLibre (`6.29.0`) arrives through the map package and must not be declared
separately.

## Where things are

| File | What it owns |
| --- | --- |
| `App/BlueiotMinimalApp.swift` | The launch order: wristband → location → notifications → map. The SDK starts after the location step |
| `App/VenueConfiguration.swift` | The build-time values and the `BlueiotBindingConfiguration` built from them |
| `App/PositionSmoothingSetting.swift` | The **Smooth position** switch and **Smoothing** values from `Settings.bundle`, and the map smoothing and tuning they select |
| `Venue/WristbandSession.swift` | The wristband session: `restore()`, the binding state, the location dialogs before a bind, `bind(tagID:)` and `end()` |
| `Venue/Venue.swift` | SDK start, attachment of the binding's position provider, and a notification per geofence event |
| `Venue/VenuePOI.swift` | The venue's features as searchable places |
| `Venue/JourneyStore.swift` | Persistence of a visit across launches, and the conversion of a picked place into a stop |
| `Venue/JourneyPlaybackLaunch.swift` | Debug builds only. The `-journeyPlayback` launch arguments, and the playback provider they and the picker attach |
| `Venue/JourneyPlayback.swift` | Debug builds only. The journey picker's rows and list states, the playback options, and the playback controls' state |
| `UI/WristbandPrompt.swift` | The wristband prompt, and the map credits |
| `UI/WristbandStatus.swift` | The session state on the map, and **End visit** |
| `UI/WristbandCopy.swift` | The text per bind error, per end reason and per session state |
| `UI/LocationPrompt.swift` | The location prompt, and the rule for when it is shown |
| `UI/NotificationPrompt.swift` | The notification prompt and the rule for when it is shown, the notification text, and the delegate that shows notifications in the foreground |
| `UI/VenueMapScreen.swift` | Map, search button, route, **New route from here**, and the start of a visit |
| `UI/POISearchSheet.swift` | The search list: one place, or several |
| `UI/GuidanceLine.swift` | The turn-by-turn sentence, in the app's language |
| `Venue/VisitRules.swift` | The rules behind the visit's text: when a new visit is ordered, the order row in the plan, and the stop-off lines |
| `UI/JourneyBar.swift` | The visit: the active stop, the plan, adding, stop-offs, reordering, and the prompt shown when the visitor leaves the route |
| `UI/JourneyPickerSheet.swift` | Debug builds only. The journey picker button, the picker sheet and the playback controls |
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
| `WristbandPrompt` | Takes the number printed on the band and binds it. Shown while no wristband session is active |
| `LocationPrompt` | Explains why location is needed and has one **Continue** button. It calls no CoreLocation API itself; answering it lets `Venue.start` run. Shown while location authorization is `.notDetermined` |
| `NotificationPrompt` | **Continue** calls `requestAuthorization(options: [.alert, .sound])`, so the iOS dialog follows the button. Shown while notification authorization is `.notDetermined`, so an install updated from a build without this step is asked on its next launch |
| `VenueMapScreen` | The map. Shown when no prompt is owed |

The SDK starts when a session is active and the location step is answered, not
before: the `.task(id:)` key in `RootView` is `false` until then. The SDK keeps
running when the session ends. `Venue.start`
calls `sdk.requestPermissions()`, so the iOS location dialog appears over
`NotificationPrompt`. A denial of either prompt is not asked about again.

**Wristband binding.** The app positions from the SDK's
`BlueiotWristbandBinding` (`WristbandSession`). The binding client holds the
session in the Keychain; the app stores no wristband id. The relay-api sends the
phone only the bound band's positions.

| Moment | Call | Effect |
| --- | --- | --- |
| Launch | `restore()` | Confirms a stored session with the relay-api. An active session opens the map; an ended one shows the prompt with its notice |
| SDK start | `attachPositionProvider(binding.positionProvider)` | Once. The provider follows whichever session the binding holds, so a bind or an end needs no re-attach |
| **Connect** | `locationReadiness()`, then `bind(tagID:)` | The label is sent as typed; the relay-api resolves every label format |
| **End visit** | `end()` | The state becomes `.ended(.userEnded)` and the prompt is shown |

`stateChanges()` drives the screens. `WristbandStatus` shows the state of an
active session at the top of the map: **Connecting…**, **Online**,
**Reconnecting…** or **Signal lost** (the venue no longer hears the band). When a
session ends, `RootView` shows the prompt with one notice per
`BlueiotBindingEndReason`. For `.superseded`: "Your wristband was scanned by
another phone." The field holds the last label, so **Connect** binds the same
band again.

**Location before a bind.** The relay-api decides whether a bind needs the
phone's location (`/v1/meta`, `takeover_location_required`). The SDK never
shows a location dialog. Before a bind, `WristbandPrompt` reads
`locationReadiness()`:

| Readiness | The app |
| --- | --- |
| `.permissionNeeded`, authorization undetermined | Asks for *While Using the App* |
| `.permissionNeeded`, denied | Asks nothing. iOS shows no second dialog |
| `.preciseLocationNeeded` | Asks for temporary full accuracy with the purpose key `WristbandTakeover` (`NSLocationTemporaryUsageDescriptionDictionary` in `project.yml`) |
| `.ready`, `.notRequired` | Asks nothing |

The footer under the field states the dialog before **Connect** is tapped. The
bind is sent in every case: a band at the reception desk binds without a
location.

**Errors.** `WristbandCopy.message(for:)` maps each `BlueiotBindingError` to one
sentence, keyed on the case and never on the relay-api's English message:

| Error | Text |
| --- | --- |
| `.tagAlreadyBound` | This wristband is already in use. Please ask the staff. |
| `.notInAuthorizedZone(.rejectedByRelay)` | To take over this wristband, be inside the museum with location enabled, or ask at the reception desk. |
| `.notInAuthorizedZone` with another cause | One sentence per cause: no permission, approximate location, no fix in time, simulated location |
| `.tagNotAvailable` | This wristband is not active. Please ask the staff. |
| `.tagNotAtReception` | Connect this wristband at the reception desk. |
| `.tagNotIssued` | This wristband has not been issued yet. Please ask the staff. |
| `.rateLimited` | Too many attempts. Try again in N seconds. |
| `.appTokenRejected`, `.notARelayAPI` | Names the configuration key to check |

**Connecting another wristband.** Press and hold the map for 1.5 seconds and the
same prompt opens as a sheet. There is no visible control; for one,
`VenueMapScreen.isChangingWristband` is the single switch. A successful bind
replaces the current session; the map and the SDK keep running.

The same sheet lists the **map credits**. The map hides MapLibre's attribution ⓘ,
its logo and the compass (`.with(chrome: .bare)` on the `MapOptions` in
`VenueMapScreen`). Hiding the ⓘ moves the OpenStreetMap (ODbL) and MapLibre
credits into the app: they are `ProximiioMapSession.attributions`, and an app
that hides the ⓘ must show them somewhere reachable from the map. Here that is
the long-press sheet.

**Floor numbers.** The relay-api sends Proximi.io floor levels, mapped from the
venue engine's numbering on the relay side, and the floor id when it knows it.
The SDK resolves a level against the floors it synced. The app sets no floor
mapping.

**Background positioning.** Positioning continues when the screen locks. It
requires four settings, and each one missing has the same symptom: positioning
stops 30 seconds after backgrounding, as if the relay had disconnected.

| Setting | Where | Without it |
| --- | --- | --- |
| `relayOnly(token:runsInBackground: true)` | `Venue.configuration(token:)` | The SDK does not set `allowsBackgroundLocationUpdates` |
| `runsInBackground: true` on `BlueiotBindingConfiguration` | `VenueConfiguration.binding` | The SDK pauses the provider on backgrounding |
| `UIBackgroundModes: [location]` and `NSLocationWhenInUseUsageDescription` | `project.yml` | iOS does not honour the background location session |
| Location authorization, *While Using the App* | `LocationPrompt`, then `sdk.requestPermissions()` in `Venue.start` | CoreLocation runs no session |

`BlueiotMinimal/Info.plist` is generated from `project.yml`; change the two keys
there or lose them on the next `xcodegen generate`.

The app does not request Always authorization. A denial leaves the map working in
the foreground. The phone's location never enters the position: the venue's
anchors position the wristband. The location session keeps the process
scheduled, and a bind sends one fix when the relay-api needs it for a take-over.

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

**Route line.** `.with(routeLineStyle:)` on the `MapOptions` in `VenueMapScreen`
draws the route ahead as a gradient from `#3F69FF` at the visitor to `#ED3731`
at the destination, and the walked part in `#3F69FF` at 30 % opacity.

**Turn-by-turn.** `session.guidanceRules = .venueWalk` in `VenueMapScreen`
enables it; guidance is off by default. The map library then follows the route it
draws and republishes `session.guidance` on every fix; the bottom bar shows the
next manoeuvre, the metres left to it, and, once, that the visitor has arrived.
The instruction sentences belong to the app, in `GuidanceLine.instruction(for:)`,
because `RouteManoeuvre.Kind` carries no display strings.

`isOffRoute` becomes `true` after three fixes more than twelve metres from the
route and returns to `false` on the first fix back on it. The session does not
re-route. While it is `true` the bar reads "You have left the route." and shows
**New route from here**, which computes a new route to the same place from the
visitor's position (`GuidanceLine.offersReroute(for:)`). The app adds no detector
of its own. The instruction is one line; the app shows no step list.

Ending a visit hands the guidance back to this bar. `JourneyNavigator.end()` sets
`guidanceRules` to `nil`; `JourneyBar` calls it once, then `VenueMapScreen`
sets `.venueWalk` again. A second `end()` after that, from `onDisappear`, would
switch single-route guidance off, with no instruction and no off-route line.

**A visit.** The list button next to the search opens the same search sheet in
multi-select; the places tapped, in that order, become a `Journey`. Before the
visit starts, `JourneyBar` calls `proposeOrder(from: .visitor)` and applies the
result when it is shorter. The first place can move. The bar then says which
happened for 8 seconds: "Stops put in the shortest order: N m less to walk." or
"Your stops are already in the shortest order." Without a position the call
returns `nil`; the tap order is kept, the bar says the order is measured when the
position arrives, and the first fix runs the same call. On that fix the result
replaces the note for 8 seconds; without a result the note is cleared.
`StartOrder` holds the rule: no order is applied once a stop is reached, done or skipped, or a stop-off
is in the plan. A restored visit that has already started is not reordered. From
there `JourneyNavigator` owns every route computation: it draws and follows one
leg at a time through the map session.

The navigator does not re-route a visitor who leaves the leg:
`JourneyBar` sets `deviationPolicy = .askApp`, and the drawn leg stays until the
visitor answers a prompt on the bar. The prompt opens on three
`JourneyNavigator.events`: `farFromRoute`, `offRouteTooLong` and
`detourOverstayed`. `leftRoute` opens no prompt. The prompt closes on
`returnedToRoute`, on `journeyFinished`, on `detourEnded` for a detour prompt,
and when either button is tapped. `DeviationPrompt.after(_:showing:)` holds this
rule. The thresholds are the library defaults in `JourneyDeviationRules`; the app
sets none.

The bar shows the active stop, what is left (`overview.remainingStops.count`,
`overview.remainingMeters`, its ETA and any leg the router refused), and
**Continue** once the visitor has arrived. Arrival does not advance the journey;
the advance rule is `.manual`, and **Continue** calls `advance()`.

The plan is changed on the bar and in **Your visit**, the list button on the bar:

| Control | Effect |
| --- | --- |
| **Back to my route** | On the deviation prompt. Calls `resumeJourney()`: a live detour ends (reached → visited, otherwise dropped), the leg to the stop the plan is on is drawn from the visitor's position, and the deviation clears |
| **New route from here** | On the deviation prompt. Calls `replanFromHere()`: a live detour ends, the remaining stops are reordered from the visitor's position and the order is applied. The stop being walked to is not kept in place |
| **Stop off** | On the bar. See below |
| **Back to the plan** | On the bar during a stop-off. Calls `cancelDetour()`: the stop-off is dropped and the leg to the planned stop is drawn from the visitor's position |
| **+** | Opens the same multi-select search used to plan the visit. `JourneyNavigator.add` appends each pick after the remaining stops; the active leg is unchanged. A place the plan already holds is named on the sheet, not dropped. **+** is available when the visit is done too: adding makes the journey active again, and the new stop becomes the active one |
| **Drag** | Reorders the remaining stops. The rows are `JourneyNavigator.reorderableStops`, the array `move(stopID:toIndex:)` indexes into; the app holds no second copy of which stops may move |
| **Save N m by reordering** | `proposeOrder(from: .visitor)` measures a shorter order from the visitor's position and returns a proposal. The stop being walked to can move. Without a position the sheet uses `proposeOrder(from: .activeStop)`, which keeps the stop being walked to first. A tap applies the proposal. It is measured again when the remaining stops, their order, the live stop or the first fix change, because `apply` refuses a proposal after any of those changes. The **Order** row is shown whenever two or more stops can move: the button, "Your stops are already in the shortest order.", "Measuring the shortest order…" while measuring or while `canApply` is `false`, or "The order cannot be measured: a stop has no route." when `proposeOrder` returns `nil`. `OrderAdvice.of` holds the rule |
| **Show the whole plan on the map** | Sets `journeyOverlayStyle = .venue`, which draws the remaining legs under the active leg. Off by default |

**Stop off** is a short stop at the nearest place of one kind, such as toilets
or a café, before the planned stop. The menu lists each kind with the nearest
place of that kind, under "Go to the nearest one before *planned stop*. Your plan
continues afterwards." A pick calls `detour(to:)`, which inserts the stop-off
before the active stop and routes to it immediately. During the stop-off the
bar reads "Stop off: *place*" and says what follows: on the way, **Back to the
plan** cancels it; at the place, **Continue** records it and routes to the planned
stop from the visitor's position. `StopOff` holds the text. The menu is hidden
while no kind of place is named, and during a stop-off. The kinds of place come from the venue's amenity tags
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
SDK's own warnings, the notification authorization status at launch, each
wristband session state (`wristband: active, online`, `wristband: ended,
SUPERSEDED`), each geofence transition and whether it was notified, and
`scene: background` / `scene: foreground` as the app leaves and returns to the
screen. The file is
`Documents/proximiio-diagnostics/proximiio-diagnostics.log` in the app container.
If the log cannot be written, the app runs without one.

The log carries no credential. The SDK redacts the shapes it recognises (URL
userinfo, `token=` and `api_key=` query values, `Authorization: Bearer` and
`password:` assignments, JWTs, e-mail addresses) and, because
`VenueConfiguration.secrets` passes them in, the application token and the
relay-api app token wherever they appear. The app writes no wristband number. The log rotates at 2 MB, on open and never mid-session, and keeps one
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
has the dSYMs for the pinned versions (SDK 6.0.0-beta.52, map 6.0.0-beta.32) from
the GitHub source releases.

## Playing a journey through the sandbox relay-api

`scripts/journey-run.mjs` plays a journey drawn in MapTap into the Proximi.io
sandbox relay-api as one walker tag's positions. The app binds the walker's tag
as it binds a wristband, with no code change. The script calls the LiveView run
API at `https://live.proximi.fi`, the same API as the LiveView web page.

Prerequisites:

- Node 22 or later. The script has no dependencies.
- A LiveView login: a Proximi.io user account (email and password) of the app's
  organisation.
- `BLUEIOT_RELAY_URL` at the sandbox, `https://relay-api-sandbox.proximi.fi` (the
  default), and `BLUEIOT_RELAY_APP_TOKEN` set to the sandbox app token. The token
  comes from your Proximi.io contact.

```sh
node scripts/journey-run.mjs login --token-file ~/.liveview-token
node scripts/journey-run.mjs list --token-file ~/.liveview-token
node scripts/journey-run.mjs start <journey_id> --token-file ~/.liveview-token \
  --relay sandbox --ground-floor -1 --loop
node scripts/journey-run.mjs status --token-file ~/.liveview-token
node scripts/journey-run.mjs stop <run_id> --token-file ~/.liveview-token
```

| Command | Effect |
| --- | --- |
| `login` | Prompts for the email and the password, the password without echo. Exchanges them for a Proximi.io user token and writes it to `--token-file` with mode 0600. The token is not printed |
| `list` | The organisation's journeys: id, name, waypoint count |
| `start` | Starts a run and prints its run id, walker and tag id. `--walker N` selects the organisation's walker N on the relay; without it the lowest free walker is used. `--speed X` scales walking and dwelling. `--dry-run` prints the request and sends nothing |
| `status` | The organisation's runs, with state, walker and tag id |
| `stop` | Stops a run. `pause` and `resume` take a run id the same way |

The API accepts only a user token; an application token is refused with HTTP
403. `--ground-floor` is the venue engine's number for the ground floor, `-1`
for the museum; that is the default.

**Walker tag id.** Enter the walker's tag id in the app's wristband prompt.
LiveView's **Connect your app** card shows it for each walker; `start` and
`status` print it as `tag`. Walker tags are `900000000000` to `900000000099`. The
id of a walker does not change between runs. Press and hold the map for 1.5
seconds to connect another tag.

**Shared sandbox.** The sandbox relay-api is shared between organisations and
carries real wristbands next to the walkers. Bind only walker tags, or bands the
operator names for the test: a bind of a band another phone follows takes it
over. A looping run plays until it is stopped, for at most 12 hours, and is not
tied to a LiveView session. Stop it with `stop` after the test, and tap **End
visit** in the app.

**Zone rules.** The sandbox reports its rules in `/v1/meta`. While the operator
has reception and authorized zones drawn (`bind_reception_required: true`,
`takeover_location_required: true`):

- A first bind of a tag needs the tag inside the reception zone. Otherwise the
  bind fails with "Connect this wristband at the reception desk."
- A take-over of a tag another phone follows needs the phone's location inside
  the authorized zone. Otherwise it fails with "To take over this wristband, be
  inside the museum …".
- A rescan of the tag this phone already follows works anywhere.

With no zones drawn both flags are `false`, and any bind and take-over succeeds.

## Take-over test

A manual test of wristband take-over between two phones, or a phone and a
simulator. Both run this app against the same relay-api. Before the test, ask
the operator which tag to use, announce the run, and start a walker journey on
that tag (see above). In the steps, A and B are the two devices and `<tag>` is
the walker's tag id.

| Step | Action | Expected |
| --- | --- | --- |
| 1 | A: enter `<tag>`, tap **Connect** | A's status reads **Online**; the dot moves with the walker |
| 2 | B: enter the same `<tag>`, tap **Connect** | B reads **Online** and receives the positions. A shows the prompt with "Your wristband was scanned by another phone." and its dot stops |
| 3 | A: tap **Connect** (the field holds `<tag>`) | A reads **Online** again. B shows "Your wristband was scanned by another phone." |
| 4 | A: tap **End visit**, then confirm | A shows the prompt with "Your visit has ended." Neither device receives positions |

Notes:

- With the zones drawn, step 1 needs the walker inside the reception zone, and
  steps 2 and 3 need the taking device's location inside the authorized zone.
  Outside it, step 2 fails on B with the take-over message and A stays
  **Online**; that result is correct for the rules. A simulator location set
  through Xcode is marked as simulated; the relay-api can refuse it.
- A repeated failure within a short time can return "Too many attempts. Try again
  in N seconds." Wait for the stated time.
- The diagnostics log of each device records the session states, for example
  `wristband: ended, SUPERSEDED`.

## Playing a journey on the phone

Debug builds only. A journey drawn in MapTap is played on the phone in place of
the relay-api: `JourneyPlaybackProvider` generates the positions locally, with
no relay and no LiveView run. The code is inside `#if DEBUG`; Release, TestFlight
and App Store builds contain neither the picker nor the launch arguments.

**The picker.** The map shows a round button with a walking figure in the
top-left corner. The corner is the one the map leaves free: the floor picker is
on the right, and the search bar and `JourneyBar` are at the bottom. The button
opens a sheet that lists the organisation's journeys from `Proximiio.journeys()`,
in the API's order, with distance, duration, waypoint count and levels from
`ProximiioJourneyTimeline`. A journey that fails `validationFailure()` is listed
disabled, with the reason in red. Tapping a playable journey opens its options:
speed (1x, 2x or 5x) and loop. **Play** detaches the binding's provider and
attaches the playback.

**The controls.** While a journey plays, the button is replaced by a panel in the
same corner: the journey name, the elapsed and total time, pause or resume, and
stop. The panel reads the provider's `diagnostics` once a second and shows
**Finished** when a journey that does not loop reaches its last waypoint.
**Stop** detaches the playback and attaches the binding's provider again, as at
launch.

**Launch arguments.** The same playback starts at launch with arguments set in
the Xcode scheme or passed to `devicectl`:

| Argument | Effect |
| --- | --- |
| `-journeyPlayback <id>` | Fetches the journey with `fetchJourney(id:)` and plays it instead of attaching the binding's provider. The id is `<organisation uuid>:<uuid>` |
| `-journeySpeed <x>` | Optional. Journey seconds per real second, 0.5 to 10, default 1 |
| `-journeyLoop` | Optional. Starts again after the last waypoint |

A journey that cannot be fetched attaches nothing; the controls show the reason,
and **Stop** attaches the binding's provider. The picker and the launch arguments
attach the provider through the same `Venue.playJourney` call. The SDK starts
only with an active wristband session, so the launch arguments apply after the
first bind. A later bind does not change the playback.

Playback runs with the screen locked (`runsInBackground: true`), as the
binding's provider does. The diagnostics log records `journey playback: <name>, <speed>x`, with
`, looping` appended when the journey loops, or `journey playback failed: <reason>`.

## Tests

```sh
xcodebuild -project BlueiotMinimal.xcodeproj -scheme BlueiotMinimal \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Sixty-one tests in eleven classes. Each covers behaviour that fails without
anything on screen looking wrong. The views are not tested; a wrong layout is
visible.

| Class | Tests | Covers |
| --- | --- | --- |
| `WristbandCopyTests` | 7 | `WristbandCopy`: the message per bind error, the take-over refusal per location cause, the rate-limit wait, the notice per end reason, the status line per link and signal, and a log line without a tag id |
| `JourneyPersistenceTests` | 5 | `JourneyStore` round-trip with stop order and state, clearing, and a stored value that no longer decodes |
| `AmenityQueryTests` | 3 | `VenuePOI.nearestByAmenity(in:from:)`: the nearest place per amenity id, kinds taken from the venue data, untagged places kept as places |
| `MapTapTests` | 4 | `VenuePOI.place(under:in:)` against the feature ids `onFeatureTap` reports, including a tap that matches no place |
| `GeofenceNotificationTests` | 5 | `NotificationPrompt.note(name:entered:)` title, body and log line; the `.notDetermined` ask rule; the launch order; and the foreground presentation options |
| `BackgroundPositioningTests` | 2 | `LocationPrompt.isOwed(_:)` and `runsInBackground` on `Venue.configuration(token:)` |
| `DiagnosticsTests` | 1 | No configured secret reaches the log verbatim |
| `DeviationPromptTests` | 7 | `DeviationPrompt.after(_:showing:)`: the events that open, close and keep the deviation prompt, and its sentences |
| `VisitRulesTests` | 14 | `StartOrder`: when a new visit is ordered, the note on the bar, and that the waiting note is replaced or cleared once the first fix is handled. `OrderAdvice.of`, the stop-off text and `GuidanceLine.offersReroute(for:)`. Two library behaviours: `proposeOrder(from: .visitor)` returns `nil` without a fix, and `JourneyNavigator.end()` switches single-route guidance off |
| `JourneyPickerTests` | 6 | Debug builds only. Picker rows: playable and unplayable journeys, the `validationFailure()` reason, the summary, API order and journeys without an id; the loading, empty and error states; the number formats |
| `JourneyPlaybackSessionTests` | 7 | Debug builds only. The playback controls' states: start, pause, resume, finish, a failed fetch and stop; the launch arguments; the options' log line |
