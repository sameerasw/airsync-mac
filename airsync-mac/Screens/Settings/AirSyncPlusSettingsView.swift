import SwiftUI

struct AirSyncPlusSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsHeaderView(title: "AirSync+", icon: "plus.diamond.fill")
                SettingsPlusView()
                    .padding()
                    .glassBoxIfAvailable(radius: 18)
            }
            .padding()
        }
    }
}
