import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var appState = AppState.shared
    @AppStorage("SUEnableAutomaticChecks") private var automaticallyChecksForUpdates = true
    @AppStorage("SUAutomaticallyUpdate") private var automaticallyDownloadsUpdates = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Appearance
                SettingsHeaderView(title: "Appearance", icon: "paintbrush")
                VStack(spacing: 12) {
                    HStack {
                        Label("Liquid Opacity", systemImage: "app.background.dotted")
                        Spacer()
                        Slider(
                            value: $appState.windowOpacity,
                            in: 0...1.0
                        )
                        .frame(width: 150)
                    }

                    HStack {
                        Label("Hide Dock Icon", systemImage: "dock.rectangle")
                        Spacer()
                        Toggle("", isOn: $appState.hideDockIcon)
                            .toggleStyle(.switch)
                    }

                    HStack {
                        Label("Always Open Window", systemImage: "macwindow")
                        Spacer()
                        Toggle("", isOn: $appState.alwaysOpenWindow)
                            .toggleStyle(.switch)
                    }
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                // 2. Application & Updates
                SettingsHeaderView(title: "Application & Updates", icon: "arrow.clockwise")
                VStack(spacing: 12) {
                    SettingsToggleView(name: "Check for updates automatically", icon: "sparkles", isOn: $automaticallyChecksForUpdates)
                    SettingsToggleView(name: "Download updates automatically", icon: "arrow.down.circle", isOn: $automaticallyDownloadsUpdates)
                    SettingsToggleView(name: "Crash reporting", icon: "ant", isOn: $appState.isCrashReportingEnabled)
                    SettingsToggleView(name: L("settings.autoStartAtLogin"), icon: "play.circle", isOn: $appState.autoStartAtLogin)
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)
            }
            .padding()
        }
    }
}
