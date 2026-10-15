# Open-Source macOS Live Presentation System
## Project Proposal and Implementation Brief for Claude Code

**Working title:** OpenPresenter  
**Platform:** macOS  
**Primary language:** Swift  
**UI:** SwiftUI, with AppKit for native window and display management  
**Distribution:** Open source via GitHub  
**Project stage:** Greenfield project

> The working title is provisional. Before publishing, check trademarks, package names, and repository-name availability.

---

## 1. Project Overview

Build a free, open-source, macOS-native live presentation and production application inspired by the workflow and feature breadth of professional presentation tools such as ProPresenter.

The app should support worship services, conferences, schools, performances, and other live events. It should prioritize reliable live output, fast operator controls, and a clear separation between the operator interface and what the audience sees.

The long-term goal is a capable ProPresenter alternative. The project must reach that goal incrementally: first establish a stable presentation engine, then add content management, media playback, production layers, stage display, and remote control.

### Product principles

1. **Live reliability first.** A missed slide, frozen output, or accidental black screen is a serious failure.
2. **Native macOS experience.** Use SwiftUI for most UI and AppKit where precise window, screen, and event control is needed.
3. **Offline-first.** Core presentation functions must work without an internet connection.
4. **Non-destructive editing.** Editing content should not unexpectedly alter what is currently live.
5. **Clear live state.** Operators must always know what is live, what is queued, and which output is selected.
6. **Modular architecture.** Media, rendering, content, outputs, and control surfaces should be independently testable.
7. **Open source by default.** Keep build instructions, contribution guidance, licensing, and issue tracking in the repository.
8. **Graceful degradation.** Missing media or a disconnected display should produce recoverable errors, not crash the app.

---

## 2. Goals and Non-Goals

### Long-term goals

- Multiple displays and independently configurable outputs.
- Playlists, slide editing, and a reusable content library.
- Structured songs, Bible passages, announcements, and presentation slides.
- Image, audio, and video playback.
- Backgrounds, themes, text styling, and transitions.
- Stage display with notes, clock, timers, and next-slide information.
- Production layers such as backgrounds, foreground content, lower thirds, and overlays.
- Live controls, keyboard shortcuts, and configurable operator workflows.
- Local remote control from a browser or companion device.
- Save/restore sessions and recover gracefully from failures.
- Import/export and backup workflows.
- A plugin or integration architecture once core interfaces are stable.

### Initial non-goals

Do not attempt to implement all of these in the first release:

- Cloud accounts, synchronization, or hosted infrastructure.
- Multi-user collaborative editing.
- A complete video switcher or broadcast mixing suite.
- Every third-party integration.
- A built-in licensed media catalog.
- Automatic downloading or redistribution of copyrighted song lyrics, Bible translations, fonts, or media.
- Windows/Linux support in the initial product.
- A complex plugin API before the core data model stabilizes.

---

## 3. Recommended Technology Stack

### Core

- **Swift** — primary implementation language.
- **SwiftUI** — operator UI, inspectors, library views, settings, and standard panels.
- **AppKit** — display discovery, window placement, full-screen behavior, keyboard event integration, and specialized native window handling.
- **AVFoundation** — audio/video playback and media timing where appropriate.
- **Core Animation / SwiftUI animation** — initial transitions and UI-level effects; introduce more specialized rendering only when justified.
- **SQLite** — durable content metadata and project structure. Use a maintained Swift SQLite wrapper or a small, isolated database layer; avoid spreading SQL throughout the UI.
- **Swift Package Manager** — modular internal packages and dependency management.
- **XCTest** — unit and integration tests.
- **GitHub Actions** — build and test automation.

### Important implementation guidance

- Use SwiftUI `WindowGroup` or explicit window management where appropriate, but do not assume a standard SwiftUI window alone provides all the control needed for reliable live output.
- Use AppKit window and screen APIs for precise external-display placement and lifecycle handling.
- Keep the presentation renderer separate from the operator interface.
- Avoid making UI views the source of truth for playback or live state.
- Avoid introducing third-party dependencies unless they solve a real need and have a compatible license.
- Start with a simple, testable renderer. Do not build a custom GPU compositor before the product requirements justify it.

---

## 4. Architecture

Use a modular, event-driven architecture with a central presentation coordinator. The coordinator owns live state and sends explicit commands to renderers and media services.

### High-level architecture

```text
┌───────────────────────────────────────────────────────────────┐
│                         Operator UI                            │
│  Playlist | Library | Slide Editor | Preview | Inspector       │
│  Live Controls | Settings | Media Browser                      │
└───────────────────────────────┬───────────────────────────────┘
                                │ User commands
                                ▼
┌───────────────────────────────────────────────────────────────┐
│                  Application / Presentation Core               │
│                                                               │
│  PresentationCoordinator                                      │
│  SessionStore | Command Handling | Live State | Event Routing  │
│  Playlist Manager | Output Manager | Recovery State            │
└─────────────┬─────────────────┬─────────────────┬─────────────┘
              │                 │                 │
              ▼                 ▼                 ▼
┌────────────────────┐ ┌──────────────────┐ ┌───────────────────┐
│ Content & Project  │ │ Rendering System │ │ Media Services    │
│ Songs / Slides     │ │ Slide Renderer   │ │ AVFoundation      │
│ Themes / Playlists │ │ Layer Compositor  │ │ Playback State    │
│ SQLite / Assets    │ │ Transitions      │ │ Audio / Video     │
└────────────────────┘ └─────────┬────────┘ └───────────────────┘
                                 │
                                 ▼
┌───────────────────────────────────────────────────────────────┐
│                         Output Manager                         │
│  Audience Output | Stage Output | Secondary Output (later)     │
│  Screen Detection | Window Placement | Output Configuration    │
└───────────────────────────────────────────────────────────────┘
```

### Core modules

#### 4.1 Presentation Core

Responsibilities:
- Own the current session and active playlist.
- Track selected item, live item, next item, and active slide.
- Process commands such as `takeLive`, `nextSlide`, `previousSlide`, `clearOutput`, and `blackout`.
- Publish state changes to UI and output renderers.
- Keep operator selection separate from live output.
- Prevent invalid state transitions.

The core should be testable without opening windows.

#### 4.2 Content Model and Project Store

Responsibilities:
- Store presentations, playlists, slide content, songs, themes, and media references.
- Persist metadata in SQLite.
- Keep media assets in a project-managed directory or a user-selected media location.
- Support versioned migrations.
- Detect missing or moved assets.
- Provide project backup and restore.

Do not store large video files as database blobs. Store references and metadata instead.

#### 4.3 Rendering System

Responsibilities:
- Convert content models into renderable visual scenes.
- Render text, images, backgrounds, and layers.
- Support aspect ratio and safe-area configuration.
- Support transitions between scenes.
- Provide deterministic rendering for preview and audience output.
- Expose renderer state and recover from media/rendering errors.

Preview and audience output should use the same rendering logic where possible, with output-specific configuration.

#### 4.4 Output Manager

Responsibilities:
- Discover connected displays.
- Let the operator select the audience display.
- Open, position, and resize output windows correctly.
- Handle display connection/disconnection and resolution changes.
- Ensure operator controls never appear on audience output.
- Support an explicit safe state if the selected display disappears.
- Keep output configuration separate from presentation content.

Do not assume that display indices or screen ordering remain stable between launches.

#### 4.5 Media Services

Responsibilities:
- Load and play audio/video assets.
- Report playback state, duration, and errors.
- Support pause, resume, stop, seek where appropriate, and looping.
- Preload the next asset when feasible.
- Prevent media failures from blocking slide navigation.
- Keep playback lifecycle out of SwiftUI view lifecycle code.

#### 4.6 Stage Display

Future module:
- Display current/next slide, presenter notes, clock, countdown timer, and service cues.
- Allow stage display to have a different layout from audience output.
- Never expose stage-only content to the audience renderer.

#### 4.7 Remote Control

Future module:
- Provide a local-network API for commands and state snapshots.
- Authenticate or pair control clients.
- Keep remote commands behind the same command validation as local UI actions.
- Make it possible to disable remote control entirely.
- Do not expose a network listener by default until the feature is enabled.

---

## 5. Data Model

Begin with a small, versioned model. Prefer stable IDs over relying on array indices or display names.

Suggested conceptual entities:

- **Project** — project ID, name, schema version, settings, asset references.
- **Playlist** — ID, title, ordered references to presentation items.
- **PresentationItem** — common identity and metadata for an item in a playlist.
- **Slide** — ID, ordered elements, transition, and optional notes.
- **SlideElement** — text, image, video, shape, or other visual element.
- **Song** — title, author metadata, copyright metadata, and ordered sections.
- **SongSection** — verse, chorus, bridge, tag, or custom section with text.
- **BiblePassage** — translation identifier, book, chapter, verse range, and resolved text when legally available.
- **Theme** — typography, colors, backgrounds, alignment, and layout defaults.
- **MediaAsset** — ID, relative or external URL, media type, duration if known, and availability state.
- **OutputConfiguration** — output role, selected display identity, aspect ratio, and rendering preferences.
- **Cue** — a future timed or operator-triggered action in a service sequence.

### Example Swift model sketch

This is illustrative, not a complete persistence implementation:

```swift
import Foundation

struct PresentationDocument: Identifiable, Codable {
    let id: UUID
    var title: String
    var slides: [SlideDocument]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        slides: [SlideDocument] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.slides = slides
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct SlideDocument: Identifiable, Codable {
    let id: UUID
    var elements: [SlideElement]
    var notes: String?

    init(
        id: UUID = UUID(),
        elements: [SlideElement] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.elements = elements
        self.notes = notes
    }
}

enum SlideElement: Codable, Identifiable {
    case text(id: UUID, text: String, role: TextRole)
    case image(id: UUID, assetID: UUID)
    case video(id: UUID, assetID: UUID)

    var id: UUID {
        switch self {
        case .text(let id, _, _),
             .image(let id, _),
             .video(let id, _):
            return id
        }
    }
}

enum TextRole: String, Codable {
    case title
    case body
    case caption
}
```

Before expanding the schema, add tests for encoding/decoding, migrations, stable identity, and missing asset handling. Be deliberate about schema design; production features may require richer element styling and layout models.

---

## 6. Operator Experience

The main window should be optimized for fast operation under pressure.

### Proposed main layout

```text
┌───────────────────────────────────────────────────────────────────┐
│ Project / Service     Output: Projector A      LIVE / SAFE STATE  │
├───────────────┬───────────────────────────────┬───────────────────┤
│ Library       │ Slide Grid / Playlist         │ Live Preview      │
│               │                               │                   │
│ Songs         │ [Item 1] [Item 2] [Item 3]     │ Current output    │
│ Presentations │ [Item 4] [Item 5] [Item 6]     │ preview           │
│ Media         │                               │                   │
│ Themes        │ Playlist order                │ Next slide        │
├───────────────┴───────────────────────────────┴───────────────────┤
│ Previous | Next | Take Live | Clear | Blackout | Media Controls    │
└───────────────────────────────────────────────────────────────────┘
```

### UX requirements

- Make the active live slide unmistakable.
- Differentiate selected, previewed, queued, and live content.
- Provide keyboard shortcuts for common operations.
- Confirm destructive actions, but avoid modal confirmations for routine live operations.
- Offer an immediate blackout and clear-output action.
- Keep media loading and error states visible.
- Support undo for editing operations where practical.
- Make the UI usable at common MacBook and external monitor resolutions.
- Never allow an editor selection to silently change audience output.

---

## 7. MVP Roadmap

The roadmap is milestone-based rather than tied to calendar estimates. Complete each milestone with tests and a usable demo before expanding scope.

### Milestone 0 — Repository and application shell

Deliverables:
- Create a macOS app project using SwiftUI and AppKit.
- Set bundle identifier, minimum macOS version, and build settings.
- Add repository license, README, contribution guide, and issue templates.
- Establish folder/module structure.
- Add basic logging and a test target.
- Build and run on a clean checkout.

Acceptance criteria:
- A developer can clone the repo and run the app using documented steps.
- Debug and release configurations build successfully.
- Basic unit tests run.

### Milestone 1 — Minimal presentation engine

Deliverables:
- Create and edit a presentation with text slides.
- Show slide thumbnails or a slide list.
- Navigate slides from the keyboard.
- Show a live preview in the operator window.
- Save and reopen a presentation.
- Implement a separate output window.

Acceptance criteria:
- The app can run a short text-only presentation from start to finish.
- The output window is independent from the operator window.
- Changing editor selection does not alter live output.
- Navigation works without noticeable UI stalls.
- State transitions are covered by unit tests.

### Milestone 2 — External display and safety controls

Deliverables:
- Enumerate connected displays.
- Select the audience display.
- Place the output window on the selected screen.
- Support full-screen output.
- Add blackout, clear, and restore controls.
- Handle display disconnect/reconnect.

Acceptance criteria:
- The operator window remains usable while output is full-screen.
- Connecting or disconnecting a display does not crash the app.
- The UI communicates when no valid output is available.
- Blackout and clear actions are deterministic and testable.

### Milestone 3 — Content and project storage

Deliverables:
- SQLite-backed project metadata.
- Playlist management and reordering.
- Reusable text slides and themes.
- Asset directory management.
- Project save, reopen, and backup.
- Schema migration mechanism.

Acceptance criteria:
- Projects survive app restarts.
- Missing assets are reported without crashing.
- Project data has stable IDs and a documented schema/versioning strategy.

### Milestone 4 — Song workflow

Deliverables:
- Song library.
- Song sections such as verse, chorus, bridge, and tag.
- Generate slides from selected song sections.
- Preserve section order and allow repeated choruses.
- Search songs and add them to a playlist.
- Record source/copyright metadata where applicable.

Acceptance criteria:
- An operator can find a song, add it to a service playlist, and take each section live.
- Repeated sections do not require duplicating the source text manually.
- Song content remains editable without corrupting saved presentations.

### Milestone 5 — Images, video, and audio

Deliverables:
- Import and manage image/video/audio assets.
- Render still images as backgrounds or slide elements.
- Play and stop video on the audience output.
- Basic audio playback and volume controls.
- Media loading indicators and error handling.
- Optional loop behavior.

Acceptance criteria:
- Unsupported or missing media fails gracefully.
- Slide navigation remains responsive during playback.
- Media lifecycle is managed independently of view appearance/disappearance.
- Test with multiple common codecs and resolutions.

### Milestone 6 — Themes, layers, and transitions

Deliverables:
- Reusable themes and text styles.
- Background and foreground layers.
- Fade transitions, then additional transitions as warranted.
- Text positioning and alignment controls.
- Output aspect-ratio settings and safe areas.
- Preview that matches audience rendering as closely as possible.

Acceptance criteria:
- A theme can be reused across slides.
- Transition state can be interrupted or completed predictably.
- A rendering issue in one slide does not crash the operator interface.

### Milestone 7 — Stage display and live production

Deliverables:
- Separate stage output window.
- Current and next slide.
- Presenter notes.
- Clock and configurable countdown timer.
- Basic cue model.
- Configurable production layers/overlays.
- Better recovery and session restoration.

Acceptance criteria:
- Stage-only information never appears on audience output.
- Stage output can be disabled without affecting audience output.
- Session restoration never automatically sends unexpected content live without an explicit policy.

### Milestone 8 — Remote control and release hardening

Deliverables:
- Optional local-network remote control.
- Pairing and authorization model.
- Status dashboard for output/media health.
- Import/export and backup documentation.
- Accessibility review.
- Automated build/test workflow.
- Signed and notarized distribution process documented when available.

Acceptance criteria:
- Remote control can be disabled.
- Invalid remote commands are rejected.
- A clean clone builds and passes tests in CI.
- Release notes and known limitations are published.

---

## 8. Suggested Repository Structure

Start with a single Xcode project and Swift Package Manager modules only where they create meaningful boundaries. Avoid creating dozens of targets on day one.

```text
OpenPresenter/
├── OpenPresenter.xcodeproj
├── Package.swift                     # Optional if using a package-first setup
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── CHANGELOG.md
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DATA_MODEL.md
│   ├── BUILDING.md
│   ├── ROADMAP.md
│   └── ADRs/
│       ├── 0001-swiftui-appkit.md
│       └── 0002-project-storage.md
├── Sources/
│   ├── App/
│   │   ├── OpenPresenterApp.swift
│   │   ├── AppDelegate.swift
│   │   ├── AppCommands.swift
│   │   └── AppEnvironment.swift
│   ├── Domain/
│   │   ├── Models/
│   │   ├── Commands/
│   │   ├── Events/
│   │   └── Protocols/
│   ├── PresentationCore/
│   │   ├── PresentationCoordinator.swift
│   │   ├── PresentationState.swift
│   │   ├── PlaylistController.swift
│   │   └── CommandDispatcher.swift
│   ├── Rendering/
│   │   ├── SlideRenderer.swift
│   │   ├── RenderScene.swift
│   │   ├── RenderLayer.swift
│   │   └── Transitions/
│   ├── Outputs/
│   │   ├── OutputManager.swift
│   │   ├── DisplayDiscovery.swift
│   │   ├── AudienceOutputController.swift
│   │   └── StageOutputController.swift
│   ├── Media/
│   │   ├── MediaService.swift
│   │   ├── VideoPlaybackController.swift
│   │   └── AssetResolver.swift
│   ├── Persistence/
│   │   ├── ProjectStore.swift
│   │   ├── Database/
│   │   ├── Migrations/
│   │   └── BackupService.swift
│   ├── Features/
│   │   ├── Operator/
│   │   ├── Playlist/
│   │   ├── SlideEditor/
│   │   ├── Library/
│   │   ├── Themes/
│   │   ├── StageDisplay/
│   │   └── Settings/
│   └── SharedUI/
│       ├── Components/
│       └── Styles/
├── Tests/
│   ├── DomainTests/
│   ├── PresentationCoreTests/
│   ├── PersistenceTests/
│   ├── RenderingTests/
│   └── OutputTests/
└── .github/
    ├── workflows/
    │   └── macos-ci.yml
    ├── ISSUE_TEMPLATE/
    └── pull_request_template.md
```

This is a target structure, not a requirement to create every file immediately. Implement only the files needed for the current milestone.

---

## 9. Initial Implementation Plan

### Step 1: Create the Xcode project

- Create a native macOS App project in Xcode.
- Use SwiftUI for the app lifecycle and primary window.
- Add an AppKit app delegate only where native lifecycle or window integration is required.
- Add unit-test and UI-test targets.
- Set a sensible minimum macOS version based on the APIs actually used.
- Use a reverse-DNS bundle identifier that you control.

### Step 2: Build a static operator shell

Create a window with:
- A sidebar for library categories.
- A playlist area.
- A slide list/grid.
- A live preview panel.
- Previous, next, take-live, clear, and blackout controls.

At this stage, use in-memory sample content. Do not build the database or media system yet.

### Step 3: Define domain models

Add stable identifiers and value types for:
- `PresentationDocument`
- `SlideDocument`
- `SlideElement`
- `PlaylistDocument`
- `PresentationItem`
- `PresentationState`

Keep these independent of SwiftUI view types. Add Codable support where appropriate and unit tests for serialization.

### Step 4: Implement the presentation coordinator

The coordinator should own explicit state such as:
- Current project.
- Active playlist.
- Selected playlist item.
- Current live item and slide.
- Current preview item and slide.
- Output status.
- Playback status.

Expose commands instead of allowing views to mutate internal state arbitrarily.

Suggested command API:

```swift
protocol PresentationControlling {
    func selectItem(_ itemID: UUID)
    func takeSelectedItemLive()
    func nextSlide()
    func previousSlide()
    func clearOutput()
    func blackout()
    func restoreOutput()
}
```

The concrete implementation should validate every command and publish state changes on the main actor when they affect UI. Keep rendering and media work off the main thread when appropriate.

### Step 5: Implement the first output window

- Create an output controller using AppKit window management.
- Use a separate renderer view for the audience output.
- Initially target the main display if no external display is available.
- Add a display selector once basic output works.
- Do not tie the output window's lifetime to a transient SwiftUI view.
- Handle display changes and window closure explicitly.

### Step 6: Add persistence only after state works

- Choose a project format and SQLite schema.
- Create migrations from the first persisted schema version.
- Add autosave carefully, avoiding a database write on every transient UI event.
- Store media files outside the database.
- Add backup/restore and missing-asset reporting.

### Step 7: Add media and advanced features incrementally

Implement one media type at a time. Start with still images, then video, then audio and more complex background playback. Establish explicit media states such as idle, loading, ready, playing, paused, stopped, and failed.

---

## 10. Quality, Reliability, and Safety Requirements

A live production app needs stronger reliability practices than a basic slideshow editor.

### Required practices

- Unit-test presentation state transitions.
- Test that selecting a slide does not take it live.
- Test next/previous behavior at the start and end of a playlist.
- Test missing files and corrupt project data.
- Test display disconnects and output recreation.
- Keep media errors isolated from the presentation coordinator.
- Avoid blocking the main thread with decoding, database work, or file operations.
- Add structured logging with clear subsystem names.
- Keep a visible output-health indicator.
- Make blackout and clear behavior explicit and separately testable.
- Never automatically take a newly selected or restored slide live unless the operator has configured that behavior.
- Avoid network services until remote control is deliberately enabled.

### Live-output distinction

Use separate concepts for:
- **Selected:** what the operator is working on.
- **Preview:** what is ready to be sent live.
- **Live:** what the audience currently sees.
- **Next:** what will follow according to the current playlist/slide sequence.

Do not collapse these into a single `currentSlide` variable.

---

## 11. Open-Source and Distribution Plan

### Recommended initial license

**Decision (October 2026):** Presenter is licensed under GPL-3.0-or-later, copyright Adrian Palma. See `LICENSE`.

Choose the license deliberately before publishing. GPL-3.0 is a reasonable option if the project aims to keep distributed derivative versions open source. MIT is more permissive. AGPL-3.0 may be relevant if a network-hosted version becomes important.

This document does not constitute legal advice. Review the license and its obligations before release.

### Repository setup

- Public GitHub repository.
- `README.md` with goals, screenshots, build instructions, status, and roadmap.
- `LICENSE` with the complete license text.
- `CONTRIBUTING.md` describing development and testing.
- `CODE_OF_CONDUCT.md`.
- `SECURITY.md` with a responsible disclosure process.
- GitHub Issues and Discussions for feedback.
- Release notes and version tags.
- GitHub Actions to build and test on macOS.

### Distribution realities

- GitHub source hosting and release assets can be free within the applicable plan limits.
- Local development can begin without a paid Apple Developer Program membership.
- Unsigned or ad-hoc-signed apps may trigger Gatekeeper warnings and require extra steps for users.
- A polished public macOS distribution normally benefits from Developer ID signing and Apple notarization, which generally require paid Apple developer membership.
- Do not promise that all users can install an unsigned build without warnings.
- Avoid committing signing certificates, API keys, secrets, or personal developer credentials.

### Content licensing

Do not bundle or redistribute copyrighted lyrics, commercial fonts, Bible translations, images, videos, or music unless the project has the appropriate rights. Support user-supplied content and document asset licensing requirements.

---

## 12. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Scope becomes too large | Use milestone gates; ship the text-only engine before advanced production |
| External-display behavior is fragile | Encapsulate display/window management in a dedicated output module |
| Media playback freezes the UI | Isolate media services and avoid blocking the main actor |
| Preview differs from audience output | Share renderer code and output configuration models |
| Data model becomes difficult to migrate | Version the schema and test migrations from the first persisted release |
| Copyright issues with sample content | Use original, public-domain, or properly licensed demo assets |
| Open-source contributions are difficult to review | Keep architecture docs, tests, coding conventions, and small pull requests |
| Feature parity is mistaken for release readiness | Prioritize predictable live behavior and document unsupported features |

---

## 13. Definition of a Successful First Public Alpha

The first public alpha is successful when a user can:

1. Clone the repository and build the app from documented instructions.
2. Create and save a presentation with multiple text slides.
3. Create a playlist and reorder items.
4. Select content without changing what is live.
5. Open a separate audience output window on an external display.
6. Advance and reverse slides using keyboard shortcuts.
7. Black out or clear the audience output intentionally.
8. Close and reopen the project without losing saved content.
9. Recover gracefully if an output display is disconnected.
10. Report bugs with reproducible steps and logs.

The alpha does not need video backgrounds, a remote app, a plugin API, or full stage-display functionality.

---

## 14. Instructions for Claude Code

Work incrementally. Do not try to implement the entire roadmap in one pass.

### First task

Inspect the current repository. If it is empty, create the minimum viable native macOS SwiftUI/AppKit project structure. If an Xcode project already exists, inspect it before modifying anything.

Then:

1. Propose the initial file structure and explain any necessary deviations from this proposal.
2. Create the app shell and a clean, buildable Xcode project.
3. Add domain models for text-based presentations and slides.
4. Implement a presentation coordinator with distinct selected, preview, and live state.
5. Build a basic operator interface with a playlist/slide list and navigation controls.
6. Add a separate audience output window, initially supporting the main display and then an external display where available.
7. Add unit tests for the presentation coordinator and state transitions.
8. Update `README.md` with exact build and run instructions.
9. Run the available build and test commands. Fix errors rather than claiming unverified success.
10. Summarize what was implemented, what was tested, and the next recommended task.

### Development constraints

- Use Swift and native macOS frameworks.
- Prefer clear, small abstractions over premature generalization.
- Do not introduce external dependencies without explaining why they are needed.
- Keep business logic out of SwiftUI views.
- Use stable UUIDs for persistent identities.
- Keep selected, preview, and live state separate.
- Do not implement fake functionality that appears to work but does not affect the real output.
- Do not claim a build or test passed unless the command was actually run and succeeded.
- Ask before performing destructive changes to existing project files.
- Keep each change buildable whenever possible.
- If an API depends on the deployment target, check availability and provide a suitable fallback or document the minimum supported macOS version.

### Expected first response from Claude Code

Before extensive implementation, briefly report:
- The repository state.
- The proposed initial files.
- The first milestone being implemented.
- Any critical assumptions about the minimum supported macOS version or project setup.

Then implement the first milestone and verify it.

---

## 15. Immediate Next Steps

1. Create a GitHub repository with the chosen project name.
2. Create a native macOS app in Xcode.
3. Add this proposal as `PROJECT_PROPOSAL.md`.
4. Open the repository in Claude Code.
5. Ask Claude Code to follow Section 14 and implement only the first milestone.
6. Build and test locally before starting persistence, media, or advanced production features.

**Guiding principle:** build a reliable live presentation engine first. Every advanced feature should extend that foundation rather than bypass it.
