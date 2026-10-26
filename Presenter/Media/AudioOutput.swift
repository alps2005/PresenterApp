import CoreAudio
import Foundation
import Observation
import PresenterCore

/// The sound outputs this Mac has, and which one Presenter plays music, audio cues and video sound through. Chosen in
/// Settings and kept per Mac (like the output screens). A chosen device that's unplugged falls back to the Mac's
/// output until it's back.
@Observable
final class AudioOutput {
    struct Device: Identifiable, Hashable {
        /// Core Audio's unique ID, stable across launches and reconnections.
        let uid: String
        let name: String
        var id: String { uid }
    }

    private(set) var devices: [Device] = []
    /// The chosen device's unique ID; nil follows the Mac's sound output.
    var chosenUID: String? {
        didSet { defaults.set(chosenUID, forKey: Self.chosenKey) }
    }

    /// The device to play through now: the chosen one while it's connected, else nil (the Mac's output).
    var effectiveUID: String? {
        AudioDeviceChoice.resolve(saved: chosenUID, available: devices.map(\.uid))
    }

    /// The chosen device isn't connected, so sound goes to the Mac's output.
    var isChosenMissing: Bool {
        AudioDeviceChoice.isMissing(saved: chosenUID, available: devices.map(\.uid))
    }

    /// The chosen device's name, remembered so a missing one can still be named.
    var chosenName: String? {
        guard let chosenUID else { return nil }
        return devices.first { $0.uid == chosenUID }?.name ?? defaults.string(forKey: Self.chosenNameKey)
    }

    static let chosenKey = "audioOutputDeviceUID"
    private static let chosenNameKey = "audioOutputDeviceName"
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        chosenUID = defaults.string(forKey: Self.chosenKey)
        refresh()
        var address = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func choose(_ device: Device?) {
        chosenUID = device?.uid
        defaults.set(device?.name, forKey: Self.chosenNameKey)
    }

    private func refresh() {
        devices = Self.outputDevices().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Core Audio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Every device that can play sound (has output streams).
    private static func outputDevices() -> [Device] {
        var address = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Device(uid: uid, name: name)
        }
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
