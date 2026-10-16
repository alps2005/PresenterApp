# Changelog

Notable changes to Presenter. Versions follow the release tags; each release's full notes are in
[docs/release-notes](docs/release-notes).

## Unreleased: planned for v0.1.0-beta.4

### Not yet tested on hardware
Beta 3 changed these and covered them with unit tests, but they still need a check on a real external display
(the GS24F14 projector used for beta 2):
- the stage display full screen on its own display;
- unplugging and replugging a display: the output comes back full screen on the right screen;
- video mute from the transport lasting across slide changes;
- the "Exporting…" progress sheet. The export ran in the background, but on the test machine it finished too fast
  to see the sheet.

### Look
- All operator and editor views now use the design tokens for spacing and corner radius. A few gaps shift by
  1 or 2 points to fit the scale. The audience and stage outputs, which scale with the output size, are unchanged.

### To do
- **Before the repository goes public:**
  - a real contact in CODE_OF_CONDUCT;
  - turn on GitHub private vulnerability reporting, which SECURITY.md relies on.

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
