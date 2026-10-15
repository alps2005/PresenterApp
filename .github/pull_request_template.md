## What and why

<!-- What this changes and the problem it solves. Link the issue if there is one. -->

## How I tested it

<!-- swift test, the build, and what you did in the app. For UI changes, add before/after screenshots. -->

## Checklist

- [ ] `swift test` passes in `Packages/PresenterCore`, and the app builds
- [ ] Live changes go through `PresentationCoordinator`; decisions that don't need UI are in the core with tests
- [ ] No method references as closure arguments
- [ ] Saved fields decode with defaults, and `currentSchemaVersion` is bumped if a saved field changed
- [ ] UI uses `Presenter/DesignSystem`; icon-only buttons have accessibility labels
- [ ] CHANGELOG.md updated under Unreleased, if users would notice
