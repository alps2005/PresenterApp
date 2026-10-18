import SwiftUI
import PresenterCore

/// Edits a theme: its name, the look and position of each text role, and its background, with a live preview.
/// Changes apply as they're made (and undo with ⌘Z); every slide following the theme updates.
struct ThemeEditorSheet: View {
    let coordinator: PresentationCoordinator
    let themeID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var role: TextRole = .body

    private var theme: Theme? { coordinator.project.theme(withID: themeID) }

    /// How many presentations follow the theme, for the footer.
    private var followers: Int {
        coordinator.project.presentations.filter { $0.themeID == themeID }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let theme {
                Text("Edit Theme").font(.title2.bold())
                TextField("Name", text: Binding(get: { theme.name }, set: { rename(to: $0) }))
                    .textFieldStyle(.roundedBorder)

                HStack(alignment: .top, spacing: Spacing.xl) {
                    controls(theme)
                        .frame(width: 300)
                    preview(theme)
                }

                HStack {
                    Text(followersText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                ContentUnavailableView("Theme Deleted", systemImage: "paintpalette")
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 820)
    }

    private var followersText: String {
        switch followers {
        case 0: "No presentation uses this theme yet. Choose it in a presentation's Document settings in the editor."
        case 1: "1 presentation uses this theme. Its slides change as you edit."
        default: "\(followers) presentations use this theme. Their slides change as you edit."
        }
    }

    private func controls(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Picker("Text", selection: $role) {
                Text("Title").tag(TextRole.title)
                Text("Body").tag(TextRole.body)
                Text("Caption").tag(TextRole.caption)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            TextStyleControls(style: Binding(
                get: { theme[role].style },
                set: { style in edit { $0[role].style = style } }
            ), layout: .narrow)

            TextPositionControls(box: theme[role].box, alignment: theme[role].style.alignment) { box, alignment in
                edit { theme in
                    theme[role].box = box
                    theme[role].style.alignment = alignment
                }
            }

            Divider()
            Text("Background").font(.subheadline.bold())
            BackgroundInspector(coordinator: coordinator, target: .theme(themeID))
        }
        .controlSize(.small)
    }

    /// All three text roles together, as a slide would show them, and each on its own below: click one to edit it.
    private func preview(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Preview").font(.subheadline.bold()).foregroundStyle(.secondary)
            SlideRenderView(scene: .slide(Self.sample(TextRole.allCases, theme: theme)))
                .aspectRatio(16 / 9, contentMode: .fit)
                // The column's full width, not whatever height is left over.
                .fixedSize(horizontal: false, vertical: true)
                .tileFrame(.idle)
                .accessibilityLabel("Preview of the theme's title, body and caption text")
            HStack(spacing: Spacing.md) {
                ForEach(TextRole.allCases, id: \.self) { each in
                    Button { role = each } label: {
                        VStack(spacing: Spacing.xs) {
                            SlideRenderView(scene: .slide(Self.sample([each], theme: theme)))
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .fixedSize(horizontal: false, vertical: true)
                                .tileFrame(.idle)
                                .overlay {
                                    if each == role {
                                        RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Color.accentColor, lineWidth: 3)
                                    }
                                }
                            Text(Self.name(of: each))
                                .font(.caption)
                                .fontWeight(each == role ? .semibold : .regular)
                                .foregroundStyle(each == role ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Edit the \(Self.name(of: each)) text")
                    .accessibilityAddTraits(each == role ? .isSelected : [])
                }
            }
            Text("Text formatted by hand on a slide keeps its own look. In the editor, Revert to Theme makes it follow the theme again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func name(of role: TextRole) -> String {
        switch role {
        case .title: "Title"
        case .body: "Body"
        case .caption: "Caption"
        }
    }

    /// A slide with sample words in the given roles, drawn with the theme.
    private static func sample(_ roles: [TextRole], theme: Theme) -> RenderedSlide {
        // Psalm 96:1 in the King James Version, which is in the public domain.
        let elements: [SlideElement] = roles.map { role in
            let text = switch role {
            case .title: "Welcome"
            case .body: "O sing unto the LORD a new song:\nsing unto the LORD, all the earth."
            case .caption: "Psalm 96:1"
            }
            return .text(TextElement(text: text, role: role))
        }
        let slide = SlideDocument(elements: elements)
        return PresentationDocument(title: "", slides: [slide]).rendered(slide, theme: theme)
    }

    private func rename(to name: String) {
        edit { $0.name = name }
    }

    private func edit(_ change: (inout Theme) -> Void) {
        guard var theme else { return }
        change(&theme)
        coordinator.updateTheme(theme)
    }
}
