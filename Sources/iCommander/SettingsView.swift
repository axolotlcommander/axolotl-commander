import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Form {
                Text("General settings arrive with later stages.")
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding()
        .frame(width: 460, height: 240)
        .onExitCommand { NSApp.keyWindow?.close() }
    }
}
