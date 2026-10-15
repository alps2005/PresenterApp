import SwiftUI
import PresenterCore

/// What the people on stage see: the live slide's words, what's next, the clock, a timer, the operator's notes
/// and stage messages. High contrast and no backgrounds, so it reads from a distance. Never shown to the audience.
struct StageOutputView: View {
    let coordinator: PresentationCoordinator

    var body: some View {
        GeometryReader { geometry in
            // Sizes are designed for a 1080-point-tall screen and scale with the window.
            let scale = max(geometry.size.height / 1080, 0.2)
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                content(scale: scale, now: context.date)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    private func content(scale: CGFloat, now: Date) -> some View {
        let settings = coordinator.project.stage
        let live = coordinator.state.live?.slide
        let next = coordinator.upNextSlide?.slide
        return VStack(alignment: .leading, spacing: 24 * scale) {
            HStack(alignment: .firstTextBaseline) {
                if settings.showsClock {
                    Text(now, format: .dateTime.hour().minute().second())
                        .font(.system(size: 72 * scale, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer()
                if let timerID = settings.timerID, let timer = coordinator.timer(withID: timerID),
                   let seconds = coordinator.timerSeconds(timerID, at: now) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(timer.name.uppercased())
                            .font(.system(size: 26 * scale, weight: .bold))
                            .foregroundStyle(.gray)
                        Text(TimerDefinition.format(seconds))
                            .font(.system(size: 72 * scale, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(seconds < 0 && !isElapsed(timer) ? .red : .white)
                    }
                }
            }

            if let message = coordinator.state.stageMessage {
                Text(message)
                    .font(.system(size: 54 * scale, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24 * scale)
                    .padding(.vertical, 12 * scale)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow, in: RoundedRectangle(cornerRadius: 12 * scale))
            }

            Text(live.map(words) ?? "")
                .font(.system(size: 92 * scale, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let next {
                VStack(alignment: .leading, spacing: 6 * scale) {
                    Text("NEXT" + (next.label.map { " · \($0.uppercased())" } ?? ""))
                        .font(.system(size: 26 * scale, weight: .bold))
                        .foregroundStyle(.gray)
                    Text(words(next))
                        .font(.system(size: 52 * scale, weight: .semibold))
                        .foregroundStyle(.yellow)
                        .lineLimit(3)
                        .minimumScaleFactor(0.4)
                }
            }

            if settings.showsNotes, let notes = coordinator.liveNotes {
                Text(notes)
                    .font(.system(size: 40 * scale, weight: .medium))
                    .foregroundStyle(.cyan)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(48 * scale)
    }

    private func words(_ slide: SlideDocument) -> String {
        let text = slide.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "—" : text
    }

    private func isElapsed(_ timer: TimerDefinition) -> Bool {
        if case .elapsed = timer.kind { return true }
        return false
    }
}
