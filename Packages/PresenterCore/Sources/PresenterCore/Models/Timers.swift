import Foundation

/// A timer shown on the stage display (and later in messages), like ProPresenter's timers.
public struct TimerDefinition: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        /// Counts down from a duration once started; goes negative (overrun) after zero.
        case countdown(seconds: Int)
        /// Counts down to a time of day, e.g. the service start. Always running.
        case countdownTo(hour: Int, minute: Int)
        /// Counts up once started.
        case elapsed
    }

    public let id: UUID
    public var name: String
    public var kind: Kind

    public init(id: UUID = UUID(), name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    /// The timers a new project starts with.
    public static func defaults() -> [TimerDefinition] {
        [
            TimerDefinition(name: "Service Starts", kind: .countdownTo(hour: 10, minute: 0)),
            TimerDefinition(name: "Sermon", kind: .countdown(seconds: 30 * 60)),
        ]
    }

    /// A countdown-to-time timer runs on the clock; start, stop and reset don't apply.
    public var followsClock: Bool {
        if case .countdownTo = kind { return true }
        return false
    }

    /// The value to show at `now`: seconds remaining for countdowns (negative once overrun), or seconds
    /// elapsed for an elapsed timer.
    public func seconds(run: TimerRun, now: Date, calendar: Calendar = .current) -> Int {
        switch kind {
        case .countdown(let total):
            return total - Int(run.elapsed(at: now).rounded(.down))
        case .elapsed:
            return Int(run.elapsed(at: now).rounded(.down))
        case .countdownTo(let hour, let minute):
            guard var target = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return 0 }
            // A target more than 12 hours ago means tomorrow (e.g. counting to 00:30 at 23:50); one less than
            // 12 hours ago has just passed and shows as overrun.
            if target.timeIntervalSince(now) < -12 * 3600, let tomorrow = calendar.date(byAdding: .day, value: 1, to: target) {
                target = tomorrow
            }
            return Int(target.timeIntervalSince(now).rounded(.up))
        }
    }

    /// "4:05", "1:02:03", or "-0:42" when overrun.
    public static func format(_ seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : ""
        let value = abs(seconds)
        let hours = value / 3600, minutes = (value % 3600) / 60, secs = value % 60
        return hours > 0
            ? String(format: "%@%d:%02d:%02d", sign, hours, minutes, secs)
            : String(format: "%@%d:%02d", sign, minutes, secs)
    }
}

/// A timer's running state. Not saved: timers start stopped after a relaunch.
public struct TimerRun: Equatable, Sendable {
    /// When the current run began; nil while stopped.
    public var startedAt: Date?
    /// Time accumulated by earlier runs (stop/start pauses and resumes).
    public var accumulated: TimeInterval

    public init(startedAt: Date? = nil, accumulated: TimeInterval = 0) {
        self.startedAt = startedAt
        self.accumulated = accumulated
    }

    public var isRunning: Bool { startedAt != nil }

    public func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}

/// What the stage display shows besides the slides.
public struct StageSettings: Codable, Hashable, Sendable {
    /// The timer shown on stage, if any.
    public var timerID: UUID?
    public var showsClock: Bool
    public var showsNotes: Bool

    public init(timerID: UUID? = nil, showsClock: Bool = true, showsNotes: Bool = true) {
        self.timerID = timerID
        self.showsClock = showsClock
        self.showsNotes = showsNotes
    }
}
