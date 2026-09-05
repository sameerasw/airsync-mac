//
//  AppNotificationSettingsView.swift
//  AirSync
//
//  Created by Antigravity on 2026-06-04.
//

import SwiftUI

struct AppNotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let app: AndroidApp
    @State private var isSilent = false
    
    @ObservedObject private var appState = AppState.shared
    @State private var clickActionTab: ClickActionTab = .none
    @State private var installedApps: [InstalledMacApp] = []
    @State private var isLoadingApps = true
    @State private var clickSearchText = ""
    @State private var webURLText = ""
    @State private var webURLError: String? = nil

    enum ClickActionTab: String, CaseIterable {
        case none = "None"
        case macApp = "Mac App"
        case webURL = "Web URL"
    }

    private var existing: MacAppLaunchPreference? {
        appState.notificationLaunchPreferences[app.packageName]
    }

    private var resolvedTarget: MacAppLaunchPreference.LaunchTarget? {
        if let existing = existing {
            return existing.target
        }
        if let entry = NotificationLaunchDefaults.findDefault(for: app.packageName) {
            return NotificationLaunchDefaults.resolveTarget(for: entry)
        }
        return nil
    }

    private var selectedBundleID: String? {
        if case .macApp(let bundleID, _) = resolvedTarget {
            return bundleID
        }
        return nil
    }

    private var filteredMacApps: [InstalledMacApp] {
        let apps: [InstalledMacApp]
        if clickSearchText.isEmpty {
            apps = installedApps
        } else {
            apps = installedApps.filter {
                $0.name.localizedCaseInsensitiveContains(clickSearchText)
            }
        }
        
        if let selectedBundleID = selectedBundleID {
            return apps.sorted { app1, app2 in
                if app1.bundleID == selectedBundleID { return true }
                if app2.bundleID == selectedBundleID { return false }
                return false
            }
        }
        return apps
    }

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            
            VStack(spacing: 0) {
                // Header (Title & Icon on left, Close button on right end)
                HStack(spacing: 12) {
                    if let iconPath = app.iconUrl,
                       let image = Image(filePath: iconPath) {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .cornerRadius(5)
                    } else {
                        Image(systemName: "app.badge")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundColor(.gray)
                    }
                    
                    Text(String(format: L("settings.notifications.app.settings"), app.name))
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    // Priority Section
                    HStack {
                        Text(L("settings.notifications.app.priority"))
                            .font(.body)
                        Spacer()
                        Picker("", selection: $isSilent) {
                            Text(L("settings.notifications.app.priority.alert")).tag(false)
                            Text(L("settings.notifications.app.priority.silent")).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.large)
                    }
                    
                    // Click Action Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("On Notification Click")
                            .font(.headline)
                        
                        Picker("", selection: $clickActionTab) {
                            ForEach(ClickActionTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.large)

                        // Conditionally show tab content
                        Group {
                            switch clickActionTab {
                            case .none:
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("No custom action configured. Clicking the notification will open the default app or do nothing.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.top, 8)
                            case .macApp:
                                macAppTab
                            case .webURL:
                                webURLTab
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(20)
                
                // Footer
                if NotificationLaunchDefaults.findDefault(for: app.packageName) != nil && existing != nil {
                    HStack {
                        Button("Reset to Default") {
                            appState.removeNotificationLaunchPreference(for: app.packageName)
                            if let entry = NotificationLaunchDefaults.findDefault(for: app.packageName) {
                                let defaultTarget = NotificationLaunchDefaults.resolveTarget(for: entry)
                                switch defaultTarget {
                                case .macApp:
                                    clickActionTab = .macApp
                                case .webURL(let url):
                                    clickActionTab = .webURL
                                    webURLText = url
                                case .disabled:
                                    clickActionTab = .none
                                }
                            } else {
                                clickActionTab = .none
                            }
                        }
                        .buttonStyle(.borderless)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
        .frame(width: 480, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 20)
        .onAppear {
            isSilent = UserDefaults.standard.appSilentNotifications[app.packageName] ?? false
        }
        .onChange(of: isSilent) { _, newValue in
            var dict = UserDefaults.standard.appSilentNotifications
            dict[app.packageName] = newValue
            UserDefaults.standard.appSilentNotifications = dict
        }
        .onChange(of: clickActionTab) { _, newValue in
            if newValue == .none {
                if NotificationLaunchDefaults.findDefault(for: app.packageName) != nil {
                    let pref = MacAppLaunchPreference(
                        androidPackage: app.packageName,
                        androidAppName: app.name,
                        target: .disabled
                    )
                    appState.setNotificationLaunchPreference(pref)
                } else {
                    appState.removeNotificationLaunchPreference(for: app.packageName)
                }
            }
        }
        .task {
            // Invalidate cache and re-scan when sheet opens
            await MacInstalledAppsScanner.shared.invalidateCache()
            installedApps = await MacInstalledAppsScanner.shared.getInstalledApps()
            isLoadingApps = false

            // Pre-fill web URL if existing preference is a URL
            if let target = resolvedTarget {
                switch target {
                case .macApp:
                    clickActionTab = .macApp
                case .webURL(let url):
                    clickActionTab = .webURL
                    webURLText = url
                case .disabled:
                    clickActionTab = .none
                }
            } else {
                clickActionTab = .none
            }
        }
    }

    // MARK: - Mac App tab
    private var macAppTab: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps…", text: $clickSearchText)
                    .textFieldStyle(.plain)
                
                if !clickSearchText.isEmpty {
                    Button(action: { clickSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
            )
            .padding(.bottom, 8)

            if isLoadingApps {
                ProgressView("Scanning installed apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredMacApps.isEmpty {
                Text("No apps found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredMacApps) { macApp in
                    let isSelected = {
                        if case .macApp(let bundleID, _) = resolvedTarget {
                            return bundleID == macApp.bundleID
                        }
                        return false
                    }()
                    
                    HStack(spacing: 10) {
                        if let icon = macApp.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "app")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(macApp.name)
                            .font(.body)
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let pref = MacAppLaunchPreference(
                            androidPackage: app.packageName,
                            androidAppName: app.name,
                            target: .macApp(bundleID: macApp.bundleID, appName: macApp.name)
                        )
                        appState.setNotificationLaunchPreference(pref)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: - Web URL tab
    private var webURLTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter the web URL to open when a \(app.name) notification is clicked.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TextField("https://web.whatsapp.com", text: $webURLText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: webURLText) { _, _ in webURLError = nil }
                    
                    Button("Save URL") {
                        saveWebURL()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(webURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let error = webURLError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Text("The URL will open in your system default browser.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(.top, 8)
    }

    private func saveWebURL() {
        var raw = webURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.lowercased().hasPrefix("http://") && !raw.lowercased().hasPrefix("https://") {
            raw = "https://\(raw)"
        }
        guard URL(string: raw) != nil else {
            webURLError = "Please enter a valid URL."
            return
        }
        let pref = MacAppLaunchPreference(
            androidPackage: app.packageName,
            androidAppName: app.name,
            target: .webURL(urlString: raw)
        )
        appState.setNotificationLaunchPreference(pref)
    }
}

