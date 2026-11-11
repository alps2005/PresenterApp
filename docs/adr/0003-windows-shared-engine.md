# ADR 0003: A Windows version that shares the Swift engine

- **Status:** Accepted. Steps 1 and 2 are done: the first Windows app went out as an open beta (windows-v0.1.0-beta.1).
- **Date:** 2026-11-04

## Context

Churches that only have Windows PCs can't use Presenter. A Windows version has to run full services and keep in
step with the Mac app, and, like the Mac app, it must be free to build and distribute.

Presenter is two halves:
- `Packages/PresenterCore`, the engine (shows, songs, Bibles, live state, saving, importers): 8.6k lines and about
  395 tests. It's almost all plain Swift and Foundation, which Swift on Windows has. It's synchronous, with the clock
  injected, and its models are Codable.
- `Presenter/`, the Mac app: 12k lines of SwiftUI, AppKit, AVFoundation, CoreAudio, PDFKit and Sparkle, none of
  which exist on Windows.

The views already only send commands to `PresentationCoordinator` and read its state.

## Decision

- **One engine.** `PresenterCore` builds and passes its tests on Windows too. Mac-only code is fenced with
  `#if canImport(...)`, and work that needs platform frameworks goes behind a protocol the app supplies:
  - The logger: `os.Logger` on Apple platforms, standard error elsewhere.
  - `MediaProbe` checks imported files: `AppleMediaProbe` (ImageIO and AVFoundation) on a Mac, and the Windows
    app's own probe there.
  - XML: `FoundationXML` off Apple platforms.
- **A bridge DLL.** `Packages/PresenterBridge` will wrap `PresentationCoordinator` behind a small C interface:
  commands go in as JSON, and state comes back as JSON.
- **Windows screens in C#/.NET with Avalonia**, which calls the bridge. Avalonia also runs on macOS, so the Windows
  app can be tried on a Mac against the same engine.
- **One file format.** `Project.json` and the `Media/` and `Bibles/` folders are the same on both, so a project
  moves between a Mac and a PC.
- **Order of work:**
  1. The engine passes its tests on Windows in CI.
  2. A first app: open a project, take slides live, and show them full screen on a second display. It became an
     open beta that works without a Mac: songs typed or imported, shows, and the live controls.
  3. The full app, a release at a time, with what beta testers report.

## Consequences

- A fix or feature in the engine reaches both apps. New features land in the engine first, with tests, and then
  get screens on each platform.
- The CI job `core-windows` keeps the engine building on Windows. A Mac-only API used in the engine without a fence
  fails there.
- The tests that make real image, audio and video files use Apple's frameworks, so they run only on the Mac. The
  store's own logic is tested everywhere with a fake probe.
- The Windows screens are new work on the scale of the Mac app's, so the full Windows app will take several
  releases.
- Windows warns about apps that aren't code-signed, much as Gatekeeper does on a Mac. Free signing for open-source
  projects (SignPath Foundation) is the way to avoid that, and no paid certificate is planned.
- The installer is made with Velopack (free, MIT), which can also bring automatic updates later. It installs to
  `%LOCALAPPDATA%\PresenterApp` and uninstalling deletes that folder whole, so the app's files stay apart from the
  project in `%LOCALAPPDATA%\Presenter`. CI installs and uninstalls on every run and fails if the project is touched.
