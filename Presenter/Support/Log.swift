import os

enum Log {
    private static let subsystem = "io.github.alps2005.Presenter"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let output = Logger(subsystem: subsystem, category: "Output")
}
