> These rules govern every comment and the README in this repository. Verbatim copy of `docs/site/ANNINA-RULES.md` from the Proximi.io iOS SDK.

# Annina Rules

Use these instructions when rewriting existing Proximi.io documentation or
creating new documentation.

## Objective

Write concise technical documentation for developers. Explain the API and its
behaviour directly. Preserve the exact technical meaning.

Do not improve the text as literature. Do not add marketing language, narrative,
metaphors or dramatic transitions.

## Audience and publication scope

Classify the documentation as public or internal before deciding which details
to include. If the intended audience is unclear, establish it with the product
owner before publishing.

Public developer documentation includes supported integration steps, required
configuration, public API behaviour and information needed to operate or debug
the integration.

Keep implementation internals, unpublished modules, vendor wire protocols,
internal tuning constants, design rationale and source-code discrepancies in
internal documentation unless a public developer must act on them. A symbol
being public does not automatically make every implementation detail suitable
for public documentation.

For positioning features, public documentation should explain inputs, required
permissions, configuration, output and observable limitations. Keep algorithm
stages, filter internals, arbitration rules and tuning rationale internal unless
the developer can configure them or must account for them in the integration.

## Core rules

1. Start with what the API does.
2. State when the developer should use it.
3. State required inputs, defaults and prerequisites.
4. State lifecycle, failure and background behaviour when relevant.
5. Use short paragraphs and direct sentences.
6. Keep one main fact per sentence.
7. Prefer concrete API names, types and values over abstract descriptions.
8. Remove any sentence that does not help the developer implement, configure,
   debug or evaluate the feature.
9. Do not repeat information already clear from the code sample or table.
10. Do not change behaviour, terminology, defaults or API signatures to make the
    prose sound smoother.

## Tone

Use neutral technical English.

Use declarative technical headings and sentences. Avoid second-person scene
setting, jokes, metaphors and narrative transitions. Imperative instructions
are acceptable when they state a concrete integration step.

Write:

> Use this preset when positions come from a relay. It disables Eddystone
> scanning, iBeacon ranging, phone-native UWB and native location input.

Do not write:

> An app the venue positions has no use for the phone's own radios, but left at
> their defaults the SDK still brings them up. One preset removes all of it.

Avoid:

- marketing claims such as “powerful”, “seamless”, “robust” or “best-in-class”;
- literary phrases such as “the story”, “the answer”, “the shape of the data”,
  “what the API wants” or “what this buys you”;
- anthropomorphism such as “the SDK knows”, “the engine wants” or “the stream
  remembers”;
- rhetorical questions;
- conversational filler such as “worth noting”, “keep this in your head”,
  “as you might expect” or “the important thing is”;
- vague words such as “thing”, “magic”, “somehow”, “usually fine” or “etc.”;
- unexplained claims such as “safe”, “fast”, “reliable” or “correct”.

Use “setting” or “property”, never “knob”.

## Technical precision

Before writing, verify behaviour in the current source code. Documentation,
comments, old examples and task descriptions are supporting evidence, not the
source of truth.

Verify at least:

- public symbol names and signatures;
- default values;
- platform and permission requirements;
- stream start, stop and restart behaviour;
- buffering and error behaviour;
- foreground and background behaviour;
- units, coordinate order and floor handling;
- distinctions between similarly named systems.

If the source and existing documentation disagree, document the source behaviour
and report the discrepancy. Do not guess.


## Terminology

Use product and symbol names exactly:

- Write **BlueIoT** in prose.
- Preserve Swift spellings such as `BlueiotConfiguration` and
  `BlueiotPositionProvider` in code.
- Write **Proximi.io Portal**, not dashboard, console or admin tool unless a
  different product is specifically meant.
- Distinguish **venue-side RTLS** from positioning performed by the phone.
- Never use "storey", use "floor".

### UWB and BlueIoT

BlueIoT supports two venue-side positioning technologies:

- **BlueIoT AoA**: venue infrastructure computes the position from BLE angle of
  arrival.
- **BlueIoT UWB**: venue infrastructure ranges a dedicated UWB tag and computes
  its position.

Both are venue-side systems. The phone receives a computed position through a
relay or direct engine connection.

Do not confuse them with **phone-native UWB**, where the iPhone uses its U1/U2
chip and Nearby Interaction to range against compatible anchors.

The BLE phone-as-tag feature applies to BlueIoT AoA only. It does not turn the
phone into a BlueIoT UWB tag.

### Geofencing

The main geofencing path is always the Proximi.io SDK:

1. Define circular or polygonal geofences in Proximi.io Portal.
2. The SDK evaluates every published position, regardless of whether it came
   from BLE, phone-native UWB, relay-fed positioning or a direct RTLS provider.
3. Consume events through `sdk.geofenceEvents()`.
4. Geofence evaluation uses the resolved floor of the position.

Do not present venue-engine area events as an alternative that developers must
choose during normal geofence integration.

`RelayPositionProvider.geofenceEvents()` and
`BlueiotPositionProvider.geofenceEvents()` expose areas configured in the venue
vendor's system. Keep their integration guidance in internal documentation
unless a public integration explicitly requires these APIs. Do not mix their
setup into the main geofencing guide.

## Page structure

For a task-oriented guide, use only the sections that add useful information:

1. One-paragraph definition
2. When to use it
3. Minimal working example
4. Required configuration
5. Behaviour and lifecycle
6. Errors or limitations
7. Related reference links

For an API reference:

1. Exact declaration
2. Parameter or property table
3. Return value
4. Errors
5. Lifecycle or concurrency rules
6. One minimal example, only if the declaration is not sufficient

Do not add an introduction that only repeats the title. Do not add a conclusion
that only repeats the page.

## Code samples

- Show the smallest complete sample that demonstrates the API.
- Use real public symbols and valid call order.
- Do not hide required setup behind comments.
- Comments should explain non-obvious constraints, not narrate each line.
- Do not introduce helper functions unless their purpose is immediately clear.
- Keep error handling realistic but proportionate to the example.

## Tables and notes

Use a table for repeated fields such as settings, defaults and effects.

Use notes only for information that would cause an incorrect implementation if
missed. Use warnings only for data loss, privacy, security, permission or
irreversible behaviour.

Do not use notes to add secondary commentary or repeat surrounding prose.

## Rewriting procedure

When rewriting an existing page:

1. Identify every factual claim.
2. Verify unstable or implementation-specific claims in source.
3. Remove repetition, scene-setting and persuasion.
4. Replace indirect explanations with explicit behaviour.
5. Separate normal integration from advanced or vendor-specific behaviour.
6. Preserve useful anchors and public API coverage.
7. Check terminology across related pages.
8. Build the documentation in strict mode and run the link checker.

Do not assume that every shipping public symbol needs a public guide. Apply the
audience and publication-scope rules first. Move internal or advanced material
to internal documentation and keep public pages focused on supported customer
workflows.

## Final review

Before finishing, confirm:

- Can a developer find the correct API without comparing parallel systems?
- Is every detail appropriate for the page's public or internal audience?
- Does every paragraph contain implementation-relevant information?
- Are defaults, units, permissions, floors and lifecycle behaviour explicit?
- Are BlueIoT AoA, BlueIoT UWB and phone-native UWB clearly separated?
- Does the main geofence path use `sdk.geofenceEvents()`?
- Are advanced venue-engine events kept outside the main geofence flow?
- Are all code samples consistent with the current source?
- Are headings, descriptions, links and anchors valid?
- Can any sentence be removed without losing technical information? If yes,
  remove it.

## Task prompt

Apply Annina Rules to the documentation in scope.

If rewriting, preserve the technical meaning while making the text shorter and
more direct. If generating new documentation, derive behaviour from the current
source and use the page structures above.

Change documentation only unless the task explicitly includes source changes.
Report technical inconsistencies instead of modifying source code. Build in
strict mode, run the link checker, and list the pages changed with a one-line
summary of each change.
