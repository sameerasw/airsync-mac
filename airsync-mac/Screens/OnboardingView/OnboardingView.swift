//
//  OnboardingView.swift
//  AirSync
//
//  Created by AI Assistant on 2025-08-13.
//

import SwiftUI
import AppKit
import QRCode
internal import SwiftImageReadWrite

enum OnboardingStep {
    case welcome
    case installAndroid
    case airBridgeSetup
    case mirroringSetup
    case plusFeatures
    case done
}

struct OnboardingView: View {
    @ObservedObject var appState = AppState.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasPairedDeviceOnce") private var hasPairedDeviceOnce: Bool = false

    @State private var currentStep: OnboardingStep = .welcome
    @State private var hue: Double = 0
    @State private var timer: Timer?
    @State private var glowOpacity: Double = 0

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
                .overlay(
                    Group {
                        if currentStep == .plusFeatures {
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color(hue: hue, saturation: 1, brightness: 1),
                                    Color(hue: hue + 0.2, saturation: 1, brightness: 1),
                                    Color(hue: hue + 0.4, saturation: 1, brightness: 1),
                                    Color(hue: hue + 0.6, saturation: 1, brightness: 1),
                                    Color(hue: hue + 0.8, saturation: 1, brightness: 1)
                                ]),
                                center: .center
                            )
                            .opacity(glowOpacity)
                            .blur(radius: 100)
                        }
                    }
                )

            Group {
                switch currentStep {

                    case .welcome:
                        WelcomeView(onNext: { withAnimation(.easeInOut(duration: 0.75)) { currentStep = .installAndroid } })

                    case .installAndroid:
                        InstallAndroidView(onNext: { withAnimation(.easeInOut(duration: 0.75)) { currentStep = .airBridgeSetup } })

                    case .airBridgeSetup:
                        AirBridgeSetupView(
                            onNext: { withAnimation(.easeInOut(duration: 0.75)) { currentStep = .mirroringSetup } },
                            onSkip: { withAnimation(.easeInOut(duration: 0.75)) { currentStep = .mirroringSetup } }
                        )

                    case .mirroringSetup:
                        MirroringSetupView(
                            onNext: { withAnimation(.easeInOut(duration: 0.75)) { currentStep = .plusFeatures } },
                            onSkip: { withAnimation(.easeInOut(duration: 0.75)) { currentStep = .plusFeatures } }
                        )

                    case .plusFeatures:
                        PlusFeaturesView(onNext: { withAnimation(.easeInOut(duration: 0.75)) { currentStep = .done } })

                    case .done:
                        Color.clear.onAppear {
                            hasPairedDeviceOnce = true
                            UserDefaults.standard.markOnboardingCompleted()
                            AppState.shared.isOnboardingActive = false
                            dismiss()
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
        .onChange(of: currentStep) { old, new in
            if new == .plusFeatures {
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                    hue += 0.01
                }
                withAnimation(.easeInOut(duration: 2.0)) {
                    glowOpacity = 0.2
                }
            } else {
                timer?.invalidate()
                withAnimation(.easeInOut(duration: 1.0)) {
                    glowOpacity = 0
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

#Preview {
    OnboardingView()
}
