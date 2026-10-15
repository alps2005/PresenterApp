# Presenter architecture

Presenter is a macOS app with two parts. Its only dependencies are Apple's frameworks; there are no third-party
packages.

| Part | Where | What it holds |
|---|---|---|
| **PresenterCore** | `Packages/PresenterCore`, a local Swift package | Everything that can be decided without UI: models, the presentation coordinator, persistence, media storage, and output and playback decisions. Fully unit tested (`swift test`). |
| **The app** | `Presenter/` | SwiftUI and AppKit: windows, views, rendering, output windows, AVFoundation playback, and the design system. Kept thin: it shows state, sends commands to the core, and carries out the core's decisions. |

## The one rule: live state goes through the coordinator

`PresentationCoordinator` (`@MainActor`, `@Observable`) owns the project and the live state. Views observe it and
call its commands. Commands return `CommandResult`: `.applied`, or `.rejected(reason)`, which the operator sees.

It keeps four ideas separate (`PresentationState`):
- **Selected:** the playlist item the operator is looking at.
- **Cued:** the slide that goes live next time the operator takes it (the preview).
- **Live:** a *snapshot* of what the audience sees. Later edits never leak to the output until the slide is taken
  live again.
- **Up next:** what Next would take live, following playlist order and arrangements.

### Undo

- **Edits are undoable.** Each one runs inside `recordingUndo`, which keeps a snapshot of the project from before
  the edit. Typing and slider drags coalesce into one step.
- **Live commands are never recorded,** so undo can't change the audience output: Take Live, Clear, Blackout,
  media cues, messages, props and timers.
- **Media is append-only:** undo keeps imported assets.

### Where the commands are

The coordinator is split by area into extensions in `Packages/PresenterCore/Sources/PresenterCore/Coordinator/`:

| File | Commands |
|---|---|
| `PresentationCoordinator.swift` | Stored state, init, derived queries (`audienceScene`, `upNextSlide`…), shared helpers |
| `+Live.swift` | Select, cue, Take Live, next/previous, Clear, Blackout, Restore |
| `+Layers.swift` | Media cues on the background layer, live video mute, messages, props on screen |
| `+ShowControls.swift` | Timers, the stage message, and the message, prop, timer and stage-settings libraries |
| `+Library.swift` | Presentations, playlist, songs, Reflow, arrangements |
| `+Editing.swift` | Text formatting, backgrounds, media assets, elements, slide order, transitions, notes |
| `+Undo.swift` | The undo engine and `replaceProject` |

**Not routed through the coordinator:** video transport (play/pause, scrubbing, volume) and showing or hiding the
output windows. Those are playback and window state, not presentation state. Video *mute* does go through the
coordinator (`setLiveVideoMuted`), because it's part of the live background.

## The audience output

What the audience sees is built from layers, like ProPresenter:
1. **Background:** `state.liveBackground`, a colour, an image or a video. A slide with a transparent background
   leaves the background that's already on screen.
2. **Slide:** the live slide's text, shapes and images.
3. **Props:** graphics that stay up across slides.
4. **Message:** a bar along the top or bottom.

Blackout covers all four.

- **Data:** `PresentationCoordinator.audienceScene` describes the background and slide layers, and `audienceProps`
  / `audienceMessage` describe the layers over them.
- **Drawing:** the app's `SlideRenderView` and `OverlayLayers` draw them, and the same views draw the operator's
  previews, so they always match.
- **Audience window:** `AudienceOutputView` cross-fades the background and slide layers separately, so a
  background that stays never fades.
- **Stage display:** `StageOutputView` shows the live words, the next slide, a clock, a timer, notes and the
  stage message. The audience never sees it.

### Placing the output windows

`OutputPlanner` (core) decides where each output goes:
- It never puts an output on the operator's display, or on the display the other output fills.
- When a display disconnects, it hides that output, and brings it back when the display reconnects.

`OutputManager` (app) reports the displays and the operator's commands to the planner, then places one
`OutputWindowController` per output as `placement(_:)` says. The windows belong to `OutputManager`, not to any
SwiftUI view, so they outlive the operator window.

### Video

`MediaPlaybackController` (app) owns the one `AVQueuePlayer`. It follows `state.liveBackground`, and
`PlaybackPlan.decide` (core) says whether to stop, keep playing, reload, load or report a missing file. So a video
keeps playing, without restarting, while transparent slides change the words over it.

## Persistence

| Type | Job |
|---|---|
| `ProjectStore` | Reads and writes `Project.json` atomically. It checks `schemaVersion` first, so a file from a newer version is reported as newer rather than corrupt. |
| `ProjectLoader` | Chooses the project at launch: the saved one; or the sample if nothing is saved; or, if the file can't be read, moves it aside (`Project.unreadable-<time>.json`) and opens the sample. |
| `ProjectBackups` | Dated copies in `Backups/`: one at launch (skipped when unchanged) and one before Open replaces the project. Keeps the newest 10. |
| `ProjectArchive` | Export and Open: the project plus the media files it uses, in one JSON file. The app runs it off the main thread. |
| `MediaStore` / `MediaLibrary` | Imported media is copied into `Media/`, named by UUID. `MediaLibrary` (app) decodes images ahead of time. |

- **Autosave:** `ProjectPersistence` (app) saves about a second after each change and again on quit. If the save
  on quit fails, it asks before quitting.
- **Format versions:** `ProjectDocument.currentSchemaVersion` is the file format version.
  - New fields decode with defaults, so older files load and are saved back at the current version.
  - Bump it whenever a release adds or changes a saved field. An older build then moves the newer file aside
    instead of dropping fields it doesn't know and saving over it.
  - The doc comment lists what each version added.

All app data lives in the sandbox container: `~/Library/Containers/<bundle id>/Data/Library/Application
Support/Presenter/`.

## The design system

`Presenter/DesignSystem` holds the operator UI's tokens (`Spacing`, `Radius`, `Palette`, `Typography`), its shared
components (`StateBadge`, `tileFrame`, `WarningLabel`, `RowCard`, `RowMenuButton`, `PanelHeader`, `PopoverForm`) and
`QuietChrome`, which turns Liquid Glass down where Presenter controls it. The reasons are in
[ADR 0001: Quiet native design](adr/0001-quiet-native-design.md).

## Testing

- **Core:** the tests in `Packages/PresenterCore/Tests` cover the models, every coordinator command, undo,
  persistence and migration, backups, snapping, output placement and playback decisions. Clocks (`now`) and
  folders are injected, so the tests are deterministic.
- **App:** the app target has no tests of its own. Logic worth testing moves into the core.
- **CI:** `.github/workflows/ci.yml` runs the core tests and a Debug build on every push and pull request to
  `develop` and `main`. `release.yml` builds the universal, ad-hoc-signed app when a version tag is pushed.
