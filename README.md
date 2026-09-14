# Proximi.io Blueiot — minimal reference app

A complete venue app in 1235 lines of Swift across eleven files. It asks
for the visitor's wristband number once, shows the venue map, searches the
venue's places, routes to the one they pick, says which turn to take next, and
walks a whole afternoon of them in order. The visitor is positioned by the
venue's own Blueiot anchors, through the Proximi.io cloud relay — the phone scans
nothing.

It exists to be read. Every file is short enough to read in one sitting, and the
comments mark the seams where your own product's code goes.

## What it deliberately is NOT

No settings screen. No diagnostics. No staff mode, no engine switches, no event
log, no offline package, no step list, no notification prompts, no
background positioning. Nothing reorders a visit on its own. Those all exist and are all deliberate omissions — every
knob is a thing you would have to read, decide about and maintain.

If you want an instrument that shows all of them at once, that is the full demo
app (`proximiio-blueiot-ios`), which is a field-debugging tool for the Proximi.io
team rather than a starting point for a product.

Foreground only. Positioning stops when the app is backgrounded; the SDK supports
keeping it alive (`ProximiioConfiguration.relayOnly(token:runsInBackground:)` plus
the `location` background mode), and this app deliberately does not.

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
| `App/BlueiotMinimalApp.swift` | The order of things: wristband → SDK → map |
| `App/VenueConfiguration.swift` | The three build-time values |
| `Venue/WristbandID.swift` | The one spelling rule for a band id, and where it is stored |
| `Venue/Venue.swift` | Starting the SDK and attaching the cloud relay to one band |
| `Venue/VenuePOI.swift` | Turning the venue's features into searchable places |
| `UI/WristbandPrompt.swift` | The only thing the app asks a person for |
| `Venue/JourneyStore.swift` | Keeping a visit across launches, and turning a picked place into a stop |
| `UI/VenueMapScreen.swift` | Map, search button, route, and where a visit starts |
| `UI/POISearchSheet.swift` | The search list — one place, or several |
| `UI/GuidanceLine.swift` | The turn-by-turn sentence, in this app's English |
| `UI/JourneyBar.swift` | The visit: the stop in hand, the plan, detours, reordering |

## Two things worth knowing before you change anything

**Changing the wristband.** A returning visitor is never asked again, but the
number can be changed without reinstalling: **press and hold the map for 1.5
seconds** and the same prompt comes back as a sheet. There is deliberately no
visible control — a visitor never needs it, and staff are told once. If your
product wants a visible one, `VenueMapScreen.onChangeWristband` is the single
call site.

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
length of time nobody can guess, so the rule is `.manual`. The plan sheet is
drag-to-reorder, and it will offer a shorter order — measured, with the metres it
saves — but the library never applies one and neither does the sheet; a tap does.
"Stop off" is a detour, and which kinds of place a venue has is read off the
venue's own amenity tags rather than from a list of categories in this app.

The visit is written to `UserDefaults` whenever it changes and restored on
launch, so an afternoon survives the app being closed — `Journey` is `Codable`
and each stop carries its own state. Drawing the whole plan under the leg in hand
is a toggle in the plan sheet, off by default.

**Following the visitor.** The button at the right of the bottom bar recentres
the map on the wristband. It is one call into the map library's own follow camera
(`ProximiioMapSession.recentre()` plus `followMyFloor()`) — this app writes no
camera of its own. Panning, pinching or rotating the map releases the follow; the
library notices the hand and publishes it through `ProximiioMapSession.cameraMode`,
which is what fills or hollows the button's symbol.

## Tests

```sh
xcodebuild -project BlueiotMinimal.xcodeproj -scheme BlueiotMinimal \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Seventeen of them, and all three subjects are chosen for the same reason: they
fail without anything on screen looking wrong. A wristband read one way by the
app and another way by the relay matches nothing, and the symptom is a dot that
never arrives. A visit that does not survive a launch loses a visitor's afternoon
in silence. An amenity query that reads the venue's data wrongly makes a venue
with toilets look like a venue without any. The screens are not tested; a layout
that is wrong is a layout you can see.
