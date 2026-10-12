import AppKit
import SwiftUI

/// Reports which screen hosts the enclosing window, now and whenever the window moves to another screen.
struct WindowScreenReader: NSViewRepresentable {
    let onChange: (NSScreen?) -> Void

    func makeNSView(context: Context) -> ScreenTrackingView {
        let view = ScreenTrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ScreenTrackingView, context: Context) {
        nsView.onChange = onChange
    }
}

final class ScreenTrackingView: NSView {
    var onChange: ((NSScreen?) -> Void)?
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let window else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
        // Defer so observable state isn't mutated during a SwiftUI update.
        DispatchQueue.main.async { [weak self] in self?.report() }
    }

    private func report() {
        onChange?(window?.screen)
    }
}
