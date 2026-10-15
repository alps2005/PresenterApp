import os

/// The core's loggers, under the app's subsystem so Console shows them together.
enum Log {
    static let coordinator = Logger(subsystem: "io.github.alps2005.Presenter", category: "PresentationCoordinator")
}
