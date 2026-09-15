//
//  PhoneDeviceView.swift
//  AirSyncWidget
//

import SwiftUI

struct PhoneDeviceView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.gray.opacity(0.3))
            .aspectRatio(CGSize(width: 60, height: 120), contentMode: .fit)
    }
}

#Preview {
    PhoneDeviceView()
        .frame(height: 100)
}
