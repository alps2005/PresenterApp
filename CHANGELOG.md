# Changelog

Notable changes to Presenter. Versions follow the release tags; each release's full notes are in
[docs/release-notes](docs/release-notes).

## v1.2.0 (2026-10-21)

This release saves projects in file format 7. Once it opens a project, Presenter 1.1 can't open that project.

### Outputs
- **Second output:** a second audience output for a livestream or a lobby screen (Output › Second Output).
- **Looks:** each audience output can leave out the background, the slide, props or messages, show a key colour
  instead of the background, and restyle the words with another theme (a lower third for a stream), with a live
  preview (the toolbar's Output menu › Look…). Saved on this Mac.

### Shows
- **Welcome window:** Presenter now opens with a window like Xcode's welcome window: the app's version, **Open
  Project…**, **Import Songs…**, **New Show**, and the shows, most recently opened first. Opening a show brings up the
  operator window; the close button quits. Window › Welcome to Presenter (⇧⌘1) opens it again. It replaces the
  Shows window that opened over the operator window at launch; **File › Shows…** (⇧⌘O) still opens that one.

### Updates
- **Presenter updates itself:** it checks GitHub once a day (asking the first time) or with **Presenter › Check for
  Updates…**, shows what's new, and installs and restarts when you agree. Never during a service: while anything is
  live or an output is on, it only shows a quiet "Update to…" item, and an accepted update waits until nothing is
  live. Updates are signed and checked. **Settings…** turns the daily check off. This is the last version you
  download by hand.
- **Download as a DMG:** releases are now a disk image with an Applications shortcut, instead of a zip. Presenter
  says so if it's opened from the disk image (or a copy macOS runs from a temporary place), where it can't update
  itself.

### Songs
- **Import Songs** (File › Import Songs…, ⇧⌘I): OpenLyrics, ChordPro, SongSelect (lyrics .txt and SongPro .usr) and
  plain-text lyrics, several files at once. Chords are left out; sections become labelled groups, and a file's
  singing order becomes a **Song Order** arrangement.
- **Song details:** writers, copyright and CCLI song number, kept from imported files and editable in the slide
  editor under **Document › Song**.

### Show control
- **Slide actions:** a slide can start, pause, reset or restart timers, show a message or prop, change the stage
  message or layout, stop audio and run a macro when it's taken live (slide editor › Format › Actions).
- **Macros:** buttons in the Live panel's new **Macros** tab that run a named list of actions, including clearing the
  output, blackout and playing audio. With five tabs, a narrow Live panel shows them as icons.

### Scripture
- **USFX and USX Bibles:** Import Bible… also reads USFX files and USX Bibles, from their folder or book files. A
  Digital Bible Library `metadata.xml` (in the folder, or beside a single file) names the translation. Notes, headings
  and introductions are left out.
- **Rename…** in the Scripture sheet changes a Bible's name and the abbreviation slides show.

### Fixes
- **Take Live** is grey while nothing is cued; it used to stay bright red.
- The show that's open at launch now shows when it was opened, so deleting another open show goes back to it.
- An output whose remembered screen has the operator window says so, instead of "disconnected", and fills that
  screen as soon as the operator window moves to another one. Before, it waited until a display changed.
- In the stage layout editor, a region's name shows only while the pointer is over it, so names no longer cover
  the words of overlapping regions.

## v1.1.0 (2026-10-19)

This release saves projects in file format 6. Once it opens a project, Presenter 1.0 can't open that project.

### Stage display
- **Stage layouts:** design what the stage display shows. A layout places regions on the screen: the live or next
  words, the live or next slide, the clock, a timer, the notes, the stage message, or fixed text. Projects start
  with **Lyrics**, **Speaker** and **Slides**; **Standard** keeps the look the stage display had before.
- **The layout editor** (Stage tab › **Edit…**): make, copy, rename and delete layouts, drag and resize regions on
  a live preview with snapping, and set each region's text size, colour, alignment and label. Every change can be
  undone, and the stage display follows as you edit.

### Slides
- **Live timers and the clock in slide text:** `{timer:Sermon}`, `{clock}` and `{clock:seconds}` show the running
  value on the audience output, its preview and the stage display. The slide editor's **Live Values › Insert**
  adds them, and warns about a timer name that doesn't exist. Other braces stay as typed.

### Outputs
- **Remembered screens:** the audience output and stage display open at launch where they were, on this Mac,
  even when a display comes back with a new ID; a display that isn't connected yet is waited for.

### Fixes
- Message blanks typed with spaces inside the braces (`{ Number }`) are filled in.

## v1.0.0 (2026-10-19)

The first stable release. It saves projects in file format 5: once 1.0 opens a project, the betas can't open that
project.

### Shows
- **More than one show:** a project can hold several shows (a Sunday service, a midweek meeting, Easter…). Each is
  its own playlist, and they all share one library, so editing a song changes it in every show that has it.
- **The Shows window** opens at launch and from **File › Shows…** (⇧⌘O). It lists the shows, most recently opened
  first; it can open, make, rename, duplicate or delete one. Untick **Show this window when Presenter opens** to skip
  it at launch.
- **Opening a show leaves the audience output alone:** what's live stays on screen until you take a slide live.
  Undo starts afresh in the show you open.
- **Deleting a presentation** removes it from every show.

### Library folders
- **Folders** group the library's presentations, one level deep. Make one with **New Folder…** in the Library, then
  drag presentations onto it or use **Move To** in a presentation's right-click menu. Drag one onto the **Library**
  header to take it out of its folder.
- **Deleting a folder** keeps its presentations: they move back to the top of the library. Folders can be renamed,
  and every change can be undone.

### Audio
- **Audio bin** (the **Audio** toolbar button, ⌥⌘U): import music and sounds (MP3, M4A, WAV, AIFF…), then click one
  to play it for the audience. Right-click to play it looping, to play it when the cued slide goes live, or to make
  it the soundtrack of the cued slide's presentation.
- **Slide audio:** in the slide editor's Format tab (with nothing selected), a slide can play a track, with a fade-in
  and looping, or fade out whatever is playing. Taking the same slide live again never restarts the music, and a
  track that's already playing plays on. Slides that play or stop audio show a note or a muted speaker under their
  thumbnail.
- **Soundtracks:** in the Document tab, a presentation can have a soundtrack that starts when you move into it from
  another item, unless it's already playing.
- **In the Live panel,** the playing track shows with pause, a position slider, the time left and Stop, which fades
  it out. Changing tracks crossfades. **Clear All** fades the audio out; **Blackout** leaves it playing. Live ›
  **Stop Audio** and **Pause or Play Audio** work from anywhere.

### Fixes
- The sidebar, workspace and Live panel say **show** instead of playlist (**Add to Show**, **Remove from Show…**).

## v0.1.0-beta.10 (2026-10-18)

### Scripture
- **Add Scripture… (⌥⌘V):** type a reference in English or Spanish (*Juan 3:16-18*, *1 Co 13:4-7*, *Jn 3:16*) or search
  for words, check the slides, and add the passage to the show. Choose verses per slide, verse numbers and the
  reference caption; new passages follow the Scripture theme.
- **Import Bible…:** reads public-domain translations in Zefania or OSIS XML. None are included; the README says
  where to find them. Bibles are kept outside the project.

### Themes
- **Duplicating or pasting text that a theme places** (like Scripture's verses) puts the copy beside the original,
  ready to move, instead of exactly on top of it.
- **Revert to Theme in Quick Edit:** on the Style tab, when the cued slide's text has its own formatting.
- **The theme editor's preview** shows the title, body and caption together, as a slide would, with each on its own
  below; click one to edit it.

## v0.1.0-beta.9 (2026-10-18)

### Slides that move on by themselves
- **Slideshow:** a presentation's **Slideshow** button moves through its slides every 5, 8, 10, 15 or 30 seconds (or a
  custom time), looping. Good for announcement loops.
- **Go To Next Timer:** right-click a slide (or use the slide editor) to give it its own time, with an option to loop
  to the first slide. It comes before the Slideshow's time.
- **Videos:** a slide whose video plays once waits for it to end; a looping video doesn't hold the slide up.
- **Seeing and stopping it:** a timer under each thumbnail, a countdown circle on the live slide, and **Next slide
  in…** with **Stop** in the Live panel (Live › Stop Auto-Advance, ⌥⌘.). Clear and Blackout stop it.

### Transitions
- **New slide transitions:** Fade Through Black, Push, Wipe and Zoom, next to Dissolve. Push and Wipe come in from
  any side.
- **Element transitions:** text, shapes and images can have their own In and Out transitions (Fade, Push, Wipe,
  Zoom), for when the whole slide shouldn't move. They play when the slide changes; an In can be delayed.
- **The Live panel's Audience preview plays transitions** as the audience sees them.
- **Dissolve fades the old words out** as the new ones fade in, instead of leaving them at full strength until the end.

### File format
- **Version 4:** beta 9 saves every project in a new format, a one-way upgrade. Earlier betas can't open it, so export
  a backup first.

## v0.1.0-beta.8 (2026-10-18)

### Library
- **Clicking a Library row anywhere selects it.** On some Macs only the row's edge responded to a click; the title and
  icon didn't. Double-clicking a row (or pressing Return) adds it to the show.
- **The sidebar's New Presentation and New Song buttons stay readable.** A long library no longer shows through them.

### Performance
- **Less work while scrolling the show.** Selecting a presentation, which happens as you scroll past it, no longer
  redraws the audience output, the stage display and the menus.

## v0.1.0-beta.7 (2026-10-18)

### Library
- **Click a song or presentation in the Library to see its slides.** It opens in the workspace, where you can
  look through it, edit it (double-click a slide or click Edit) or add it to the show. Before, clicking it showed
  "That playlist item no longer exists." Clicking a theme no longer shows that message either.

### Show
- **Rename the show.** Right-click the show's name at the top of the sidebar and choose Rename Show…. The window
  title shows the show's name.

## v0.1.0-beta.6 (2026-10-17)

### Project
- **New installs start clean.** The first launch opens an empty project with only the starting themes (Worship,
  Scripture, Lower Third): no sample presentations, media, timers, messages or props. A project that can't be
  read is still moved aside, and an empty project opens instead of the sample.

### Media
- **Delete media from the media bin.** Right-click an image or video and choose Delete…. If slides or themes use
  it, Presenter says which ones; they lose that background or image. Undo brings it back. What's on screen stays
  until you change it. The file is removed from the media folder at the next launch, unless a backup still uses it.

### Development
- Debug builds use the bundle ID `io.github.alps2005.Presenter.debug`, so Xcode builds keep their own data and a
  downloaded release never opens a developer's test project or media.

## v0.1.0-beta.5 (2026-10-17)

### Themes
- **Themes**, like ProPresenter's: a reusable look for each kind of text (title, body, caption) — font, size,
  colour, position and effects — and a background. New projects start with Worship, Scripture and Lower Third.
- Choose a presentation's theme in the editor's Document tab; Presenter asks whether to keep formatting already on
  the slides. New Song has a theme picker, starting at the theme marked Default.
- Edit themes from the sidebar, with a live preview. Every slide that follows the theme changes.
- Text styled or moved by hand keeps its look. The Format tab says whether text follows the theme, with Revert to
  Theme and Update Theme from This Text.
- Backgrounds fall back slide, presentation, theme. Deleting a theme leaves its presentations looking the same.

### Text
- **Outline** and **Box** effects: an outline around each letter, and a filled, rounded box behind the words.
  In the Format tab, in themes, and in Quick Edit under Effects….

### Project
- Projects are saved in format version 3. Beta 4 and earlier move a version 3 file aside (without overwriting it)
  and open a sample project. Version 2 projects load with the starting themes and look the same as before.

### Look
- **The slide editor's inspector keeps its margins.** With an image or video background, the Background
  section's controls were wider than the inspector, which pushed every row past the column and hid its margins.
  It showed on macOS 14 and 15, where the inspector sits flush with the window edge (reported on a 2019 iMac).
  The Scaling, Dim, Loop and Mute controls now wrap onto their own lines in a narrow inspector, and the
  Background choice turns into a menu when its five buttons don't fit.
- **The live panel keeps its margins** in a narrow window: the Timers, Messages, Props and Stage choice becomes a
  menu when its four buttons don't fit.
- The font menu has a fixed width, so a long font name installed on the Mac can't widen the inspector.
- The inspector has the same solid background as the rest of the editor.
- Presenter Notes and Quick Edit's text box leave space between the words and the box's edge, and have an
  outline, so the notes box no longer disappears into the dark inspector.
- Quick Edit and the media bin have the same 16 pt margins as the side panels.
- The thumbnail-size slider's outline is one pixel wide, so it stays visible on non-Retina displays.

### For contributors
- [ADR 0002](docs/adr/0002-spacing-and-panel-padding.md) sets the panel padding rule and the 238 pt width every
  inspector row must fit. Column widths are tokens (`Widths`).
- Debug builds outline in amber, and log, any panel whose content doesn't fit its column at the column's
  narrowest width.
  `scripts/layout-screenshots.sh` captures each inspector tab at its narrowest width.

## v0.1.0-beta.4 (2026-10-16)

### Tested on hardware (2026-10-16)
Beta 3's untested changes now pass on the GS24F14 external display:
- the stage display and the audience output each go full screen on it;
- unplugging and replugging it: the output hides, then comes back full screen on the GS24F14 by itself;
- video mute from the transport lasts across slide changes, forwards and back;
- the "Exporting…" sheet shows for a 585 MB project, and the window keeps responding.

### Show
- **Output menu:** the first section is headed Audience Output. A display the other output is using is listed as
  "GS24F14 – used by the Audience Output" instead of being left out, so the stage display no longer looks unable
  to use it.
- **A disconnected display** is shown in words in the Live panel, not only as an icon in the toolbar. The toolbar
  icon's tooltip gives the output status.
- **Clear Background:** a slide with its own background brings it back when it goes live, as in ProPresenter.
  The Live panel now says so after a clear, and points to the slide's Background button for removing it for good.

### Look
- All operator and editor views now use the design tokens for spacing and corner radius. A few gaps shift by
  1 or 2 points to fit the scale. The audience and stage outputs, which scale with the output size, are unchanged.

### Project
- The repository is public. Security problems can be reported privately from its Security tab, and the Code of
  Conduct has a contact email.

## v0.1.0-beta.3 (2026-10-15)

### Data safety
- Undo no longer drops an image or video imported after the edit being undone.
- Projects are saved in format version 2. A project from this version is refused (and moved aside, not overwritten)
  by an older Presenter that doesn't understand it.
- Export Project… and Open Project… run in the background with a progress sheet, so large projects with
  videos don't freeze the window.
- If saving fails when you quit, Presenter asks before quitting instead of losing your changes.
- The project is backed up to `Backups/` each time Presenter opens it, keeping the newest 10.

### Show
- Muting a video from the transport now lasts while the same video keeps playing under later slides.
- A new message keeps its position, size and colours in one undo step.

### Look and accessibility
- The operator window is dark by default, with solid panels instead of translucent glass. View › Follow System
  Appearance turns that off.
- **Clearer state badges:** every badge has an icon and a word, in a larger size.
  - BLACKOUT, BACKGROUND ONLY, CLEARED and NOTHING LIVE each look different.
  - CUED is always blue, whatever the system accent colour.
- **Live and cued tiles:** they're outlined the same way everywhere. Up Next and Cued now have borders, and the
  live item in the media bin shows LIVE.
- **Blackout:** the button is set apart from Clear and Restore.
- **Toolbar:** on macOS 26 and later, the operator toolbar's buttons no longer share a glass capsule, so it's
  easier to see which toggles are on.
- **Warnings:** a rejected Take Live and other warnings show in amber.
- **Timers:** the values are larger.
- **Wording:** "Take Live" is used everywhere, and props on screen say LIVE.
- **Confirmations:** deleting a timer or a message asks first.
- **Accessibility:** VoiceOver labels on icon-only buttons, and scrolling respects Reduce Motion.

### Project
- Contributor docs: CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, issue and pull request templates,
  [ARCHITECTURE](docs/ARCHITECTURE.md) and [ADR 0001](docs/adr/0001-quiet-native-design.md).
- CI pins its Xcode version and setup action, and the Xcode scheme is shared.

See [the release notes](docs/release-notes/v0.1.0-beta.3.md).

## v0.1.0-beta.2 (2026-10-14)

- **Stage display:** live words, next slide, clock, timer, notes and a stage message.
- **Show tools:** timers, messages and props.
- **Media:** video backgrounds and a Media Bin, with transport controls.
- **Layers:** transparent backgrounds, and clearing each layer separately.
- **Song tools:** Reflow, arrangements, a library and search, and a thumbnail size slider.

See [the release notes](docs/release-notes/v0.1.0-beta.2.md).

## v0.1.0-beta.1 (2026-10-14)

The first beta:
- **Running a service:** a playlist in one continuous workspace; cue, take live, Clear, Blackout and Restore.
- **Audience output:** in a window, or full screen on a second display.
- **Songs:** New Song from pasted lyrics.
- **Editing:** a Keynote-style slide editor, and Quick Edit.
- **Undo and saving:** undo and redo, autosave, and Export/Open with images.

See [the release notes](docs/release-notes/v0.1.0-beta.1.md).
