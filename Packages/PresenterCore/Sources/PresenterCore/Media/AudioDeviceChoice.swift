import Foundation

/// Where sound plays: the device the operator chose (a USB interface to the sound desk, say) while it's connected,
/// else the Mac's own output, so a missing interface never silences a service.
public enum AudioDeviceChoice {
    /// The device to play through, by unique ID, or nil for the system's output. `saved` is nil for the system's
    /// output; `available` lists the connected output devices.
    public static func resolve(saved: String?, available: [String]) -> String? {
        guard let saved, available.contains(saved) else { return nil }
        return saved
    }

    /// True when a chosen device isn't connected, so the operator can be told sound is going elsewhere.
    public static func isMissing(saved: String?, available: [String]) -> Bool {
        saved != nil && resolve(saved: saved, available: available) == nil
    }
}
