import Foundation
import PresenterCore

// The C interface the Windows app calls (Windows/Presenter.Windows.Core/Engine.cs). Strings are UTF-8 and
// NUL-terminated. Every string the engine returns is the caller's to release with presenter_free.
//
// The engine runs on the main actor, which isn't thread-safe. The app makes every call from its UI thread (it checks
// before each call), so one thread uses the engine at a time and the calls run it directly, as the Mac app's views do.

/// The language the engine's messages, undo names and new things' names are in: "en" or "es" (anything else is
/// English). Called before `presenter_open`, so a new project's first show is named in it too.
@_cdecl("presenter_set_language")
public func presenter_set_language(_ code: UnsafePointer<CChar>?) {
    let text = code.map { String(cString: $0) } ?? ""
    Localization.language = AppLanguage.preferred(from: [text])
}

/// Opens the project in a data folder (created if needed) and returns a handle for the other calls.
@_cdecl("presenter_open")
public func presenter_open(_ dataDirectory: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let dataDirectory else { return nil }
    let url = URL(fileURLWithPath: String(cString: dataDirectory), isDirectory: true)
    let session = onMainActor { BridgeSession(dataDirectory: url) }
    return Unmanaged.passRetained(session).toOpaque()
}

/// Runs a command, given as JSON (see BridgeCommand), and returns the reply as JSON.
@_cdecl("presenter_send")
public func presenter_send(_ handle: UnsafeMutableRawPointer?, _ command: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let session = session(handle), let command else { return nil }
    let json = String(cString: command)
    return makeCString(onMainActor { session.send(json) })
}

/// Returns everything the app draws, as JSON (see BridgeState).
@_cdecl("presenter_state")
public func presenter_state(_ handle: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>? {
    guard let session = session(handle) else { return nil }
    return makeCString(onMainActor { session.stateJSON() })
}

/// Called a few times a second: moves the live slide on when its countdown ends. Returns 1 when the app should
/// read the state again, else 0.
@_cdecl("presenter_tick")
public func presenter_tick(_ handle: UnsafeMutableRawPointer?) -> Int32 {
    guard let session = session(handle) else { return 0 }
    return onMainActor { session.tick() } ? 1 : 0
}

/// Saves anything unsaved and closes the project. The handle can't be used afterwards.
@_cdecl("presenter_close")
public func presenter_close(_ handle: UnsafeMutableRawPointer?) {
    guard let handle else { return }
    let session = Unmanaged<BridgeSession>.fromOpaque(handle).takeRetainedValue()
    onMainActor { session.saveIfChanged() }
}

/// Releases a string the engine returned.
@_cdecl("presenter_free")
public func presenter_free(_ string: UnsafeMutablePointer<CChar>?) {
    string?.deallocate()
}

/// The project format this engine reads and writes, so the app can say which Mac version matches.
@_cdecl("presenter_schema_version")
public func presenter_schema_version() -> Int32 {
    Int32(ProjectDocument.currentSchemaVersion)
}

private func session(_ handle: UnsafeMutableRawPointer?) -> BridgeSession? {
    handle.map { Unmanaged<BridgeSession>.fromOpaque($0).takeUnretainedValue() }
}

/// Runs main-actor code from a C call. A main-actor function has the same calling convention as a plain one, so
/// this calls it directly. That's safe only because every call comes from the app's one UI thread (see the top).
func onMainActor<T>(_ body: @MainActor () -> T) -> T {
    withoutActuallyEscaping(body) { body in
        unsafeBitCast(body, to: (() -> T).self)()
    }
}

/// A copy of `string` as a NUL-terminated UTF-8 C string, released with presenter_free.
func makeCString(_ string: String) -> UnsafeMutablePointer<CChar> {
    let bytes = string.utf8CString
    let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
    bytes.withUnsafeBufferPointer { pointer.initialize(from: $0.baseAddress!, count: bytes.count) }
    return pointer
}
