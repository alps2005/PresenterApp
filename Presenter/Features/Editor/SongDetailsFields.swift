import PresenterCore
import SwiftUI

/// A presentation's song credits: writers, copyright and CCLI song number. Each field saves when the operator presses
/// Return or leaves it, not at every keystroke: writers are split at commas, which would eat the comma being typed.
struct SongDetailsFields: View {
    let coordinator: PresentationCoordinator
    let presentation: PresentationDocument

    @State private var authors = ""
    @State private var copyright = ""
    @State private var ccliNumber = ""
    @FocusState private var focused: Field?

    private enum Field {
        case authors, copyright, ccliNumber
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.sm, verticalSpacing: Spacing.sm) {
            row("Writers", text: $authors, prompt: "Separated by commas", field: .authors)
            row("Copyright", text: $copyright, prompt: "Year and holder", field: .copyright)
            row("CCLI #", text: $ccliNumber, prompt: "Song number", field: .ccliNumber)
        }
        .textFieldStyle(.roundedBorder)
        .onSubmit(save)
        .onChange(of: focused) { _, _ in save() }
        .onAppear(perform: load)
        .onChange(of: presentation.id) { _, _ in load() }
        // Undo, or a change made elsewhere, shows here unless the operator is typing.
        .onChange(of: presentation.song) { _, _ in if focused == nil { load() } }
        .onDisappear(perform: save)
    }

    private func row(_ label: String, text: Binding<String>, prompt: String, field: Field) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            TextField(label, text: text, prompt: Text(prompt))
                .labelsHidden()
                .focused($focused, equals: field)
        }
    }

    private func load() {
        show(presentation.song ?? SongInfo())
    }

    private func show(_ song: SongInfo) {
        authors = song.authorLine
        copyright = song.copyright
        ccliNumber = song.ccliNumber
    }

    private func save() {
        let info = SongInfo(authors: SongInfo.authors(from: authors), copyright: SongInfo.copyright(from: copyright),
                            ccliNumber: SongInfo.ccliNumber(from: ccliNumber))
        // Tidied as saved ("Watts, Mason," → "Watts, Mason"), and saved only if that changed anything.
        show(info)
        guard info != (presentation.song ?? SongInfo()) else { return }
        coordinator.setSongInfo(info, presentationID: presentation.id)
    }
}
