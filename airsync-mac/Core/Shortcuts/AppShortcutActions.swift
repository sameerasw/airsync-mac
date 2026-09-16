//
//  AppShortcutActions.swift
//  AirSync
//
//  Central action implementations shared by the in-app menu/sidebar bindings and the
//  global hotkey handlers, so both paths always run exactly the same logic.
//

import AppKit

enum AppShortcutActions {
    static func openSettings() {
        AppDelegate.shared?.showAndActivateMainWindow()
        AppState.shared.selectedTab = .settings
    }

    static func openHelp() {
        if let url = URL(string: "https://airsync.notion.site") {
            NSWorkspace.shared.open(url)
        }
    }

    static func mirrorPrimary() {
        let appState = AppState.shared
        guard let device = appState.device, appState.adbConnected else { return }
        if appState.useNativeMirroringByDefault {
            appState.isNativeMirroring = true
        } else {
            ADBConnector.startScrcpy(ip: device.ipAddress, port: UInt16(appState.adbPort), deviceName: device.name)
        }
    }

    static func mirrorAlternate() {
        let appState = AppState.shared
        guard let device = appState.device, appState.adbConnected else { return }
        if appState.useNativeMirroringByDefault {
            ADBConnector.startScrcpy(ip: device.ipAddress, port: UInt16(appState.adbPort), deviceName: device.name)
        } else {
            appState.isNativeMirroring = true
        }
    }

    static func desktopPrimary() {
        let appState = AppState.shared
        guard appState.isPlus, appState.licenseCheck, let device = appState.device, appState.adbConnected else { return }
        if appState.useNativeDesktopMirroringByDefault {
            appState.isNativeDesktopMirroring = true
        } else {
            ADBConnector.startScrcpy(ip: device.ipAddress, port: UInt16(appState.adbPort), deviceName: device.name, desktop: true)
        }
    }

    static func desktopAlternate() {
        let appState = AppState.shared
        guard appState.isPlus, appState.licenseCheck, let device = appState.device, appState.adbConnected else { return }
        if appState.useNativeDesktopMirroringByDefault {
            ADBConnector.startScrcpy(ip: device.ipAddress, port: UInt16(appState.adbPort), deviceName: device.name, desktop: true)
        } else {
            appState.isNativeDesktopMirroring = true
        }
    }

    static func toggleMirrorHere() {
        let appState = AppState.shared
        guard appState.device != nil, appState.adbConnected else { return }
        appState.isSidebarMirroring.toggle()
    }
}
