import SwiftUI

/// Settings › Audio: which sound output music, audio cues and video sound play through on this Mac.
struct AudioSettingsView: View {
    @Bindable var output: AudioOutput

    var body: some View {
        Form {
            Picker("Play sound through", selection: Binding(
                get: { output.chosenUID },
                set: { uid in output.choose(output.devices.first { $0.uid == uid }) }
            )) {
                Text("The Mac's sound output").tag(String?.none)
                Divider()
                ForEach(output.devices) { device in
                    Text(device.name).tag(Optional(device.uid))
                }
                if output.isChosenMissing, let uid = output.chosenUID {
                    Text("\(output.chosenName ?? "Chosen output") (not connected)").tag(Optional(uid))
                }
            }
            Text(output.isChosenMissing
                 ? "That output isn't connected, so sound plays through the Mac's output until it's back."
                 : "Music, audio cues, soundtracks and video sound. Choose the interface that feeds the sound desk, so a Bluetooth headset or a change to the Mac's sound settings can't take the service's sound elsewhere. Kept on this Mac.")
                .font(.caption)
                .foregroundStyle(output.isChosenMissing ? Palette.warning : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
