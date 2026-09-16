# Proximi.io Blueiot — minimal reference app

A complete venue app in 1475 lines of Swift across thirteen files. It asks
for the visitor's wristband number once, shows the venue map, searches the
venue's places, routes to the one they pick, says which turn to take next, notes
the places they enter and leave, and walks a whole afternoon of them in order — added to, reordered and detoured from
as the afternoon goes, with the phone in a pocket as often as not. The visitor is
positioned by the venue's own Blueiot anchors, through the Proximi.io cloud relay
— the phone scans nothing.

It exists to be read. Every file is short enough to read in one sitting, and the
comments mark the seams where your own product's code goes.

## What it deliberately is NOT

No settings screen. No diagnostics. No staff mode, no engine switches, no event
log, no offline package, no step list. Nothing reorders
a visit on its own. Those all exist and are all deliberate omissions — every
knob is a thing you would have to read, decide about and maintain.

If you want an instrument that shows all of them at once, that is the full demo
app (`proximiio-blueiot-ios`), which is a field-debugging tool for the Proximi.io
team rather than a starting point for a product.

Positioning does carry on with the phone in a pocket or the screen locked. What
that asks of a visitor is one location prompt, and one for notifications the first
time there is one to show; what it asks of you is under **In a pocket** and
**Geofence notifications** below.

## Fill in the configuration

Three values, all build-time, none editable at runtime:

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
$EDITOR Config/Secrets.xcconfig
```

| Key | What it is |
| --- | --- |
| `PROXIMIIO_APPLICATION_TOKEN` | Your Proximi.io application token (dashboard → organisation → Application token) |
| `BLUEIOT_CLOUD_RELAY_URL` | The Proximi.io cloud relay carrying this venue's wristband positions. A bare host is enough |
| `BLUEIOT_CLOUD_RELAY_TOKEN` | That relay's stream token, sent as `Authorization: Bearer` |

`Config/Secrets.xcconfig` is gitignored and is the only place a real *credential*
may live. `Config/App.xcconfig` is tracked, leaves those three empty and
`#include?`s your copy last, so what you set wins. It does carry one non-secret
survey value — see **Floor numbers** below. With any key empty the app still builds and runs, and
says on screen which key is missing.

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
`project.yml` — the same artefacts a customer resolves. There are no local
package paths.

## Where things are

| File | What it owns |
| --- | --- |
| `App/BlueiotMinimalApp.swift` | The order of things: wristband → location → SDK → map |
| `App/VenueConfiguration.swift` | The three build-time values |
| `Venue/WristbandID.swift` | The one spelling rule for a band id, and where it is stored |
| `Venue/Venue.swift` | Starting the SDK, attaching the cloud relay to one band, and a note per geofence |
| `Venue/VenuePOI.swift` | Turning the venue's features into searchable places |
| `UI/WristbandPrompt.swift` | The first thing the app asks a person for, and the map credits |
| `UI/LocationPrompt.swift` | The other one, and the rule for when it is shown |
| `UI/NotificationPrompt.swift` | The third, asked mid-visit: the rule for when, and the words on a note |
| `Venue/JourneyStore.swift` | Keeping a visit across launches, and turning a picked place into a stop |
| `UI/VenueMapScreen.swift` | Map, search button, route, and where a visit starts |
| `UI/POISearchSheet.swift` | The search list — one place, or several |
| `UI/GuidanceLine.swift` | The turn-by-turn sentence, in this app's English |
| `UI/JourneyBar.swift` | The visit: the stop in hand, the plan, adding to it, detours, reordering |
| `Assets.xcassets/AppIcon.appiconset` | The app icon — a **placeholder**, see below |

**The icon is a placeholder.** `AppIcon-1024.png` is a flat Proximi.io stand-in
that says so on its face; it is there because App Store validation refuses an
archive without an icon (no 120 px iPhone icon, no 152 px iPad icon, no
`CFBundleIconName`), not because anyone chose it. Replace that one file with your
product's 1024×1024 PNG — opaque, sRGB, square corners; iOS masks it — and keep
the name, or update `Contents.json` next to it. Xcode derives every other size
from it; nothing else in the project refers to the image.

## Two things worth knowing before you change anything

**Changing the wristband.** A returning visitor is never asked again, but the
number can be changed without reinstalling: **press and hold the map for 1.5
seconds** and the same prompt comes back as a sheet. There is deliberately no
visible control — a visitor never needs it, and staff are told once. If your
product wants a visible one, `VenueMapScreen.isChangingWristband` is the single
switch.

The same sheet lists the **map credits**. The map hides MapLibre's attribution ⓘ
(`.with(chrome: .bare)` on the `MapOptions` in `VenueMapScreen`), and hiding it
moves the OpenStreetMap (ODbL) and MapLibre credits into the app: they are
`ProximiioMapSession.attributions`, and an app that hides the ⓘ must show them
somewhere reachable from the map — here, behind the long press.

**Floor numbers.** The relay reports the venue engine's floor numbers, and the
SDK turns them into Proximi.io floor ids on its own: an engine floor number *is*
a Proximi.io floor level, and the SDK already syncs every floor with its level.
The app passes no mapping table — passing one would switch that derivation off —
and a number the venue has no floor for is logged rather than quietly drawn on a
blank level.

One integer is left, in `Config/App.xcconfig`, because it is the one thing the
SDK cannot know:

| Key | What it is |
| --- | --- |
| `BLUEIOT_GROUND_FLOOR_NO` | Which floor number the engine calls the ground floor. Proximi.io calls it level `0`; Blueiot LocalSense venues usually start at `1`, and this one does. Empty = `0`, and then this key is not needed at all |

It is the venue's survey rather than a credential, so it is tracked with this
venue's working value, and it goes away the day the deployment is renumbered.

**In a pocket.** Positioning carries on when the screen locks, and it takes four
things — all four, because each one missing looks the same: the dot stops 30
seconds after backgrounding, as if the relay had died. Two are code, in
`Venue.swift`: `relayOnly(token:runsInBackground: true)` for the SDK, and
`runsInBackground: true` on the relay provider's configuration, without which the
SDK pauses the provider on its own. Two are in `project.yml` and must survive your
edits: `UIBackgroundModes: [location]`, which is what lets iOS keep the process
running off screen, and `NSLocationWhenInUseUsageDescription`, the sentence iOS
shows when the app asks. `Info.plist` is generated from that file, so change them
there or lose them on the next `xcodegen generate`.

The fourth is the visitor's: with location never granted, CoreLocation runs no
session and iOS suspends the app at its 30-second grace period — so
`LocationPrompt` asks once, between the wristband and the map, and iOS's own
prompt follows. *While Using the App* is all it needs; nothing asks for Always. A
refusal is not asked about again, and the map still works on screen. The phone's
location never enters the position — the venue's anchors place the wristband; the
location session is only what keeps the process scheduled.

**Geofence notifications.** Every geofence the wristband enters or leaves is a
local notification — on screen or in a pocket, because the location mode above
already keeps the process alive, and a local notification needs no background
mode and no purpose string of its own. The geofences are the ones drawn in the
Proximi.io Portal: `authenticate()` syncs them, the SDK's engine decides the
transitions with its own enter/exit tolerance (the app adds no policy of its own),
and `Venue.announceGeofences` turns each one into one note. The prompt for them is
not on the launch path: `NotificationPrompt` comes up over the map on the first
transition that would have shown a note, and iOS's own prompt follows; a first
transition that arrives with the phone in a pocket leaves the card waiting for the
next time the app is on screen, and whatever iOS is told, nobody is asked again.
Each transition is also a line in the diagnostics log — `geofence enter · Lobby ·
notified`, or `· not authorized`.

**Turn-by-turn.** `session.guidanceRules = .venueWalk` in `VenueMapScreen` is the
whole opt-in. The map library then follows the route it is already drawing and
republishes `session.guidance` on every fix; the bottom bar shows the turn in
hand, the metres still to walk to it, and — plainly, once — that the visitor has
arrived. The instruction sentences are the app's, in `VenueMapScreen.instruction(for:)`,
because `RouteManoeuvre.Kind` carries no display strings and no library should
choose a venue's language for it.

Leaving the route is reported, not acted on: `isOffRoute` latches after three
fixes beyond twelve metres and clears itself on the first fix back inside, so the
bar says so and this app adds no detector and no re-routing of its own.

**A visit.** The list button next to the search opens the same search sheet in
multi-select; the places tapped, in that order, become a `Journey`. From there
`JourneyNavigator` owns every route computation in the walk — it draws and
follows one leg at a time through the same session the map is already using, and
re-routes a leg by itself when the visitor wanders, which a single route does not
do.

The bar shows the stop in hand, what is left (`overview.remainingMeters`, its
ETA, and any leg routing refused), and **Continue** when the visitor has arrived.
Arrival does not advance on its own: somebody stands in front of an exhibit for a
length of time nobody can guess, so the rule is `.manual`.

**Your visit** — the list button on the bar — is where the plan is changed, and
it does four things:

| | |
| --- | --- |
| **+** | Opens the same multi-select search the visit was planned in, and `JourneyNavigator.add` puts each pick after everything still to be walked. The leg in hand is left alone. A place the plan already holds is named on the sheet rather than dropped without a word. The **+** is there when the visit is done too: adding revives it, and the new stop becomes the one being walked to |
| **Drag** | Reorders what is still ahead. The rows *are* `JourneyNavigator.reorderableStops` — the array `move(stopID:toIndex:)` indexes into — so the app holds no second copy of which stops may move |
| **Save N m by reordering** | A shorter order, measured. The library never applies one and neither does the sheet; a tap does. It is re-measured whenever the stops change, because `apply` ignores a proposal that no longer describes the journey |
| **Show the whole plan on the map** | Draws the rest of the afternoon under the leg in hand. Off by default |

"Stop off" is a detour. Which kinds of place a venue has is read off the venue's
own amenity tags rather than from a list of categories in this app, and what each
kind is *called* comes from the SDK's amenity store — `amenities()` once per
install, then `amenity(id:)`, which is a local row read. The app keeps no titles
of its own, so an amenity renamed on the server is renamed here without a release.

The visit is written to `UserDefaults` whenever it changes and restored on
launch, so an afternoon survives the app being closed — `Journey` is `Codable`
and each stop carries its own state.

**Following the visitor.** The button at the right of the bottom bar recentres
the map on the wristband. It is one call into the map library's own follow camera
(`ProximiioMapSession.recentre()` plus `followMyFloor()`) — this app writes no
camera of its own. Panning, pinching or rotating the map releases the follow; the
library notices the hand and publishes it through `ProximiioMapSession.cameraMode`,
which is what fills or hollows the button's symbol.

## The diagnostics log

From its first statement (`BlueiotMinimalApp.init`, and the comment there on why
it must be first) the app has the SDK write down everything positioning sees —
fixes, floors, the relay coming and going, the SDK's own warnings, each geofence
crossed and whether it was notified, and `scene:
background` / `scene: foreground` as the app leaves and returns to the screen —
in `Documents/proximiio-diagnostics/proximiio-diagnostics.log` inside the app's
container. When something goes wrong that nobody can reproduce, Proximi.io
support may ask for that folder; on a development build, Xcode's Devices and
Simulators window downloads the container.

Nothing in it is a credential. The SDK strips the shapes it knows — bearer
tokens, `token=` values, JWTs, passwords in URLs, e-mail addresses — and, because
`VenueConfiguration.secrets` hands them over, the application token and the relay
token wherever and however they appear. The wristband number is written; it is
printed on the band. The log rotates at 2 MB on the next launch, keeping one
previous generation, and an export is capped at 10 MB.

Crash logs from a TestFlight build symbolicate this app's own code; the
`MapLibre`, `ProximiioBinary` and `ProximiioMapBinary` frameworks are SwiftPM
binary targets whose dSYMs are not in the archive by design (App Store Connect
says "Upload Symbols Failed" for each — expected), and Proximi.io support has them
for the pinned versions (SDK 6.0.0-beta.40, map 6.0.0-beta.13), from the GitHub
source releases.

## Tests

```sh
xcodebuild -project BlueiotMinimal.xcodeproj -scheme BlueiotMinimal \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Twenty-three of them, and all six subjects are chosen for the same reason: they
fail without anything on screen looking wrong. A wristband read one way by the
app and another way by the relay matches nothing, and the symptom is a dot that
never arrives. A visit that does not survive a launch loses a visitor's afternoon
in silence. An amenity query that reads the venue's data wrongly makes a venue
with toilets look like a venue without any. A background flag left at its default,
or a location ask that nags or never fires, stops the dot thirty seconds after the
screen locks. A credential written into the diagnostics log verbatim travels with
every export. A note that says *arrived* on the way out, or a notification ask
that fires on launch and spends iOS's one prompt, is wrong the same silent way.
The screens are not tested; a layout that is wrong is a layout you
can see.
