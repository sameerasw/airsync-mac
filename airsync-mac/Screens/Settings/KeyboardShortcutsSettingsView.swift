import SwiftUI

struct KeyboardShortcutsSettingsView: View {
    @ObservedObject var appState = AppState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsHeaderView(title: "Keyboard Shortcuts", icon: "keyboard")

                VStack(spacing: 12) {
                    ForEach(AppShortcuts.all) { definition in
                        shortcutRow(definition)
                    }
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                Text("Global shortcuts work anywhere on your Mac, even while AirSync isn't focused. In-App shortcuts only work while AirSync is the active app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func shortcutRow(_ definition: AppShortcutDefinition) -> some View {
        HStack {
            Label(definition.name, systemImage: definition.icon)

            Spacer()

            Text(definition.displayString)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .glassBoxIfAvailable(radius: 6)

            Picker("", selection: Binding(
                get: { appState.scope(for: definition.id) },
                set: { appState.setScope($0, for: definition) }
            )) {
                Text("In-App").tag(ShortcutScope.inApp)
                Text("Global").tag(ShortcutScope.global)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
    }
}
