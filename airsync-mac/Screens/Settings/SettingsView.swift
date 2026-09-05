import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState = AppState.shared

    var body: some View {
        Group {
            switch appState.selectedSettingsTab {
            case .myMac:
                MyMacSettingsView()
            case .sync:
                SyncSettingsView()
            case .notifications:
                NotificationsSettingsView()
            case .mirroring:
                MirroringSettingsView()
            case .quickShare:
                QuickShareSettingsView()
            case .menubar:
                MenubarSettingsView()
            case .appleIntelligence:
                AppleIntelligenceSettingsView()
            case .appearance:
                AppearanceSettingsView()
            case .airsyncPlus:
                AirSyncPlusSettingsView()
            }
        }
        .frame(minWidth: 300)
    }
}
