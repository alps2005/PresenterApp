import AppKit
import PresenterCore

enum DisplayDiscovery {
    static func currentDisplays() -> [DisplayInfo] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let id = displayID(of: screen) else { return nil }
            let identity = DisplayIdentity(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                           serial: CGDisplaySerialNumber(id), name: screen.localizedName)
            return DisplayInfo(id: id, name: screen.localizedName, frame: screen.frame, isPrimary: index == 0, identity: identity)
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { self.displayID(of: $0) == displayID }
    }
}
