import AppKit

/// A connected display. `id` is stable while the display stays connected, but not guaranteed across launches;
/// persisting the selected display needs a durable identity (planned with output configuration storage).
struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let frame: CGRect
    /// The display with the menu bar.
    let isPrimary: Bool

    var resolutionDescription: String {
        "\(Int(frame.width))×\(Int(frame.height))"
    }
}

enum DisplayDiscovery {
    static func currentDisplays() -> [DisplayInfo] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let id = displayID(of: screen) else { return nil }
            return DisplayInfo(id: id, name: screen.localizedName, frame: screen.frame, isPrimary: index == 0)
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { self.displayID(of: $0) == displayID }
    }
}
