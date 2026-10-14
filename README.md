# Presenter

A free, open-source, macOS-native live presentation app for worship services, conferences, schools and live events. Live reliability comes first. The operator's view is kept strictly separate from what the audience sees.

**Status:** early development. Milestone 1 is mostly built: a text-only presentation engine with a separate audience output window. Projects save automatically. See [`PROJECT_PROPOSAL.md`](PROJECT_PROPOSAL.md) for the full roadmap.

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
- Xcode 27 or later to build it (the project file uses the Xcode 26+ format)

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
| Clear the slide from the output | ⌥⌘C |
| Blackout | ⌥⌘B |
| Restore after clear/blackout | ⌥⌘R |
| Show/hide audience output | ⌥⌘O, or the **Output** toolbar menu |
| New presentation / new slide | ⌘N / ⇧⌘N |
| Save now (the project also autosaves) | ⌘S |
| Open a project file / export a copy | ⌘O / ⇧⌘S |

**Audience output.** Choose **Show in Window** to rehearse on a single screen. With a second display connected, pick it under **Full Screen** to get a borderless output covering that display. Full-screen output is never offered on the display that shows the operator window. If the output display disconnects, the output hides and the toolbar shows a warning. It comes back automatically when that display reconnects.

**Editing is non-destructive.** Editing a live slide does not change what the audience sees until you take that slide live again. The Live panel warns you when this is the case.

**Saving.** The project saves itself about a second after each change, and again when you quit. It lives at `~/Library/Containers/<bundle id>/Data/Library/Application Support/Presenter/Project.json`. Nothing is ever live when the app starts.

- **Export Project…** writes a copy anywhere, e.g. to keep a backup or move it to another Mac. Images aren't included yet, so on another Mac image backgrounds show as missing.
- **Open Project…** replaces the current project with a file you pick. The current project is backed up to `Presenter/Backups/` first, and the audience output doesn't change.
- If the project file can't be read at launch, it's renamed to `Project.unreadable-<number>.json` so it's never overwritten, and a sample project opens instead.

**One continuous workspace.** The workspace shows every presentation in the playlist one after another, so you can scroll ahead to see what's coming. The sidebar highlights the first presentation whose title is in view, and clicking a sidebar item scrolls to it. When Next or Previous moves the live slide off screen, the workspace scrolls just enough to show it again. While you're typing a presentation title, Space and the arrow keys edit the title instead of changing slides.

**Formatting slides.** Cue a slide, then use the tabs under the workspace:

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
  App/                         App entry point, delegate, menu commands
  Features/Operator/           Operator window: playlist, slide grid, slide editor and inspectors, live panel, controls
  Media/                       Media library: imported images, decoded ahead of time
  Outputs/                     Display discovery, output placement, audience window
  Rendering/                   Shared slide renderer (used for thumbnails, preview and output)
  Support/                     Logging and AppKit helpers
Packages/PresenterCore/        UI-free domain models, PresentationCoordinator and ProjectStore, with unit tests
```

The `PresentationCoordinator` owns all live state and is the only thing that changes it. It keeps four ideas separate:

- **Selected:** the playlist item you're working on.
- **Cued:** the slide that will go live next time you take it.
- **Live:** a snapshot of what the audience currently sees.
- **Up next:** what Next will take live.

Logs use the subsystem `io.github.alps2005.Presenter` and can be viewed in Console.app.

## License

Not chosen yet. See section 11 of the proposal.
