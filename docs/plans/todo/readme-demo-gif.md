# Reproducible README demo GIF

> **Implementation ready for visual inspection (2026-09-22).** The chosen scenes are Peter Rabbit
> at `7451058775928492912_14838-h-0.htm.xhtml#img_images_peter19.jpg` and
> `38533_overlay_preview.webpub` at `38533-0004-generic.xhtml#uwlh00026`. The generated default is a
> bezel-framed 720 × 1504, 10 fps, 16-second GIF; pass `--no-bezel` for the masked simulator
> framebuffer alone. The same run also produces three 720 × 480 capability stills: EPUB theme
> controls, synchronized narration highlighting, and a split Time Machine PDF / Nota comic view.
> The comic capture targets `50272-0002-generic.xhtml#hix00001` so it lands on the page art rather
> than the heading-only pagination slice.

**Type:** Documentation / example-app tooling

**Primary platform:** iOS Simulator

**Estimated effort:** M

**Output:** one generated README GIF, one poster image, and a reproducible capture command

## Goal

Add a short, polished README demo that shows the plugin doing real work in the example app. The
demo must be reproducible from programmatic code: a dedicated integration-test-style scenario
drives the app, the simulator records the full framebuffer, and `ffmpeg` produces the checked-in
GIF.

This is a showcase, not a regression suite. It should use the real plugin, reader, fixtures, and
example-app controls, but make only the assertions needed to keep a failed or half-loaded capture
from being published.

## Intended README result

The README hero should contain:

1. the package badges and one-sentence product promise;
2. one inline portrait demo GIF;
3. a short capability line and links to Quick Start, the example app, and API documentation;
4. optional static screenshots for capabilities that do not fit the hero GIF, such as PDF and
   audiobook playback.

The GIF should answer one question immediately: **what does this plugin let a Flutter app do?** It
should not try to document the UI or enumerate every supported format.

## Editorial direction

- Capture the actual example app and native Readium view. Do not recreate the reader in HTML or
  animate still screenshots to imply behavior that was not recorded.
- Prefer one coherent visual story. Use at most two source fixtures in the final GIF; more cuts will
  read as a feature-list montage at README size.
- Skip covers, front matter, and sparse opening pages. Navigate directly to a deliberately chosen,
  content-rich locator before recording begins.
- Keep controls and transitions visible long enough to understand, but remove loading, fixture
  selection, debug output, and setup from the final cut.
- Do not add narration or music to the GIF. Motion, playback state, and synchronized highlighting
  must make the feature legible without sound.
- Keep the master recording so the GIF can be regenerated at a different size or palette without
  rerunning the simulator, but do not commit temporary captures by default.

## Fixture candidates

All Nota fixtures are cleared for public README use. The final choice still needs a short visual
audition because source structure and feature coverage do not predict how well a page reads in a
narrow capture.

### Option A — illustrated EPUB: `peter_rabbit.epub`

**Use for:** the everyday reading experience, typography/theme changes, pagination, image handling,
and a static user highlight.

- Title: *The Tale of Peter Rabbit*.
- Advantages:
  - English, immediately recognizable, and visually rich;
  - many interior illustrations rather than a text-only test document;
  - already identified by `FixtureKeys.peterRabbitEpub` and bundled by the existing fixture build;
  - the package metadata identifies the source as Project Gutenberg.
- Risks:
  - most story content is in one large spine resource, so exact pagination may shift with simulator,
    font, and preference changes;
  - its default first page includes Project Gutenberg boilerplate and must not be used as the demo
    start.
- Candidate start:
  - `7451058775928492912_14838-h-0.htm.xhtml#pgepubid00000`, followed by a small deterministic
    progression adjustment if the title page is still too sparse;
  - also audition the text/image groups around `img_images_peter19.jpg`,
    `img_images_peter24.jpg`, and `img_images_peter43.jpg`.
- Recommendation: **best default for the first scene**, provided the audition finds a page where
  the illustration and surrounding text remain readable after the theme and font changes.

For a future Web capture, use `test-peter-rabbit.webpub`. It is a compact synthetic WebPub derived
from the same material, but its single short page is less representative than the native EPUB and
should not replace the native hero without comparing both.

### Option B — synchronized read-along: `38533_overlay_preview.webpub`

**Use for:** Media Overlay playback, moving text highlighting, playback controls, and visible
text/audio synchronization.

- Title: *De nye læsere*.
- Advantages:
  - bundled local audio; no network dependency;
  - a moving highlight communicates synchronized narration even in a silent GIF;
  - already covered by integration fixtures on native and Web;
  - demonstrates a capability that is difficult to communicate with a static screenshot.
- Risks:
  - text-only pages are less visually rich than an illustrated EPUB or comic;
  - early reading-order items are title/edition/colophon material and are poor demo content;
  - highlight movement depends on cue length, so the selected cue must change within the clip without
    flashing too quickly.
- Candidate start:
  - reading-order item 4, `38533-0004-generic.xhtml#uwlh00026` (`INDLEDNING`);
  - prefer the cue beginning at `#uwlh00027`, whose duration is long enough to register visually;
  - also audition a later locator in item 6 (`BAGGRUND`) on native if the item-4 paragraphs do not
    fill the viewport well. Item 4 remains the cross-platform-safe choice because the trimmed Web
    fixture includes the first four reading-order items.
- Recommendation: **best second scene if the GIF emphasizes accessibility and synchronized
  narration**.

### Option C — narrated comic: `50272-nota-comics.webpub`

**Use for:** visually distinctive comic reading, synchronized narration, automatic page/panel
framing, and the plugin's richer publication support.

- Title: *Når tegneserien bliver digital*.
- Advantages:
  - strongest visual impact of the current fixture set;
  - motion within the page can demonstrate behavior that no feature matrix conveys;
  - differentiates the plugin from a basic EPUB webview.
- Risks:
  - framing behavior is more complex and therefore more sensitive to the exact starting cue;
  - a panel transition that is clear on a phone may be too subtle after GIF downscaling;
  - the opening item is only a few seconds long and must be skipped.
- Candidate start:
  - audition reading-order item 2 (`Side 1`) and item 3 (`Side 2`);
  - choose a cue with an obvious pan or framing change within a 5–6 second window;
  - do not start on the cover/title reading-order item.
- Recommendation: **best second scene if the GIF emphasizes visual breadth and a memorable “magic
  moment.”** Prefer it over Option B only if the panel motion remains obvious in the compressed GIF.

### Option D — reflowable automation fallback: `712199_ebook.epub`

**Use for:** reliable typography, navigation, search, and decoration capture if Peter Rabbit's large
resource causes unstable pagination.

- Title: *De nye læsere*.
- Advantages:
  - the existing integration-test workhorse;
  - eight small spine documents make direct chapter navigation cheap and stable;
  - already used for preference, navigation, search, and decoration tests.
- Risks:
  - primarily text and less visually distinctive;
  - the opening resources are sparse front matter.
- Candidate start:
  - reading-order item 6 (`NYE VEJE TIL LÆSNING`) or item 7 (`DE NYE LÆSERE`), selected after
    inspecting the rendered page at the capture viewport.
- Recommendation: **fallback, not the first artistic choice**.

### Fixtures not proposed for the hero GIF

- `time_machine.pdf`: useful as a static capability screenshot, but a PDF page and settings change
  do not provide a strong short animation.
- `38533.audiobook`: useful as a static screenshot of the time-based controls. In a silent GIF the
  most important behavior is not visible.
- `test-fixed-layout.webpub`: deterministic but intentionally sparse and synthetic.
- remote audiobook fixtures: excluded because the result would depend on network and service
  availability.

## Fixture audition and selection gate

Do not implement the final storyboard against the first fixture that opens successfully. First make
6–8 second unpolished captures of Options A–C at their candidate locators, using the same simulator,
viewport, and output width planned for the final GIF.

Score each candidate from 1–5 on:

| Criterion | Weight | Question |
| --- | ---: | --- |
| Readability after compression | 30% | Can text, highlighting, and page motion be understood at README width? |
| Feature clarity | 25% | Is the demonstrated capability recognizable without a caption or sound? |
| Visual interest | 20% | Does the clip reward attention in the first two seconds? |
| Determinism | 15% | Can the same locator and action produce materially the same clip repeatedly? |
| Capture simplicity | 10% | Can the scene avoid coordinate taps, network access, and platform timing guesses? |

Save the audition clips as temporary artifacts, not committed files. Produce a contact sheet or a
short side-by-side preview for the fixture-selection review.

Selection rule:

- choose one primary scene if it scores at least 4/5 for both readability and feature clarity;
- add one secondary scene only when it demonstrates a materially different capability and the
  combined GIF remains at or below the size and duration budgets;
- if no animated scene survives compression, use the Peter Rabbit preferences scene as the GIF and
  move Media Overlay/comic coverage into static screenshots or a linked MP4.

## Baseline storyboard

The baseline assumes Option A wins the primary slot and either Option B or C wins the secondary
slot. The exact locator and the secondary choice are intentionally finalized only after the audition.

### Scene 1 — adaptable EPUB reading (Peter Rabbit, 9 seconds)

| Time | Action | What the frame should communicate |
| ---: | --- | --- |
| 0.0–1.5 s | Hold on the preselected story page with controls unobtrusive. | A real, readable illustrated EPUB is open. |
| 1.5–2.1 s | Open visual reader settings. | Reader behavior is configurable from Flutter UI. |
| 2.1–3.4 s | Show the text controls, then make one visible font-size adjustment. | Typography updates the native reader live. |
| 3.4–4.0 s | Switch to the Theme section. | Transition, not a second feature explanation. |
| 4.0–5.0 s | Select the warm light/teal preset that best preserves the illustration. | Theme and text colors update together. |
| 5.0–5.5 s | Close settings. | Return focus to content. |
| 5.5–7.3 s | Hold the restyled page, then advance exactly one page. | Pagination remains fluid after preferences change. |
| 7.3–9.0 s | Hold on a strong text/image composition. | Give the viewer time to register the result. |

Do not automate native text selection for this first version. Widget-test finders cannot interact
reliably with the native reader's selection UI, and coordinate long-presses would make the capture
fragile. If a user highlight materially improves the scene, apply a known decoration through the
plugin API after the page settles and label the transition honestly in accompanying README text; do
not simulate a selection gesture that did not occur.

### Scene 2B — synchronized read-along (Media Overlay, 6–7 seconds)

| Time | Action | What the frame should communicate |
| ---: | --- | --- |
| 0.0–1.0 s | Hold on the preselected `INDLEDNING` locator. | New publication/feature is visually established. |
| 1.0–1.4 s | Start playback from the chosen cue. | The standard playback control changes state. |
| 1.4–5.8 s | Let at least one highlight transition occur. | Text and bundled narration stay synchronized. |
| 5.8–6.6 s | Pause and hold. | End on a stable highlighted page. |

If the first cue is only a heading, prepare at `#uwlh00027` before capture instead of recording a
slow seek from the title.

### Scene 2C — narrated comic (alternative, 6–7 seconds)

| Time | Action | What the frame should communicate |
| ---: | --- | --- |
| 0.0–1.0 s | Hold on the selected `Side 1` or `Side 2` cue. | Establish the comic page. |
| 1.0–5.8 s | Play through one obvious framing/pan transition. | Narration can drive visual comic navigation. |
| 5.8–6.6 s | Pause on the destination panel. | Let the final composition settle. |

### Composite and duration

- Default final duration: 15–17 seconds.
- Use a hard cut or 150–200 ms dissolve between fixtures. Longer transitions waste the very small
  GIF budget.
- Do not add a logo/end card; the surrounding README already supplies the project name and calls to
  action.
- If only Scene 1 survives audition, ship a focused 9–11 second GIF rather than padding it.

## Capture architecture

### 1. Dedicated showcase target

Add a standalone target such as:

```text
flutter_readium/example/integration_test/readme_demo_test.dart
```

It must not be imported by `plugin_integration_test.dart` or run as part of the normal integration
suite. The target may reuse:

- `test_fixtures.dart` for fixture identifiers and platform-aware paths;
- `ReadiumIntegrationHarness` helpers for opening publications and waiting for locators;
- the real example-app Blocs, `PlayerPage`, `ReaderWidget`, settings sheets, and controls.

Use a small demo bootstrap around the real example widgets to:

1. reset demo state without erasing the whole simulator;
2. open the selected fixture;
3. compute an initial `Locator` from the selected reading-order link/fragment;
4. mount the reader and wait until its first locator/status is available;
5. show a stable ready frame;
6. emit a `README_DEMO_READY:<scene>` marker;
7. perform the timed actions;
8. emit `README_DEMO_DONE:<scene>`.

The test may drive ordinary Flutter controls through `WidgetTester`. Direct plugin calls are allowed
for setup that a user should not have to watch, especially selecting the initial locator. The visible
part of a settings scene should still use the actual example-app controls.

Add `ValueKey<String>` values only where semantic lookup is currently ambiguous. Prefer keys or
tooltips; do not add coordinate taps. Likely additions are:

- the visual-settings action;
- individual theme swatches, not only the enclosing `ToggleButtons`;
- the Text/Layout/Theme segmented-control choices;
- play/pause if the tooltip changes make lookup inconvenient.

### 2. Minimal assertions and waits

The showcase target should fail only when it cannot produce a truthful clip. Keep these checks:

- the selected fixture path exists in the generated fixture map;
- `openPublication` succeeds;
- the target reading-order item or locator exists;
- the mounted reader emits an initial locator or ready status before `README_DEMO_READY`;
- a preference action completes before the next visible beat;
- playback scenes reach a time-based state with a current locator before their hold begins;
- no unexpected Flutter exception is pending when the scene emits `README_DEMO_DONE`.

Do not add:

- pixel/golden comparisons;
- assertions for exact pagination, line wrapping, or highlight geometry;
- broad API regression checks already covered elsewhere;
- assertions for every intermediate UI state;
- fixed sleeps as substitutes for readiness. Fixed durations are appropriate only for the deliberate
  on-screen holds after readiness is known.

### 3. Host-side capture orchestrator

Add:

```text
bin/generate_readme_demo
```

Responsibilities:

1. verify required commands (`flutter`, `xcrun`, `ffmpeg`, and ImageMagick when the default bezel is
   enabled) and a suitable booted iOS Simulator;
2. verify generated fixtures exist, and tell the user to run `bin/fetch_test_resources` if not;
3. build/run only the dedicated showcase target;
4. stream test output so the process never appears hung;
5. start full-frame recording when `README_DEMO_READY:<scene>` appears;
6. stop recording after `README_DEMO_DONE:<scene>`;
7. fail if either marker, the test process, or the raw recording is missing;
8. trim the stable lead/trail holds, concatenate the selected scenes, and generate the output assets;
9. print the final duration, dimensions, frame rate, and byte size.

Use `xcrun simctl io <udid> recordVideo` rather than Flutter screenshots. The reader is a native
platform view, so Flutter-layer or Marionette screenshots cannot be trusted to contain all reader
content.

The recorder/test rendezvous deliberately uses log markers plus a 1–2 second stable hold after
`READY`. Starting the recorder after the app is fully loaded avoids capturing build, launch, fixture
copy, or spinner time. The final trim removes most of the handshake hold while retaining a calm first
frame.

### 4. Stable simulator presentation

The generator should either select a booted simulator or accept `--device-id`. Record in
portrait and normalize presentation before capture:

- fixed logical device size;
- light system appearance unless the scene itself changes reader theme;
- status bar time `9:41`, full battery, and stable network indicators;
- no keyboard, pointer, debug banner, accessibility inspector, or host notifications;
- app state reset by the demo bootstrap rather than a destructive simulator erase.

The final renderer adds a deterministic physical-device bezel by default. `--no-bezel` omits that
frame while retaining the simulator's status bar, Dynamic Island, and rounded screen mask.

Do not silently create or delete simulators. If no suitable simulator is booted, print the expected
setup and stop.

## Encoding and asset contract

Keep the high-quality intermediate as H.264 MP4 in a temporary/output directory. Generate the GIF
with a two-pass palette (`palettegen` + `paletteuse`) and fixed parameters.

Target contract:

| Property | Target |
| --- | --- |
| Orientation | Portrait |
| GIF width | 640–720 px after audition |
| Frame rate | 10–12 fps |
| Duration | 15–17 s maximum; 9–11 s for a single scene |
| Colors | 128 or 256, chosen by visual comparison |
| GIF size | preferred ≤ 5 MiB; hard ceiling 8 MiB |
| Looping | infinite, with a 1.0–1.5 s stable final hold |
| Poster | PNG or WebP from the strongest stable frame |

Suggested checked-in paths:

```text
docs/assets/readme/flutter-readium-demo.gif
docs/assets/readme/flutter-readium-demo-poster.png
docs/assets/readme/capability-reading.png
docs/assets/readme/capability-listening.png
docs/assets/readme/capability-rich-formats.png
```

Keep raw scene recordings and palette files out of Git. Add a narrow ignore entry for the generator's
working directory rather than ignoring general media types.

The script must print a warning and leave the previous checked-in GIF untouched when generation or
size validation fails. Generate into a temporary directory and replace the destination only after
all checks pass.

## README changes after the asset is approved

Update both public entry points deliberately:

- repository README: `README.md`;
- pub.dev package README: `flutter_readium/README.md`.

Use the same opening promise, demo, alt text, and capability summary in both. While doing this work,
also reconcile their currently divergent format/feature claims. Decide whether the package README
uses a repository-hosted absolute asset URL or includes the media in the published package; do not
accidentally add several megabytes to the pub package.

Suggested alt text:

> flutter_readium example app changing EPUB reading preferences and demonstrating synchronized
> reading or narrated comic navigation.

The text immediately below the GIF must name the demonstrated features so the README remains useful
when animation is disabled or the image cannot load.

## Implementation phases

### Phase 1 — audition

1. Build the existing fixtures from `readium-test-resources`.
2. Add a temporary/direct-locator capture path without polishing the final driver.
3. Capture Options A–C at the candidate locations.
4. Downscale and encode them with the intended GIF settings.
5. Score them and choose:
   - primary fixture and exact locator;
   - optional secondary fixture and exact cue;
   - final theme preset and font-size adjustment;
   - single-scene or two-scene duration.
6. Record the decision and selected locators in this plan before implementing the permanent runner.

### Phase 2 — reproducible runner

1. Add the standalone showcase target and only the keys it needs.
2. Implement readiness waits and `READY`/`DONE` markers.
3. Implement `bin/generate_readme_demo` and syntax-check it with `bash -n`.
4. Run the generator twice from the same checkout and compare duration, dimensions, and the visual
   sequence. Byte-for-byte equality is not required because video encoders and simulator rendering
   can vary; the scene order and timing should be materially stable.

### Phase 3 — editorial pass

1. Review the generated GIF at its actual README display width, not only full size.
2. Remove any beat that cannot be understood without explanation.
3. Tune crop, palette, frame rate, and holds to meet the file-size target.
4. Check that no debug text, local paths, notification banners, or personal data appear.
5. Obtain approval for the final fixture choice and cut before checking in the binary.

### Phase 4 — README integration

1. Add the approved GIF/poster.
2. Rewrite and synchronize the two README introductions.
3. Keep detailed platform setup below the visual Quick Start.
4. Verify the rendered repository README and a local/pub-package rendering path.
5. Confirm the package archive size before publishing-related changes are accepted.

## Verification

Required for the implementation:

1. `bash -n bin/generate_readme_demo`.
2. Run the generator against the chosen simulator and fixtures.
3. Run `ffprobe`/`ffmpeg` checks for dimensions, duration, and frame rate; check GIF byte size.
4. Open the GIF and watch at least two complete loops at the intended README width.
5. Confirm the first frame is immediately meaningful and the loop boundary is not a flash.
6. Run `bin/format` and `bin/analyze` for Dart changes.
7. Run the dedicated showcase target once without recording to ensure a recorder failure is not
   hiding a driver failure.
8. Render both README files and confirm the asset URL/path works in both contexts.

Normal integration suites do not need to run merely because the capture target changes, unless the
implementation also modifies shared example-app behavior. If shared widgets or Blocs change, run the
relevant existing integration group in addition to the showcase target.

## Acceptance criteria

- One documented command regenerates the demo from existing generated fixtures.
- The final GIF contains only real example-app/plugin output captured from a simulator.
- The chosen fixture and initial locator are recorded in the permanent showcase target.
- Loading/setup time and uninteresting front matter are absent from the final cut.
- The sequence is understandable without audio and at README display width.
- The GIF meets the duration and size ceilings and ends on a stable frame.
- The showcase target contains only readiness/truthfulness assertions, not a duplicate regression
  suite.
- The repository and package README introductions agree on current feature/format support.
- Temporary videos, frames, and palettes are not committed.

## Out of scope

- automatically committing regenerated binaries from CI;
- recording remote/network-dependent publications;
- making native text selection controllable solely for the GIF;
- building a general-purpose video production framework;
- replacing the existing integration-test suite with the showcase target;
- claiming pixel-identical output across Xcode, simulator runtime, font, or Flutter upgrades.
