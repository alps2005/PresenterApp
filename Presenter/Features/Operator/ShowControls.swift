import SwiftUI
import PresenterCore

/// Like ProPresenter's show controls: timers, and what the stage display shows.
/// Text is entered in popovers, never in fields that stay in the window, so Space and the arrow keys keep
/// driving the slides.
struct ShowControls: View {
    enum Tab: String, CaseIterable, Identifiable {
        case timers = "Timers"
        case stage = "Stage"
        var id: Self { self }
    }

    let coordinator: PresentationCoordinator
    let outputManager: OutputManager
    @AppStorage("showControlsTab") private var tab: Tab = .timers

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Show Controls", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .timers: TimersTab(coordinator: coordinator)
            case .stage: StageTab(coordinator: coordinator, outputManager: outputManager)
            }
        }
        .controlSize(.small)
    }
}

// MARK: - Timers

private struct TimersTab: View {
    let coordinator: PresentationCoordinator
    @State private var editing: TimerDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                VStack(spacing: 6) {
                    ForEach(coordinator.project.timers) { timer in
                        row(timer, now: context.date)
                    }
                }
            }
            Button {
                editing = TimerDraft(timer: nil)
            } label: {
                Label("New Timer", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .popover(item: Binding(get: { editing?.timer == nil ? editing : nil }, set: { editing = $0 })) { draft in
                TimerEditor(coordinator: coordinator, draft: draft) { editing = nil }
            }
        }
    }

    private func row(_ timer: TimerDefinition, now: Date) -> some View {
        let run = coordinator.timerRun(for: timer.id)
        let seconds = coordinator.timerSeconds(timer.id, at: now) ?? 0
        let isOnStage = coordinator.project.stage.timerID == timer.id
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(timer.name).lineLimit(1)
                    if isOnStage {
                        Image(systemName: "rectangle.on.rectangle").foregroundStyle(.secondary).help("Shown on the stage display")
                    }
                }
                Text(timer.summary).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(TimerDefinition.format(seconds))
                .font(.body.monospacedDigit().bold())
                .foregroundStyle(seconds < 0 && timer.isCountdown ? .red : .primary)
            if !timer.followsClock {
                Button {
                    run.isRunning ? coordinator.stopTimer(timer.id) : coordinator.startTimer(timer.id)
                } label: {
                    Image(systemName: run.isRunning ? "pause.fill" : "play.fill")
                }
                .help(run.isRunning ? "Pause" : "Start")
                Button {
                    coordinator.resetTimer(timer.id)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset")
            }
            Menu {
                Button(isOnStage ? "Hide on Stage Display" : "Show on Stage Display") {
                    var settings = coordinator.project.stage
                    settings.timerID = isOnStage ? nil : timer.id
                    coordinator.setStageSettings(settings)
                }
                Button("Edit…") { editing = TimerDraft(timer: timer) }
                Divider()
                Button("Delete", role: .destructive) { coordinator.deleteTimer(timer.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .popover(item: Binding(get: { editing?.timer?.id == timer.id ? editing : nil }, set: { editing = $0 })) { draft in
                TimerEditor(coordinator: coordinator, draft: draft) { editing = nil }
            }
        }
        .padding(8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct TimerDraft: Identifiable {
    let timer: TimerDefinition?
    var id: String { timer?.id.uuidString ?? "new" }
}

private struct TimerEditor: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case countdown = "Countdown"
        case countdownTo = "Count to Time"
        case elapsed = "Elapsed"
        var id: Self { self }
    }

    let coordinator: PresentationCoordinator
    let draft: TimerDraft
    let onDone: () -> Void

    @State private var name = ""
    @State private var kind: Kind = .countdown
    @State private var minutes = 5
    @State private var seconds = 0
    @State private var time = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.timer == nil ? "New Timer" : "Edit Timer").font(.headline)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            Picker("Type", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch kind {
            case .countdown:
                HStack {
                    Stepper("\(minutes) min", value: $minutes, in: 0...600)
                    Stepper("\(seconds) s", value: $seconds, in: 0...59, step: 5)
                }
            case .countdownTo:
                DatePicker("Counts down to", selection: $time, displayedComponents: .hourAndMinute)
            case .elapsed:
                Text("Counts up from zero when started.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDone() }
                Button(draft.timer == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { load() }
    }

    private var timerKind: TimerDefinition.Kind {
        switch kind {
        case .countdown: return .countdown(seconds: minutes * 60 + seconds)
        case .elapsed: return .elapsed
        case .countdownTo:
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            return .countdownTo(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        }
    }

    private func load() {
        guard let timer = draft.timer else { return }
        name = timer.name
        switch timer.kind {
        case .countdown(let total):
            kind = .countdown
            minutes = total / 60
            seconds = total % 60
        case .countdownTo(let hour, let minute):
            kind = .countdownTo
            time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? time
        case .elapsed:
            kind = .elapsed
        }
    }

    private func save() {
        if var timer = draft.timer {
            timer.name = name.isEmpty ? timer.name : name
            timer.kind = timerKind
            coordinator.updateTimer(timer)
        } else {
            coordinator.addTimer(name: name, kind: timerKind)
        }
        onDone()
    }
}

extension TimerDefinition {
    var isCountdown: Bool {
        if case .elapsed = kind { return false }
        return true
    }

    var summary: String {
        switch kind {
        case .countdown(let seconds): "Countdown · \(TimerDefinition.format(seconds))"
        case .countdownTo(let hour, let minute): "Counts to \(String(format: "%d:%02d", hour, minute))"
        case .elapsed: "Elapsed"
        }
    }
}

// MARK: - Stage

private struct StageTab: View {
    let coordinator: PresentationCoordinator
    let outputManager: OutputManager
    @State private var isComposing = false
    @State private var draftMessage = ""

    var body: some View {
        let settings = coordinator.project.stage
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(stageStatus, systemImage: "rectangle.on.rectangle")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(outputManager.isEnabled(.stage) ? "Hide" : "Show") { outputManager.toggle(.stage) }
                    .help("Show or hide the stage display (⌥⌘D). Choose its screen in the Output menu.")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Message to the stage").font(.caption.bold())
                if let message = coordinator.state.stageMessage {
                    HStack {
                        Text(message)
                            .lineLimit(2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.yellow.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.black)
                        Spacer()
                        Button("Hide") { coordinator.hideStageMessage() }
                    }
                }
                Button(coordinator.state.stageMessage == nil ? "Send Message…" : "Change Message…") {
                    draftMessage = coordinator.state.stageMessage ?? ""
                    isComposing = true
                }
                .popover(isPresented: $isComposing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Message to the stage").font(.headline)
                        TextField("e.g. 5 minutes left", text: $draftMessage, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                        HStack {
                            Spacer()
                            Button("Cancel", role: .cancel) { isComposing = false }
                            Button("Show on Stage") {
                                coordinator.showStageMessage(draftMessage)
                                isComposing = false
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(16)
                    .frame(width: 320)
                }
            }

            Picker("Timer", selection: Binding(
                get: { settings.timerID },
                set: { id in
                    var updated = settings
                    updated.timerID = id
                    coordinator.setStageSettings(updated)
                }
            )) {
                Text("None").tag(UUID?.none)
                ForEach(coordinator.project.timers) { Text($0.name).tag(Optional($0.id)) }
            }
            Toggle("Clock", isOn: Binding(
                get: { settings.showsClock },
                set: { value in
                    var updated = settings
                    updated.showsClock = value
                    coordinator.setStageSettings(updated)
                }
            ))
            Toggle("Slide notes", isOn: Binding(
                get: { settings.showsNotes },
                set: { value in
                    var updated = settings
                    updated.showsNotes = value
                    coordinator.setStageSettings(updated)
                }
            ))
            Text("The stage display shows the live slide's words, the next slide, and these. The audience never sees them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stageStatus: String {
        switch outputManager.status(.stage) {
        case .off: "Stage display off"
        case .windowed: "Stage display in a window"
        case .fullScreen(let name): "Stage display on \(name)"
        case .displayMissing(let name): "\(name) disconnected"
        }
    }
}
