import SwiftUI
import PresenterCore

/// Paste a song's lyrics and get one slide per stanza, labelled by section (Verse, Chorus, Coro…).
struct NewSongSheet: View {
    let coordinator: PresentationCoordinator
    /// Called with the new playlist entry, so the workspace can scroll to it.
    let onAdded: (PresentationItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var lyrics = ""
    /// 0 keeps whole stanzas on one slide.
    @State private var maxLines = 0

    private var slides: [SlideDocument] {
        LyricsParser.slides(from: lyrics, maxLinesPerSlide: maxLines == 0 ? nil : maxLines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("New Song").font(.title2.bold())

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack(alignment: .top, spacing: Spacing.md) {
                TextEditor(text: $lyrics)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.sm)
                    .background(Palette.panelRaised, in: RoundedRectangle(cornerRadius: Radius.card))
                    .frame(minWidth: 320, minHeight: 300)
                    .overlay(alignment: .topLeading) {
                        if lyrics.isEmpty {
                            Text("Paste or type the lyrics here.")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, Spacing.sm + 5) // + the TextEditor's own text inset
                                .padding(.vertical, Spacing.sm)
                                .allowsHitTesting(false)
                        }
                    }

                preview
                    .frame(width: 200)
            }

            Text("A blank line starts a new slide. A line with only a section name (Verse 1, Chorus, Bridge, Verso, Coro, Puente…) isn't shown; it labels the slides after it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Picker("Lines per slide", selection: $maxLines) {
                    Text("Whole stanza").tag(0)
                    Text("2 lines").tag(2)
                    Text("3 lines").tag(3)
                    Text("4 lines").tag(4)
                }
                .fixedSize()
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Song") {
                    if let item = coordinator.addSong(title: title, lyrics: lyrics,
                                                      maxLinesPerSlide: maxLines == 0 ? nil : maxLines) {
                        onAdded(item)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(slides.isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 600)
    }

    /// The slides the lyrics will make, with their labels, so the split can be checked before adding.
    private var preview: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(slides.count == 1 ? "1 slide" : "\(slides.count) slides")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(spacing: Spacing.xs) {
                                Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                                if let label = slide.label { GroupLabelTag(label: label) }
                            }
                            .font(.caption2)
                            Text(slide.primaryText)
                                .font(.caption)
                                .lineLimit(4)
                        }
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.card))
                    }
                }
            }
        }
    }
}

/// A slide's group label ("Verse 1", "Chorus"), coloured by kind like ProPresenter's groups.
struct GroupLabelTag: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .lineLimit(1)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(SongSectionKind(label: label).color, in: Capsule())
            .foregroundStyle(.white)
    }
}

extension SongSectionKind {
    /// Kept clear of red LIVE, blue CUED and amber warnings. (EDITED shares purple with Chorus, but it's a
    /// badge with a pencil icon, not a capsule.)
    var color: Color {
        switch self {
        case .verse: .indigo
        case .preChorus: .teal
        case .chorus: .purple
        case .bridge: .brown
        case .other: .gray
        }
    }
}
