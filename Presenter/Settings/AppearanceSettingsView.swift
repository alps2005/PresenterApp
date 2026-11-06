import PresenterCore
import SwiftUI

/// Settings › Appearance: dark or light, text size, and the colours for LIVE, CUED and each kind of song section.
/// Changes show straight away in every window.
struct AppearanceSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Presenter is dark unless you choose otherwise, so it stays quiet in a dark room.")
                    .settingsNote()
            }

            Section {
                Picker("Text size", selection: $settings.textSize) {
                    ForEach(AppSettings.TextSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("The text in Presenter's windows. Slides, the audience output and the stage display keep their own sizes.")
                    .settingsNote()
            }

            Section("Live and Cued") {
                ColorPicker("Live", selection: Binding(get: { settings.liveColor }, set: { settings.setLiveColor($0) }),
                            supportsOpacity: false)
                ColorPicker("Cued", selection: Binding(get: { settings.cuedColor }, set: { settings.setCuedColor($0) }),
                            supportsOpacity: false)
                Text("Outlines and badges for what's on the audience output now, and what goes live next. Keep them easy to tell apart.")
                    .settingsNote()
            }

            Section("Song Sections") {
                ForEach(AppSettings.sectionKinds, id: \.key) { kind in
                    ColorPicker(selection: Binding(get: { settings.color(for: kind) }, set: { settings.setColor($0, for: kind) }),
                                supportsOpacity: false) {
                        Text(AppSettings.title(for: kind))
                            .font(.ui(.caption2).bold())
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(settings.color(for: kind), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text("The labels on slide thumbnails, such as Verse 1 or Coro. Spanish names (Verso, Coro, Puente…) get the same colours.")
                    .settingsNote()
            }

            Section {
                HStack {
                    Text("Kept on this Mac, not in the project.")
                        .settingsNote()
                    Spacer()
                    Button("Restore Defaults") { settings.resetToDefaults() }
                        .disabled(!settings.isCustomized)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

extension Text {
    /// The small grey explanation under a setting.
    func settingsNote() -> some View {
        font(.ui(.caption))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
