# Changelog

Notable changes to Presenter. Versions follow the release tags; each release's full notes are in
[docs/release-notes](docs/release-notes).

## Unreleased

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
