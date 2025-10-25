//
//  NotificationsManager.swift
//  AirSync
//
//  Created by AI Assistant on 2025-10-22.
//

import Foundation
internal import Combine

// A simple persisted notification model keyed by device identifier (e.g., IP)
struct DeviceNotification: Codable, Identifiable, Equatable {
    let id: String
    let app: String
    let title: String
    let body: String
    let timestamp: Date
    let deviceKey: String
    var isDismissed: Bool
}

final class NotificationsManager: ObservableObject {
    static let shared = NotificationsManager()

    @Published private(set) var notifications: [DeviceNotification] = []

    private let storeKey = "persistedNotifications"
    private var cancellables = Set<AnyCancellable>()

    private init() {
        load()
    }

    // MARK: - Public API

    func addOrUpdate(_ n: DeviceNotification) {
        if let idx = notifications.firstIndex(where: { $0.id == n.id && $0.deviceKey == n.deviceKey }) {
            notifications[idx] = n
        } else {
            notifications.insert(n, at: 0)
        }
        save()
    }

    func dismiss(id: String, deviceKey: String) {
        if let idx = notifications.firstIndex(where: { $0.id == id && $0.deviceKey == deviceKey }) {
            notifications[idx].isDismissed = true
            save()
        }
    }

    func list(for deviceKey: String, includeDismissed: Bool = false) -> [DeviceNotification] {
        notifications.filter { $0.deviceKey == deviceKey && (includeDismissed || !$0.isDismissed) }
    }

    func clearAll(for deviceKey: String? = nil) {
        if let key = deviceKey {
            notifications.removeAll { $0.deviceKey == key }
        } else {
            notifications.removeAll()
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(notifications) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let list = try? JSONDecoder().decode([DeviceNotification].self, from: data) else { return }
        notifications = list
    }
}

