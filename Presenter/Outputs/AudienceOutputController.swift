import AppKit
import os
import SwiftUI
import PresenterCore

/// Owns the audience output NSWindow. Its lifetime belongs to `OutputManager`, never to a SwiftUI view.
final class AudienceOutputController: NSObject, NSWindowDelegate {
    private enum Mode: Equatable {
        case windowed
        case fullScreen(CGDirectDisplayID)
    }

    private let coordinator: PresentationCoordinator
    private let mediaLibrary: MediaLibrary
    private var window: NSWindow?
    private var mode: Mode?

    /// Called when the operator closes the windowed output with its close button.
    var onUserClosedWindow: (() -> Void)?

    init(coordinator: PresentationCoordinator, mediaLibrary: MediaLibrary) {
        self.coordinator = coordinator
        self.mediaLibrary = mediaLibrary
    }

    /// A normal resizable window, for rehearsing on a single display.
    func showWindowed() {
        if mode == .windowed, let window {
            window.orderFront(nil)
            return
        }
        tearDown()
        let window = makeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable]
        )
        window.title = "Audience Output"
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.delegate = self
        window.center()
        window.orderFront(nil)
        self.window = window
        mode = .windowed
        Log.output.info("Showing windowed output")
    }

    /// A borderless window covering the whole screen, including its menu bar. It never becomes key,
    /// so keyboard focus stays with the operator window.
    func showFullScreen(on screen: NSScreen, displayID: CGDirectDisplayID) {
        if mode == .fullScreen(displayID), let window {
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            return
        }
        tearDown()
        let window = makeWindow(contentRect: screen.frame, styleMask: [.borderless])
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        self.window = window
        mode = .fullScreen(displayID)
        Log.output.info("Showing full-screen output on \(screen.localizedName, privacy: .public)")
    }

    func hide() {
        guard window != nil else { return }
        tearDown()
        Log.output.info("Output hidden")
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        mode = nil
        onUserClosedWindow?()
    }

    private func tearDown() {
        window?.delegate = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        mode = nil
    }

    private func makeWindow(contentRect: NSRect, styleMask: NSWindow.StyleMask) -> NSWindow {
        let window = NSWindow(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.backgroundColor = .black
        // A separate SwiftUI root: it doesn't inherit the operator window's environment.
        let hostingView = NSHostingView(rootView: AudienceOutputView(coordinator: coordinator).environment(mediaLibrary))
        // The window decides its size; SwiftUI content must not resize it.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        return window
    }
}

/// What the audience sees. Uses the same renderer as the operator's live preview.
private struct AudienceOutputView: View {
    let coordinator: PresentationCoordinator

    /// The scene on top, fading in during a dissolve.
    @State private var shown: AudienceScene
    /// The scene being dissolved away, underneath. Nil when nothing is fading.
    @State private var outgoing: AudienceScene?
    @State private var shownOpacity = 1.0

    init(coordinator: PresentationCoordinator) {
        self.coordinator = coordinator
        _shown = State(initialValue: coordinator.audienceScene)
    }

    var body: some View {
        ZStack {
            Color.black
            if let outgoing {
                SlideRenderView(scene: outgoing)
            }
            // The incoming slide is opaque, so fading it in over the old one is a true cross-dissolve.
            SlideRenderView(scene: shown)
                .opacity(shownOpacity)
        }
        .ignoresSafeArea()
        .onChange(of: coordinator.audienceScene) { _, scene in present(scene) }
    }

    /// Only a different slide with a dissolve fades in. Cuts, clear, blackout and re-taking the same
    /// slide are always instant; a new change mid-fade starts from what's on screen now.
    private func present(_ scene: AudienceScene) {
        guard case .slide(let incoming) = scene, let transition = incoming.slide.transition,
              case .slide(let current) = shown, current.slide.id != incoming.slide.id else {
            outgoing = nil
            shown = scene
            shownOpacity = 1
            return
        }
        outgoing = shown
        shown = scene
        shownOpacity = 0
        withAnimation(.easeInOut(duration: transition.duration)) {
            shownOpacity = 1
        } completion: {
            // Only clear the layer this fade added; a newer change may already have replaced it.
            if shown == scene { outgoing = nil }
        }
    }
}
