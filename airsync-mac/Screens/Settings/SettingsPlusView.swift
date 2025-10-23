//
//  SettingsPlusView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-04.
//

import SwiftUI

struct SettingsPlusView: View {
    @ObservedObject var appState = AppState.shared

    @State private var licenseKey: String = ""
    @State private var isCheckingLicense = false
    @State private var licenseValid: Bool? = nil

    @State private var isExpanded: Bool = false
    @State private var isLicenseVisible = false

    @State private var selectedPlan: LicensePlanType = UserDefaults.standard.licensePlanType
    @State private var showPlusUnlockedSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("plus.title"), systemImage: "key")
                Spacer()

                if !appState.isPlus {
                    // Plan selection
                    HStack {
                        Spacer()
                        Picker("Plan", selection: $selectedPlan) {
                            ForEach(LicensePlanType.allCases) { plan in
                                Text(plan.displayName).tag(plan)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedPlan) { _, newValue in
                            UserDefaults.standard.licensePlanType = newValue
                        }
                        .labelStyle(.iconOnly)
                    }
                    .padding(.bottom, 4)
                }

                if appState.isPlus {
                    HStack{
                        Text(appState.isPlus ? "Active" : "Not active")
                        GlassButtonView(
                            label: "What’s in Plus",
                            systemImage: "sparkles",
                            action: {
                                showPlusUnlockedSheet = true
                            }
                        )
                    }
                }
            }


            // License input + check
            if !appState.isPlus {
                TextField(L("license.enterKey"), text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isCheckingLicense)

                HStack {
                    GlassButtonView(
                        label: "Activate",
                        systemImage: "checkmark.seal",
                        action: {
                            #if SELF_COMPILED
                            licenseValid = true
                            showPlusUnlockedSheet = true
                            #else
                            
                            Task {
                                isCheckingLicense = true
                                licenseValid = nil
                                UserDefaults.standard.licensePlanType = selectedPlan
                                let result = try? await Gumroad().checkLicenseKeyValidity(
                                    key: licenseKey,
                                    save: true,
                                    isNewRegistration: true
                                )
                                licenseValid = result ?? false
                                isCheckingLicense = false
                                if result == true {
                                    // Show Plus unlocked sheet
                                    showPlusUnlockedSheet = true
                                }
                            }
                            #endif
                        }
                    )
                    .disabled(licenseKey.isEmpty || isCheckingLicense)

                    if isCheckingLicense {
                        ProgressView().scaleEffect(0.6)
                    } else if let valid = licenseValid {
                        Image(systemName: valid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundColor(valid ? .green : .red)
                            .transition(.scale)
                    }

                    GlassButtonView(
                        label: "Get AirSync+",
                        systemImage: "link",
                        action: {
                            if let url = URL(string: "https://store.sameerasw.com") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    )

                    Spacer()
                }
            }

            // License info display
            #if SELF_COMPILED
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("License Info")
                        .font(.headline)
                    Spacer()
                    Text(appState.isPlus ? "Self Compiled" : "License inactive")
                        .font(.subheadline)
                        .foregroundColor(appState.isPlus ? .green : .red)
                }
                
                Divider()
            }
            #else
            if let details = appState.licenseDetails {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("License Info")
                            .font(.headline)
                        Spacer()
                        Text(appState.isPlus ? "Thank you <3" : "License inactive")
                            .font(.subheadline)
                            .foregroundColor(appState.isPlus ? .green : .red)
                    }

                    Divider()

                    infoRow(label: "Email", icon: "envelope", value: details.email)
                    infoRow(label: "Product", icon: "shippingbox", value: details.productName)
                    infoRow(label: "Order #", icon: "number", value: "\(details.orderNumber)")
                    infoRow(label: "Purchaser ID", icon: "person.fill", value: details.purchaserID)
                    infoRow(label: "Uses Count", icon: "number.square", value: "\(details.usesCount)")
                    infoRow(label: "Price", icon: "dollarsign.circle", value: "\(Double(details.price) / 100.0) \(details.currency.uppercased())")
                    infoRow(label: "Sale Date", icon: "calendar", value: details.saleTimestamp)

                    if let cancelled = details.subscriptionCancelledAt, !cancelled.isEmpty {
                        infoRow(label: "Cancelled At", icon: "xmark.circle", value: cancelled, color: .red)
                    }
                    if let ended = details.subscriptionEndedAt, !ended.isEmpty {
                        infoRow(label: "Ended At", icon: "calendar.badge.exclamationmark", value: ended, color: .orange)
                    }
                    if let failed = details.subscriptionFailedAt, !failed.isEmpty {
                        infoRow(label: "Failed At", icon: "exclamationmark.triangle", value: failed, color: .orange)
                    }

                    infoRow(label: "Refunded", icon: details.refunded ? "checkmark.circle" : "xmark.circle",
                            value: details.refunded ? "Yes" : "No", color: details.refunded ? .red : .secondary)
                    infoRow(label: "Disputed", icon: details.disputed ? "checkmark.circle" : "xmark.circle",
                            value: details.disputed ? "Yes" : "No", color: details.disputed ? .red : .secondary)
                    infoRow(label: "Chargebacked", icon: details.chargebacked ? "checkmark.circle" : "xmark.circle",
                            value: details.chargebacked ? "Yes" : "No", color: details.chargebacked ? .red : .secondary)

                    HStack {
                        Label("License Key", systemImage: "key")
                        Spacer()
                        Group {
                            if isLicenseVisible {
                                Text(details.key)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            } else {
                                Text(String(repeating: "•", count: max(6, min(details.key.count, 12))))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onTapGesture {
                            withAnimation {
                                isLicenseVisible.toggle()
                            }
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(10)
                .transition(.opacity.combined(with: .move(edge: .top)))

                if details.key != "" && !appState.isPlus {
                    Label("License invalid, expired or network error", systemImage: "xmark.circle")
                        .foregroundColor(.red)
                }
            }
            #endif
        }
        .sheet(isPresented: $showPlusUnlockedSheet) {
            PlusUnlockedSheet()
        }

        // Why Plus section
        DisclosureGroup(isExpanded: $isExpanded) {
            Text("""
Keeps me inspired to continue and maybe even to publish to the Apple app store and Google Play Store. Think of it as a little donation to keep this project alive and evolving.
That said, I know not everyone who wants the full experience can afford it. If that’s you, please don’t hesitate to reach out. 😊

The source code is available on GitHub, and you're more than welcome to build with all Plus features free — for personal use which also opens for contributions which is a win-win!.
As a thank-you for supporting the app, AirSync+ unlocks some nice extras: media controls, synced widgets, low battery alerts, wireless ADB, and more to come as I keep adding new features.

Enjoy the app!
(っ◕‿◕)っ
""")
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        } label: {
            Text(L("plus.why"))
                .font(.subheadline)
                .bold()
        }
        .padding(.horizontal)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func infoRow(label: String, icon: String, value: String, color: Color = .secondary) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(color)
        }
    }
}

#Preview {
    SettingsPlusView()
}
