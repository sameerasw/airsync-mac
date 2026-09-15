//
//  BatteryIconView.swift
//  AirSyncWidget
//

import SwiftUI

struct BatteryIconView: View {
    let level: Int
    let isCharging: Bool

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                    .frame(width: 16, height: 10)

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: max(1, CGFloat(level) / 100 * 12))

                    Spacer()
                }
                .padding(1)
                .frame(width: 14, height: 8)
            }

            Text("\(level)%")
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(.primary)

            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.primary.opacity(0.7))
            }
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        BatteryIconView(level: 90, isCharging: false)
        BatteryIconView(level: 50, isCharging: false)
        BatteryIconView(level: 15, isCharging: false)
        BatteryIconView(level: 45, isCharging: true)
    }
    .padding()
}
