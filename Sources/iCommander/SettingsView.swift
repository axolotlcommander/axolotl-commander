import SwiftUI

struct SettingsView: View {
    @AppStorage(Launcher.terminalDefaultsKey) private var terminal = "com.apple.Terminal"

    var body: some View {
        TabView {
            Form {
                Picker("Terminal:", selection: $terminal) {
                    ForEach(Launcher.installedTerminals) { Text($0.name).tag($0.bundleID) }
                }
                Text("Used by Open Terminal Here (⌃/) and by commands typed in the command line.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding()
        .frame(width: 460, height: 240)
        .onExitCommand { NSApp.keyWindow?.close() }
    }
}
