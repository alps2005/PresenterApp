# Presenter

A free, open-source, macOS-native live presentation app for worship services, conferences, schools and live events. Live reliability comes first. The operator's view is kept strictly separate from what the audience sees.

**Status:** 1.2. The latest download is on the [Releases](https://github.com/alps2005/PresenterApp/releases) page, and from 1.2 on Presenter updates itself. See [`PROJECT_PROPOSAL.md`](PROJECT_PROPOSAL.md) for the roadmap.

## Install

Download `Presenter-<version>.dmg` from the [Releases](https://github.com/alps2005/PresenterApp/releases) page, open it, drag **Presenter** onto the **Applications** shortcut, then eject the disk image. Run Presenter from Applications, not from the disk image: a copy run from there can't update itself.

The app isn't notarized by Apple, so macOS blocks it the first time. To open it anyway:

1. Double-click Presenter, then click **Done** (or **Cancel**) on the warning.
2. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the Presenter message.
3. Confirm with your password. After that it opens normally.

On older macOS versions you can instead right-click Presenter in Applications and choose **Open**.

### Updating

From 1.2 on, Presenter updates itself. It checks GitHub once a day (it asks the first time whether it may), and **Presenter › Check for Updates…** checks now. It shows what's new and asks before installing; then it restarts as the new version, with no new security prompt. It never interrupts a service: while anything is live or an output is on, it only shows a quiet "Update to…" item in the Presenter menu and the welcome window, and an update you accept waits until nothing is live. **Settings…** (⌘,) turns the daily check off.

Updates are signed: Presenter only installs one signed with the project's private key, so a tampered download is refused.

### Publishing a release

Push a version tag and GitHub Actions builds, tests and uploads the DMG, with a signed update feed (`appcast.xml`) that installed copies check:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Every push and pull request to `develop` or `main` also runs the tests and a build (`.github/workflows/ci.yml`).

The release needs the repository secret `SPARKLE_ED_PRIVATE_KEY` (the update signing key; its public half is `SPARKLE_PUBLIC_ED_KEY` in the project). Write the release notes in `docs/release-notes/<tag>.md` first: they're shown in the update window, without their "Install" section. **Actions › Release › Run workflow** does a dry run that builds and signs everything and keeps the files, without publishing. Tags with a suffix (`v1.3.0-beta.1`) become pre-releases, which are never offered as updates.

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
| Import song files | ⇧⌘I (File › Import Songs…) |
| Undo / redo the last edit | ⌘Z / ⇧⌘Z |
| Save now (the project also autosaves) | ⌘S |
| Open a project file / export a copy | ⌘O / ⇧⌘S |
| Edit a presentation in the slide editor | **Edit** next to its title; **Done** or Esc to return |
| Show/hide Quick Edit for the cued slide | ⌥⌘E, or the **Quick Edit** toolbar button |
| Open another show, or make one | ⇧⌘O (File › Shows…) |
| Show/hide the audio bin | ⌥⌘U, or the **Audio** toolbar button |
| Stop the audio (fading it out) | **Stop** under the Audience preview, or Live › Stop Audio |
| Bring back the operator window after closing it | ⌘0 (Window › Show Operator Window) |
| Open the welcome window again | ⇧⌘1 (Window › Welcome to Presenter) |

**Audience output.** Choose **Show in Window** to rehearse on a single screen. With a second display connected, pick it under **Full Screen** to get a borderless output covering that display. Full-screen output is never offered on the display that shows the operator window. If the output display disconnects, the output hides and the toolbar shows a warning. It comes back automatically when that display reconnects. Presenter remembers each output's screen on this Mac: at the next launch the audience output and stage display open where they were, found by the display's serial number (or make, model and name) even if macOS gives it a new ID. If that display isn't connected yet, the output waits for it.

**Second output and looks.** A second audience output (Output menu › **Second Output**, or the toolbar's Output menu) shows the same slides on another screen, for a livestream or a lobby TV. Each audience output has a **Look…** (in its section of the toolbar's Output menu) that chooses what it shows, with a live preview: the background, the slide, props and messages can each be left out; without its background an output shows black or a **key colour** (green, so a video mixer can put the words over a camera); and **Words** can restyle the slide's text in another theme, e.g. a lower third for the stream. Words formatted by hand keep their look. Looks are saved on this Mac, like the screens. Blackout blacks out every output. The Live panel's Audience preview always shows everything.

**Undo.** ⌘Z undoes the last change to your slides and playlist, and ⇧⌘Z redoes it. Typing and dragging a slider undo in one step. While you're typing in a text field, ⌘Z undoes the typing first. Taking slides live, Clear and Blackout are never undone, so Undo can't change what the audience sees.

**Songs.** **New Song…** (⌥⌘N) takes pasted lyrics and makes one slide per stanza: a blank line starts a new slide. A line that's only a section name, such as *Verse 1*, *[Chorus]*, *Coro:*, *Verso 2*, *Puente* or *Bridge*, isn't shown on screen. Instead, it labels the slides after it with a coloured tag, which you can change in the slide editor's Format panel. **Lines per slide** splits long stanzas into slides of 2, 3 or 4 lines.

**Importing songs.** **File › Import Songs…** (⇧⌘I) reads song files, several at once, and lists each song with its writers and slide count, or says why a file couldn't be read, before anything is added. Imported songs go into the library and the open show, as one step to undo.
- **Formats:** OpenLyrics (.xml, from OpenLP and others), ChordPro (.cho, .chordpro, .chopro, .pro), SongSelect's lyrics (.txt) and SongPro (.usr) downloads, and plain lyrics in any text file (typed as for New Song). Chords are left out.
- **Sections and order:** sections become labelled groups (Verse 1, Chorus…). If the file gives a singing order (OpenLyrics' verse order, or ChordPro's `{chorus}`), the song gets a **Song Order** arrangement that plays.
- **Credits:** writers, copyright and the CCLI song number are kept with the song, for your licence reports. See or change them in the slide editor under **Document › Song**.

**Scripture.** **Scripture…** (⌥⌘V, or the sidebar) adds a Bible passage to the show as text slides.
- **Reference or words:** type a reference in English or Spanish, like *Juan 3:16-18*, *1 Co 13:4-7*, *Jn 3:16*, *Salmo 23* or *Mateo 5:3-12; 6:9-13*, or search for words and click a verse. Accents and capitals don't matter.
- **Slides:** choose 1 to 4 verses per slide, with or without small verse numbers and the reference ("Juan 3:16-17 · RVR1909") on each slide. A long verse is split at a sentence or clause. New passages follow the **Scripture** theme: verses at the top left, the reference small at the bottom.
- **Bibles:** Presenter doesn't include or download any. **Import Bible…** reads Zefania, OSIS and USFX XML files, and USX Bibles (choose the Bible's folder, or all its book files; a Digital Bible Library bundle's `metadata.xml` names the translation). These are the free formats public-domain and open translations are shared in. The [open-bibles](https://github.com/seven1m/open-bibles) collection has several, including the King James Version (OSIS); [eBible.org](https://ebible.org) shares the World English Bible and many others as USFX and USX; and the Zefania XML Bible project shares Zefania files on SourceForge. Check each translation's license first: use only public-domain or freely licensed ones.
- Imported Bibles are kept in `Application Support/Presenter/Bibles`, outside the project; the slides are ordinary text, so a project never needs the Bible file.

**Song tools.**
- **Reflow:** the **Reflow** button on a presentation (and in the slide editor) shows all its words as one document. Type, and the slides update as you go; they keep their style, and new slides copy the one before them. It uses the same format as New Song: a blank line starts a slide, and a section name (Verse 1, Coro…) labels the slides after it. ⌘Z undoes a run of typing in one step.
- **Arrangements:** for a song with group labels, the arrangement menu next to Add Slide sets the order the groups play in, like ProPresenter, e.g. *Verse 1 · Chorus · Verse 2 · Chorus · Bridge · Chorus*. A repeated chorus plays again without copying its slides. The workspace shows the slides in that order, and → / Space step through each repeat. **Slide Order** plays every slide once, in order.
- **Library:** under the playlist, the **Library** lists every presentation, including ones taken off the playlist. Click one to look through its slides in the workspace, where **Edit** opens it in the slide editor and **Add to Show** adds it to the playlist. Click ⊕ (or double-click it, or press Return) to add it straight away; right-click to delete it.
- **Show name:** right-click the show's name at the top of the sidebar and choose **Rename Show…**. The window title shows it.
- **Search:** the field above the playlist filters the playlist and the library by title and by the words on the slides. It ignores case and accents.
- **Thumbnail size:** the slider at the bottom right of the workspace sets the thumbnail size.
- **Renaming:** click a presentation's title to rename it.

**Moving on by itself.** Like ProPresenter, slides can advance without anyone pressing → or Space.
- **Slideshow:** the **Slideshow** button in a presentation's header moves through every slide after the chosen time (5, 8, 10, 15 or 30 seconds, or **Custom…**) and starts again from the first after the last. Good for announcement loops before the service.
- **Go To Next Timer:** right-click a slide and choose **Go To Next Timer…** (or use **Go To Next** in the slide editor) to give that slide its own time; it comes before the Slideshow's. **Loop to the first slide** goes back to the presentation's first slide; without it, the last slide moves on to the next item in the show, as → does, and stops at the end of the show.
- **Videos:** a slide whose video background plays once (Loop off) waits for the video to end before its countdown starts, so 0 seconds moves on the moment it finishes. A looping video doesn't hold the slide up.
- **Seeing it:** slides that move on by themselves show their time under the thumbnail; the live one fills a small red circle as it counts down, and the Live panel shows **Next slide in…** with a **Stop** button (Live › Stop Auto-Advance, ⌥⌘.). Pressing → or ←, or taking another slide live, starts that slide's own countdown. Clear and Blackout stop it; Restore starts it again.

**Stage display and timers.** A second output for the people on stage, which the audience never sees. It shows the live slide's words in large type, the next slide in yellow (with its group label), a clock, a timer, the slide's notes, and a message banner.
- **Turning it on:** Output menu › **Stage Display** (window or full screen on any display not already used), or ⌥⌘S. The audience output and stage display can't use the same screen, and both recover by themselves if their display is unplugged.
- **Show Controls** at the bottom of the Live panel:
  - **Timers:** start, pause and reset timers, or create new ones: a countdown (e.g. a 30-minute sermon), counting down to a time of day (e.g. service at 10:00), or counting up. A countdown past zero turns red. The ⋯ menu shows a timer on the stage display.
  - **Stage:** send a message to the stage (e.g. "5 minutes left"), choose the stage layout, and the timer shown on stage (with the standard look, also the clock and notes).
- **Stage layouts:** besides the standard look, a project starts with three layouts: **Lyrics** (big words and what's next, for singers and the band), **Speaker** (clock, timer and notes) and **Slides** (the live and next slides as pictures). Choose one in the Stage tab; **Edit…** opens the layout editor, where you make, copy and delete layouts and drag and resize their regions on a live preview (snapping to edges and centres; hold ⌘ to place freely). A region shows the live or next words, the live or next slide, the clock, a timer, the notes, the stage message, or fixed text, with its own text size, colour and alignment.
- **Live timers in slides:** type `{timer:Sermon}`, `{clock}` or `{clock:seconds}` in a slide's words (or use **Live Values › Insert** in the slide editor) and the audience output, its preview and the stage display show the running value. Other words in braces stay as typed, so lyrics are safe. Thumbnails and the editor show what you typed.
- **Notes:** the live slide's notes also appear under the Audience preview.

**Shows and the library.** A project holds one library of presentations and any number of shows. A show is a playlist: a Sunday service, a midweek meeting, Easter. All shows use the same library, so editing a song changes it in every show that has it.
- **Welcome window:** Presenter opens with it, before the operator window. It lists the shows with the open one first, then the most recently opened. Double-click one (or select it and press Return) to open it and start presenting. **New Show** makes one (its arrow also duplicates the selected show), **Import Songs…** and **Open Project…** go straight to those, and right-click renames, duplicates or deletes a show. Its close button quits Presenter, unless something is live or an output is on: then it goes back to the operator window. Untick **Show this window when Presenter opens** to start in the operator window instead. Window › **Welcome to Presenter** (⇧⌘1) opens it again; then closing it just closes it.
- **Shows sheet:** **File › Shows…** (⇧⌘O) lists the same shows over the operator window, for switching quickly during a service.
- **Opening a show** never changes the audience output. What's live stays on screen until you take a slide live, and Undo starts afresh.
- **Folders:** **New Folder…** in the Library makes a folder. Drag presentations onto it, or right-click one and choose **Move To**. Dragging one onto the **Library** header takes it out of its folder. Deleting a folder keeps its presentations: they move to the top of the library.
- **Deleting a presentation** removes it from the library and from every show.

**Audio.**
- **Audio bin:** the **Audio** toolbar button (⌥⌘U) opens it under the workspace. **Import…** adds music and sounds (MP3, M4A, WAV, AIFF…); files that don't play are rejected. Click a track to play it for the audience. Right-click to loop it, to play it when the cued slide goes live, or to make it the soundtrack of the cued slide's presentation.
- **Slide audio:** in the slide editor's Format tab, with nothing selected, **Audio** sets what happens when the slide is taken live: leave the audio alone, play a track (with a fade-in and looping), or fade out whatever is playing. Taking the same slide live again never restarts the music, and a cue for the track that's already playing lets it play on.
- **Soundtracks:** in the Document tab, **Soundtrack** plays a track when you move into the presentation from another item, unless it's already playing. A slide's own audio comes first.
- **In the Live panel:** the playing track shows under the Audience preview, with pause, a position slider, the time left and **Stop**, which fades it out over 2 seconds. A new track crossfades with the old one.
- **Clear and Blackout:** **Clear All** fades the audio out; **Blackout** leaves it playing.

**Video backgrounds and the media bin.**
- **Media Bin:** the **Media** toolbar button (⌥⌘I) opens it under the workspace. **Import…** adds images and videos (MP4, MOV, M4V…); files that don't play are rejected.
- **Media cues:** click an item to put it straight on the audience output's background layer, behind the words on screen, like a ProPresenter media cue. Right-click to make it the background of the cued slide or of its presentation instead.
- **Deleting media:** right-click an item and choose **Delete…**. Presenter names the slides and themes that use it; they lose that background or image, and Undo brings it back. The file leaves the media folder at the next launch, unless a backup still uses it.
- **Video backgrounds:** a video plays on the background layer and keeps playing, without restarting, while transparent slides change the words over it. In the Background inspector, choose **Video** to pick one and set its fill, looping, mute and dimming.
- **Transport:** while a video is live, controls under the Audience preview play and pause it, scrub, show the time left, mute it and set the volume.
- **Missing files:** a missing or unplayable video shows the default background with a warning and never holds up slide changes.
- **File size:** exported projects include their videos, so they can be large.

**Messages and props.** Two more layers over the slides, managed from **Show Controls** in the Live panel:
- **Messages:** a bar across the bottom (or top) of the audience output, like "Parent of child {Number}, please come to the nursery". Words in braces are blanks you fill in when you click **Show…**, and `{timer:Sermon}` shows a live timer. Edit the text, position, size and colours from the ⋯ menu. One message shows at a time.
- **Props:** graphics that stay up across slides, such as a logo. Click a prop to show or hide it; several can be on at once. **New Prop** and **Edit Props…** open them in the slide editor, so they can hold text, shapes and images. Changes to a prop that is on screen wait until you hide it and show it again (its tile says EDITED).
- **Clearing:** Clear Messages (⌥⌘G) and Clear Props (⌥⌘P) are in the Clear button's menu. Clear All (⌥⌘A) clears every layer and Restore brings them back. Blackout hides everything.

**Slide actions and macros.** Like ProPresenter's, they do several things at a cue.
- **Slide actions:** in the slide editor, **Format › Actions** lists what happens when the slide is taken live: start, pause, reset or restart a timer; show a message (with its blanks filled in) or clear messages; show or hide a prop; send or hide a stage message; switch the stage layout; stop the audio; run a macro. A ⚡ on the thumbnail marks slides with actions. Taking the same slide live again doesn't run them again.
- **Macros:** the **Macros** tab in the Live panel holds buttons that run a named list of actions, such as *Pre-Service* (show the logo, start the countdown, play the walk-in music) or *End of Service* (clear everything). Macros can also clear the output, black out and play audio. Right-click a macro to edit, duplicate or delete it.
- A stage layout switched by an action shows in the Stage tab; choosing one there takes over again. Actions that point at something deleted are marked and skipped.

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
- A project saved by a newer version of Presenter isn't opened by an older one; it's moved aside instead, so nothing in it is lost. Release notes say when a version changes the file format; after that, older versions can't open the project.
- If the project file can't be read at launch, it's renamed to `Project.unreadable-<number>.json` so it's never overwritten, and an empty project opens instead.

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
  - **Animate:** the slide's transition, 0.2–2 seconds, played on the audience output (and the Live panel's Audience preview) when the slide goes live: **Dissolve** (cross-fade), **Fade Through Black**, **Push** and **Wipe** (from the left, right, top or bottom) and **Zoom**. Clear and Blackout are always instant.
  - **Element transitions:** select a text, shape or image and give it its own **In** and **Out** transition (Fade, Push, Wipe or Zoom), for when the whole slide shouldn't move. They play with the slide change: one → brings the slide, its elements transition in (an In can wait up to 5 seconds), and the previous slide's elements transition out without holding the new slide back. Everything else follows the slide's own transition. Slides with element transitions show ✦ under their thumbnail.
  - **Document:** the presentation's title, theme and background.

The audience output keeps running while you edit, and edits don't reach it until a slide is taken live again. Build animations (moving text and shapes on and off a slide) and audio are coming in the next phase.

**Themes.** A theme is a reusable look, like ProPresenter's: a font, size, colour, position and effects for each kind of text (title, body and caption) and a background. New projects start with three: **Worship**, **Scripture** (verses top left, the reference small at the bottom) and **Lower Third** (words in a dark band along the bottom, with no background, for a stream or camera feed).

- **Choosing one:** in the slide editor, **Document › Theme**. If the slides already have formatting, Presenter asks whether to keep it or use the theme for all the text. New Song also has a theme picker.
- **Editing:** double-click a theme in the sidebar (or **Edit Theme…** in the editor). Every slide that follows it changes as you edit, with a live preview. Right-click a theme to duplicate it, delete it, or **Use for New Songs**, which marks it **Default**.
- **Formatting by hand:** text you style or move yourself keeps its look when the theme changes. With the text selected, the editor's Format tab says whether it follows the theme, and has **Revert to Theme** and **Update Theme from This Text**.
- **Backgrounds:** a slide's own background comes first, then the presentation's, then the theme's.
- **Deleting a theme** leaves its presentations looking the same: the look is written into their slides.

**Text effects.** Text can have an **Outline** around each letter and a **Box** behind the words (a filled, rounded box with space around the text). They're in the Format tab, in a theme, and in Quick Edit under **Effects…**.

**Quick Edit.** For a fast fix during a service, cue a slide and press ⌥⌘E (or the **Quick Edit** toolbar button). A panel appears under the workspace with three tabs:

- **Text:** the slide's words.
- **Style:**
  - font, weight, italic, size, colour, alignment and shadow, and **Effects…** for an outline and a box;
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
