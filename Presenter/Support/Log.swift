import os

enum Log {
    private nonisolated static let subsystem = "io.github.alps2005.Presenter"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let output = Logger(subsystem: subsystem, category: "Output")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    /// Debug builds only: a panel whose content is wider than its column (`overflowGuard`).
    /// Nonisolated: SwiftUI calls a `Layout` off the main actor's isolation.
    nonisolated static let layout = Logger(subsystem: subsystem, category: "Layout")
}
