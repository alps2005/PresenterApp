import AppKit
import os
import SwiftUI

/// Owns one output NSWindow (audience or stage). Its lifetime belongs to `OutputManager`, never to a SwiftUI view.
final class OutputWindowController: NSObject, NSWindowDelegate {
    private enum Mode: Equatable {
        case windowed
        case fullScreen(CGDirectDisplayID)
    }

    private let title: String
    private let makeContent: () -> AnyView
    private var window: NSWindow?
    private var mode: Mode?

    /// Called when the operator closes the windowed output with its close button.
    var onUserClosedWindow: (() -> Void)?

    init(title: String, makeContent: @escaping () -> AnyView) {
        self.title = title
        self.makeContent = makeContent
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
        window.title = title
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.delegate = self
        window.center()
        window.orderFront(nil)
        self.window = window
        mode = .windowed
        Log.output.info("Showing \(self.title, privacy: .public) in a window")
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
        window.title = title
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        self.window = window
        mode = .fullScreen(displayID)
        Log.output.info("Showing \(self.title, privacy: .public) full screen on \(screen.localizedName, privacy: .public)")
    }

    func hide() {
        guard window != nil else { return }
        tearDown()
        Log.output.info("\(self.title, privacy: .public) hidden")
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
        let hostingView = NSHostingView(rootView: makeContent())
        // The window decides its size; SwiftUI content must not resize it.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        return window
    }
}
