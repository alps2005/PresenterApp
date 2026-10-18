import SwiftUI
import PresenterCore

// Automatic advancing (Slideshow and Go To Next timers): the controls that set it and the countdown the operator sees.

enum AdvanceTime {
    /// "8 s", "1.5 s", "2:00".
    static func label(_ seconds: Double) -> String {
        if seconds >= 60 { return TimerDefinition.format(Int(seconds.rounded())) }
        return "\(seconds.formatted(.number.precision(.fractionLength(0...1)))) s"
    }

    /// Slideshow intervals offered in the presentation header.
    static let slideshowPresets: [Double] = [5, 8, 10, 15, 30]
}

/// A thumbnail's timer: the time it stays up, and on the live slide a pie that fills as the countdown runs.
struct AdvanceBadge: View {
    let seconds: Double
    /// Set on the live slide while its countdown runs.
    let advance: AutoAdvance?

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            if let advance {
                if case .waitingForVideo = advance.phase {
                    Image(systemName: "film")
                        .help("Moves on when the video ends")
                } else {
                    // Only the live thumbnail redraws, and only while it counts down.
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        CountdownPie(progress: advance.progress(at: context.date) ?? 0)
                    }
                    .frame(width: 11, height: 11)
                }
            } else {
                Image(systemName: "timer")
            }
            Text(AdvanceTime.label(seconds)).monospacedDigit()
        }
        .foregroundStyle(advance == nil ? Color.secondary : Palette.live)
        .help(advance == nil ? "Moves on by itself after \(AdvanceTime.label(seconds))" : "Moving on by itself")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Moves on after \(AdvanceTime.label(seconds))")
    }
}

/// A circle that fills clockwise from the top.
struct CountdownPie: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().strokeBorder(lineWidth: 1.2)
            PieSlice(progress: progress).padding(2)
        }
    }

    nonisolated private struct PieSlice: Shape {
        let progress: Double

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            path.move(to: center)
            path.addArc(center: center, radius: min(rect.width, rect.height) / 2,
                        startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * progress), clockwise: false)
            path.closeSubpath()
            return path
        }
    }
}

/// In the live panel: when the live slide moves on, and a button to stop it.
struct AutoAdvanceStatus: View {
    let coordinator: PresentationCoordinator

    var body: some View {
        if let advance = coordinator.state.autoAdvance {
            HStack(spacing: Spacing.sm) {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    if let left = advance.secondsLeft(at: context.date) {
                        Label("Next slide in \(TimerDefinition.format(left))", systemImage: "timer")
                            .monospacedDigit()
                    } else {
                        Label("Next slide when the video ends", systemImage: "film")
                    }
                }
                .font(.callout)
                Spacer(minLength: Spacing.sm)
                Button("Stop") { coordinator.stopAutoAdvance() }
                    .controlSize(.small)
                    .help("Stop moving on by itself (⌥⌘.). The next slide you take live starts its own timer.")
            }
        }
    }
}

/// A slide's Go To Next timer: on or off, its time, and whether it loops to the first slide.
struct GoToNextControls: View {
    @Binding var timer: GoToNextTimer?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle("Go to the next slide after", isOn: Binding(
                get: { timer != nil },
                set: { timer = $0 ? (timer ?? GoToNextTimer(seconds: 10)) : nil }
            ))
            if let current = timer {
                HStack(spacing: Spacing.sm) {
                    TextField("Seconds", value: Binding(
                        get: { current.seconds },
                        set: { timer?.seconds = max(0, $0) }
                    ), format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Seconds")
                    Stepper("seconds", value: Binding(
                        get: { current.seconds },
                        set: { timer?.seconds = max(0, $0) }
                    ), in: 0...3600, step: 1)
                }
                Toggle("Loop to the first slide", isOn: Binding(
                    get: { current.loopsToFirst },
                    set: { timer?.loopsToFirst = $0 }
                ))
                Text(current.seconds == 0
                     ? "0 moves on as soon as the slide's video ends (with a video that plays once)."
                     : "A video that plays once is waited for first; a looping one isn't.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Right-click a slide › Go To Next Timer….
struct GoToNextSheet: View {
    let coordinator: PresentationCoordinator
    let slideID: UUID
    let presentationID: UUID
    @State private var timer: GoToNextTimer?
    @Environment(\.dismiss) private var dismiss

    init(coordinator: PresentationCoordinator, slideID: UUID, presentationID: UUID) {
        self.coordinator = coordinator
        self.slideID = slideID
        self.presentationID = presentationID
        let slide = coordinator.project.presentation(withID: presentationID)?.slide(withID: slideID)
        _timer = State(initialValue: slide?.goToNext ?? GoToNextTimer(seconds: 10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Go To Next Timer").font(.headline)
            GoToNextControls(timer: $timer)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    coordinator.setGoToNext(timer, forSlides: [slideID], inPresentation: presentationID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 340)
    }
}

/// The presentation header's Slideshow menu › Custom….
struct SlideshowIntervalSheet: View {
    let coordinator: PresentationCoordinator
    let presentationID: UUID
    @State private var seconds: Double
    @Environment(\.dismiss) private var dismiss

    init(coordinator: PresentationCoordinator, presentationID: UUID) {
        self.coordinator = coordinator
        self.presentationID = presentationID
        _seconds = State(initialValue: coordinator.project.presentation(withID: presentationID)?.slideshowInterval ?? 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Slideshow").font(.headline)
            HStack(spacing: Spacing.sm) {
                Text("Every slide moves on after")
                TextField("Seconds", value: $seconds, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Seconds")
                Text("seconds")
            }
            Text("After the last slide it starts again from the first. A slide's own Go To Next Timer comes first.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Start Slideshow") {
                    coordinator.setSlideshowInterval(seconds, presentation: presentationID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 380)
    }
}
