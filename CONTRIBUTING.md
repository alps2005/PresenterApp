# Contributing to Presenter

Thanks for helping. Presenter runs live services, so reliability comes before features. Every change should
keep what the audience sees predictable.

## Build and test

You need macOS 14 or later and Xcode 26 or later (CI uses Xcode 26.6).

```sh
# Core tests: models, coordinator, persistence, output and playback decisions. No windows open.
cd Packages/PresenterCore
swift test

# Build the app without signing
xcodebuild -project Presenter.xcodeproj -scheme Presenter -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

Or open `Presenter.xcodeproj`, choose the shared **Presenter** scheme and **My Mac**, and press ⌘R. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is organised.

## Branches and pull requests

- Work on a branch from `develop`, and open the pull request against `develop`.
- `main` only receives merges from `develop` for releases. Releases are tagged `vX.Y.Z` (or
  `vX.Y.Z-beta.N`), which runs `.github/workflows/release.yml`.
- CI (`swift test` plus a Debug build) must pass.
- Keep a pull request to one change, and describe how you tested it. For UI changes, include a before and after
  screenshot.
- Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.

## Code rules

- **Live state goes through the coordinator.** Views and output windows observe `PresentationCoordinator` and send
  it commands; nothing else changes the project or what's live.
  - Edits are recorded for undo with `recordingUndo`.
  - Live commands (Take Live, Clear, Blackout) are never undone.
- **Decisions go in the core, with tests.** If logic can be expressed without AppKit, SwiftUI or AVFoundation, put
  it in `PresenterCore` and test it. Examples: `OutputPlanner`, `PlaybackPlan`, `ProjectLoader`, `Snapping`. The
  app target should be thin glue.
- **No method references as closure arguments.** Write `items.map { format($0) }`, not `items.map(format)`.
  Unapplied method references have crashed the CI compiler. Key paths such as `map(\.id)` are fine.
- **Saved data:** when a release adds or changes a field in a saved type, decode it with a default
  (`decodeIfPresent`) and bump `ProjectDocument.currentSchemaVersion`. See its doc comment.
- **UI:** use the tokens and components in `Presenter/DesignSystem` (`Palette`, `Spacing`, `StateBadge`,
  `tileFrame`, `WarningLabel`, `PopoverForm`…), not ad hoc colours and borders.
  - State is never shown by colour alone.
  - Icon-only buttons need an `accessibilityLabel`.
  - Pad panels by the rule on `Spacing`, and make every inspector row fit `Widths.inspectorContentWidth` or wrap.
  - See [ADR 0001](docs/adr/0001-quiet-native-design.md) and [ADR 0002](docs/adr/0002-spacing-and-panel-padding.md).
- **Style:** match the code around you. Comments explain why, not what. Log with `os.Logger` under the
  `io.github.alps2005.Presenter` subsystem.

## Reporting bugs and ideas

Use the issue templates. For a bug, the steps that led to it and your macOS version help most. Report security
problems privately, as described in [SECURITY.md](SECURITY.md).

By contributing, you agree that your contribution is licensed under the GPL-3.0-or-later, like the rest of
Presenter, and that you'll follow the [Code of Conduct](CODE_OF_CONDUCT.md).
