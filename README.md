# Presenter

A free, open-source, macOS-native live presentation app for worship services, conferences, schools and live events. Live reliability comes first. The operator's view is kept strictly separate from what the audience sees.

**Status:** beta. The latest download is on the [Releases](https://github.com/alps2005/PresenterApp/releases) page. See [`PROJECT_PROPOSAL.md`](PROJECT_PROPOSAL.md) for the roadmap.

## Install

Download `Presenter-<version>.zip` from the [Releases](https://github.com/alps2005/PresenterApp/releases) page, unzip it and drag **Presenter** into **Applications**.

The app isn't notarized by Apple, so macOS blocks it the first time. To open it anyway:

1. Double-click Presenter, then click **Done** (or **Cancel**) on the warning.
2. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the Presenter message.
3. Confirm with your password. After that it opens normally.

On older macOS versions you can instead right-click Presenter in Applications and choose **Open**.

### Publishing a release

Push a version tag and GitHub Actions builds, tests and uploads the zip:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Every push and pull request to `develop` or `main` also runs the tests and a build (`.github/workflows/ci.yml`).

## Requirements

- macOS 14 Sonoma or later to run the app
- Xcode 26 or later to build it (CI uses Xcode 26.6)

## Build and run

### In Xcode

1. `git clone https://github.com/alps2005/PresenterApp.git`
2. Open `Presenter.xcodeproj`.
3. Select the **Presenter** scheme and **My Mac**, then press ⌘R.

The project is set to automatic signing with the original author's team. If you're building with your own Apple ID, open the **Presenter** target, go to **Signing & Capabilities**, and choose your own team (a free personal team works).

### From the command line

```sh
# Build the app without code signing
xcodebuild -project Presenter.xcodeproj -scheme Presenter -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

# Run it
open build/Build/Products/Debug/Presenter.app
```

### Run the tests

The presentation engine lives in a local Swift package and its tests run without opening any windows:

```sh
cd Packages/PresenterCore
swift test
```

## Using the app

| Action | How |
|---|---|
| Cue a slide (preview only, audience unaffected) | Click it |
| Take a slide live | Double-click it, press Return with the workspace focused, or ⌘Return |
| Next / previous slide (continues into the next or previous presentation) | → or Space / ←, with the workspace focused, or ⌥⌘→ / ⌥⌘← from anywhere |
| Clear the slide's words, keeping the background | ⌥⌘C (Clear Slide) |
| Clear the background, keeping the words | ⌥⌘X (Clear Background) |
| Clear both | ⌥⌘A (Clear All) |
| Blackout | ⌥⌘B |
| Restore after a clear or blackout | ⌥⌘R |
| Show/hide audience output | ⌥⌘O, or the **Output** toolbar menu |
| New presentation / new slide | ⌘N / ⇧⌘N |
| New song from pasted lyrics | ⌥⌘N, or **New Song…** under the playlist |
| Undo / redo the last edit | ⌘Z / ⇧⌘Z |
| Save now (the project also autosaves) | ⌘S |
| Open a project file / export a copy | ⌘O / ⇧⌘S |
| Edit a presentation in the slide editor | **Edit** next to its title; **Done** or Esc to return |
| Show/hide Quick Edit for the cued slide | ⌥⌘E, or the **Quick Edit** toolbar button |
| Bring back the operator window after closing it | ⌘0 (Window › Show Operator Window) |

**Audience output.** Choose **Show in Window** to rehearse on a single screen. With a second display connected, pick it under **Full Screen** to get a borderless output covering that display. Full-screen output is never offered on the display that shows the operator window. If the output display disconnects, the output hides and the toolbar shows a warning. It comes back automatically when that display reconnects.

**Undo.** ⌘Z undoes the last change to your slides and playlist, and ⇧⌘Z redoes it. Typing and dragging a slider undo in one step. While you're typing in a text field, ⌘Z undoes the typing first. Taking slides live, Clear and Blackout are never undone, so Undo can't change what the audience sees.

**Songs.** **New Song…** (⌥⌘N) takes pasted lyrics and makes one slide per stanza: a blank line starts a new slide. A line that's only a section name, such as *Verse 1*, *[Chorus]*, *Coro:*, *Verso 2*, *Puente* or *Bridge*, isn't shown on screen. Instead, it labels the slides after it with a coloured tag, which you can change in the slide editor's Format panel. **Lines per slide** splits long stanzas into slides of 2, 3 or 4 lines.

**Song tools.**
- **Reflow:** the **Reflow** button on a presentation (and in the slide editor) shows all its words as one document. Type, and the slides update as you go; they keep their style, and new slides copy the one before them. It uses the same format as New Song: a blank line starts a slide, and a section name (Verse 1, Coro…) labels the slides after it. ⌘Z undoes a run of typing in one step.
- **Arrangements:** for a song with group labels, the arrangement menu next to Add Slide sets the order the groups play in, like ProPresenter, e.g. *Verse 1 · Chorus · Verse 2 · Chorus · Bridge · Chorus*. A repeated chorus plays again without copying its slides. The workspace shows the slides in that order, and → / Space step through each repeat. **Slide Order** plays every slide once, in order.
- **Library:** under the playlist, the **Library** lists every presentation, including ones taken off the playlist. Click ⊕ (or double-click) to add one to the playlist; right-click to delete it.
- **Search:** the field above the playlist filters the playlist and the library by title and by the words on the slides. It ignores case and accents.
- **Thumbnail size:** the slider at the bottom right of the workspace sets the thumbnail size.
- **Renaming:** click a presentation's title to rename it.

**Stage display and timers.** A second output for the people on stage, which the audience never sees. It shows the live slide's words in large type, the next slide in yellow (with its group label), a clock, a timer, the slide's notes, and a message banner.
- **Turning it on:** Output menu › **Stage Display** (window or full screen on any display not already used), or ⌥⌘S. The audience output and stage display can't use the same screen, and both recover by themselves if their display is unplugged.
- **Show Controls** at the bottom of the Live panel:
  - **Timers:** start, pause and reset timers, or create new ones: a countdown (e.g. a 30-minute sermon), counting down to a time of day (e.g. service at 10:00), or counting up. A countdown past zero turns red. The ⋯ menu shows a timer on the stage display.
  - **Stage:** send a message to the stage (e.g. "5 minutes left"), and choose the timer, clock and notes shown on stage.
- **Notes:** the live slide's notes also appear under the Audience preview.

**Video backgrounds and the media bin.**
- **Media Bin:** the **Media** toolbar button (⌥⌘I) opens it under the workspace. **Import…** adds images and videos (MP4, MOV, M4V…); files that don't play are rejected.
- **Media cues:** click an item to put it straight on the audience output's background layer, behind the words on screen, like a ProPresenter media cue. Right-click to make it the background of the cued slide or of its presentation instead.
- **Video backgrounds:** a video plays on the background layer and keeps playing, without restarting, while transparent slides change the words over it. In the Background inspector, choose **Video** to pick one and set its fill, looping, mute and dimming.
- **Transport:** while a video is live, controls under the Audience preview play and pause it, scrub, show the time left, mute it and set the volume.
- **Missing files:** a missing or unplayable video shows the default background with a warning and never holds up slide changes.
- **File size:** exported projects include their videos, so they can be large.

**Messages and props.** Two more layers over the slides, managed from **Show Controls** in the Live panel:
- **Messages:** a bar across the bottom (or top) of the audience output, like "Parent of child {Number}, please come to the nursery". Words in braces are blanks you fill in when you click **Show…**, and `{timer:Sermon}` shows a live timer. Edit the text, position, size and colours from the ⋯ menu. One message shows at a time.
- **Props:** graphics that stay up across slides, such as a logo. Click a prop to show or hide it; several can be on at once. **New Prop** and **Edit Props…** open them in the slide editor, so they can hold text, shapes and images. Changes to a prop that is on screen wait until you hide it and show it again (its tile says EDITED).
- **Clearing:** Clear Messages (⌥⌘G) and Clear Props (⌥⌘P) are in the Clear button's menu. Clear All (⌥⌘A) clears every layer and Restore brings them back. Blackout hides everything.

**Layers and transparent backgrounds.** The audience output has two layers, like ProPresenter: a background, and the slide's words on top.
- **Opaque slides:** when a slide goes live, its background (colour or image) replaces the background on screen.
- **Transparent slides:** a slide whose background is **None** (shown as a checkerboard on thumbnails) only changes the words. Whatever background is already on screen stays.
- **Example:** give the first slide of a song an image and set the rest to None. The image stays up for the whole song, and a Dissolve fades only the words.
- **Clear per layer:** Clear Slide, Clear Background and Clear All work on the layers separately. The Clear button's arrow has all three.

**Editing is non-destructive.** Editing a live slide does not change what the audience sees until you take that slide live again. The Live panel warns you when this is the case.

**Saving.** The project saves itself about a second after each change, and again when you quit. If that last save fails, Presenter asks before quitting so you can export a copy first. It lives at `~/Library/Containers/<bundle id>/Data/Library/Application Support/Presenter/Project.json`. Nothing is ever live when the app starts.

- **Backups:** each time Presenter opens your project, it copies it to `Presenter/Backups/` (unless nothing changed since the last copy), keeping the newest 10.
- **Export Project…** writes a copy anywhere, e.g. to keep a backup or move it to another Mac. The copy includes the images and videos the project uses, so it opens complete on the other Mac.
- **Open Project…** replaces the current project with a file you pick. The current project is backed up to `Presenter/Backups/` first, and the audience output doesn't change.
- A project saved by a newer version of Presenter isn't opened by an older one; it's moved aside instead, so nothing in it is lost.
- If the project file can't be read at launch, it's renamed to `Project.unreadable-<number>.json` so it's never overwritten, and a sample project opens instead.

**Appearance.** The operator window is dark, with solid panels, so it stays readable in a dark booth. LIVE is always red, CUED always blue and warnings amber, and every state badge has an icon and a word. To use the system's light or dark setting instead, turn on **View › Follow System Appearance**.

**One continuous workspace.** The workspace shows every presentation in the playlist one after another, so you can scroll ahead to see what's coming. The sidebar highlights the first presentation whose title is in view, and clicking a sidebar item scrolls to it. When Next or Previous moves the live slide off screen, the workspace scrolls just enough to show it again. While you're typing a presentation title, Space and the arrow keys edit the title instead of changing slides.

**Slide editor.** **Edit** opens a presentation in a Keynote-style editor that fills the window:

- **Left:** slide thumbnails. Click to select, drag to reorder, right-click to take a slide live or delete it, **Add Slide** at the bottom.
- **Middle:** the slide. Click an item to select it, drag to move it, and drag the handles to resize. Double-click text to change the words; Esc finishes. The arrow keys nudge the selected item (with Shift, ten times as far).
  - **Alignment guides:** while you drag or resize, yellow guides appear when an item lines up with the slide's centre or edges, or with another item's centre or edges. Within a few points it snaps onto the line, and a tag shows its position (or size) in slide points. Hold ⌘ while dragging to place it freely.
  - **Copy, Cut, Paste** (⌘C / ⌘X / ⌘V) work on the selected item, even between slides and presentations. A paste that would land exactly on top of an item is nudged down and to the right. Text copied from another app pastes as a new text box.
  - **Duplicate** (⌘D) adds a copy just above and to the right. **Delete** (⌫ or ⌦) removes the selected item.
- **Toolbar:** **Done**, **Take Live**, **Add Slide**, **Text**, **Shape** (rectangle, rounded rectangle, oval), **Media** (an image from your Mac) and zoom (Fit, 25–200%).
- **Right, chosen with the toolbar's three buttons:**
  - **Format:** the selected item's settings: text style; shape, fill and border; or image scaling and opacity. Each also has position, size, stacking order and Delete. With nothing selected, it shows the slide's background and presenter notes.
  - **Animate:** the slide's transition: None, or a **Dissolve** of 0.2–2 seconds that cross-fades the audience output when the slide goes live. Clear and Blackout are always instant.
  - **Document:** the presentation's title and background.

The audience output keeps running while you edit, and edits don't reach it until a slide is taken live again. Build animations (moving text and shapes on and off a slide) and audio are coming in the next phase.

**Quick Edit.** For a fast fix during a service, cue a slide and press ⌥⌘E (or the **Quick Edit** toolbar button). A panel appears under the workspace with three tabs:

- **Text:** the slide's words.
- **Style:**
  - font, weight, italic, size, colour, alignment and shadow;
  - a 9-point **Position** grid with a margin slider, to place the text box;
  - **Reset Position**, which returns to the default centred layout;
  - **Apply to All Slides…**, which copies this slide's style and position to every slide in the presentation, leaving their text alone.
- **Background:** this slide's own colour or image. **Presentation** means it inherits the presentation's background.

The **Background** button next to each presentation's title sets the background for the whole presentation. Every slide that doesn't set its own background uses it.

Images are copied into the app's media folder (`~/Library/Containers/<bundle id>/Data/Library/Application Support/Presenter/Media`), so moving or deleting the original file doesn't break a slide. If a copy goes missing, slides show the default background and the editor and Live panel show a warning.

## Project layout

```text
Presenter.xcodeproj
Presenter/                     macOS app target (SwiftUI + AppKit)
  App/                         App entry point, delegate, menu commands, saving and opening projects
  DesignSystem/                Tokens, shared components and the solid "quiet native" chrome
  Features/Operator/           Operator window: playlist, continuous workspace, Quick Edit and inspectors, live panel, show controls, media bin
  Features/Editor/             Keynote-style slide editor: thumbnails, canvas, toolbar and Format/Animate/Document inspector
  Media/                       Media library (images decoded ahead of time) and video playback
  Outputs/                     Display discovery and the audience and stage display windows
  Rendering/                   Shared slide renderer and overlay layers (used for thumbnails, previews and outputs)
  Support/                     Logging and AppKit helpers
Packages/PresenterCore/        UI-free core, with unit tests: models, PresentationCoordinator, persistence (store,
                               archive, backups, loading), the media store, and output and playback decisions
docs/                          Architecture, decision records and release notes
```

`PresentationCoordinator` owns the project and the live state, and every change to what the audience sees goes through it. Video transport (play, pause, scrubbing, volume) and showing or hiding the output windows are handled by the app's playback controller and output manager. The coordinator keeps four ideas separate:

- **Selected:** the playlist item you're working on.
- **Cued:** the slide that will go live next time you take it.
- **Live:** a snapshot of what the audience currently sees.
- **Up next:** what Next will take live.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for more, and [CONTRIBUTING.md](CONTRIBUTING.md) to help out.

Logs use the subsystem `io.github.alps2005.Presenter` and can be viewed in Console.app.

## License

Copyright © 2026 Adrian Palma.

Presenter is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

Presenter is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the [GNU General Public License](LICENSE) for more details.

In short: anyone may use, study, share and change Presenter, but any version they distribute must also be free and open source under the GPL.
