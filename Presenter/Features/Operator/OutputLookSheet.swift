import PresenterCore
import SwiftUI

/// Chooses what an audience output shows, with a preview of it: which layers, a key colour in place of the
/// background, and a theme for the words. Saved on this Mac as soon as it changes.
struct OutputLookSheet: View {
    let coordinator: PresentationCoordinator
    let outputManager: OutputManager
    let role: OutputRole
    @Environment(\.dismiss) private var dismiss

    private var look: OutputLook { outputManager.look(role) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("\(role.title) Look").font(.title2.bold())
            AudienceOutputView(coordinator: coordinator) { outputManager.look(role) }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Preview of the \(role.title)")
            Form {
                Section("Show") {
                    Toggle("Background", isOn: binding(\.showsBackground))
                    Toggle("Slide", isOn: binding(\.showsSlide))
                    Toggle("Props", isOn: binding(\.showsProps))
                    Toggle("Messages", isOn: binding(\.showsMessages))
                }
                Section {
                    Picker("Without the background", selection: Binding(
                        get: { look.keyColor == nil ? 0 : 1 },
                        set: { choice in update { $0.keyColor = choice == 0 ? nil : RGBAColor(red: 0, green: 0.69, blue: 0.25) } }
                    )) {
                        Text("Black").tag(0)
                        Text("Key colour").tag(1)
                    }
                    if let color = look.keyColor {
                        ColorPicker("Key colour", selection: Binding(
                            get: { color.color },
                            set: { new in update { $0.keyColor = RGBAColor(new) } }
                        ), supportsOpacity: false)
                    }
                } footer: {
                    Text("A key colour, like green, lets a video mixer put the words over a camera.")
                }
                .disabled(look.showsBackground)
                Section {
                    Picker("Words", selection: binding(\.themeID)) {
                        Text("As on the slide").tag(UUID?.none)
                        ForEach(coordinator.project.themes) { theme in
                            Text("In “\(theme.name)”").tag(Optional(theme.id))
                        }
                    }
                } footer: {
                    Text("Restyles the slide's words with a theme, e.g. a lower third for a livestream. Words formatted by hand keep their look.")
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Show Everything") { outputManager.setLook(.everything, for: role) }
                    .disabled(look.isEverything)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 460)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<OutputLook, Value>) -> Binding<Value> {
        Binding(get: { look[keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    private func update(_ change: (inout OutputLook) -> Void) {
        var updated = look
        change(&updated)
        outputManager.setLook(updated, for: role)
    }
}
