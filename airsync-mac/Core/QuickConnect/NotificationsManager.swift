import Foundation

struct NotificationItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let message: String
    let date: Date

    init(id: UUID = UUID(), title: String, message: String, date: Date = Date()) {
        self.id = id
        self.title = title
        self.message = message
        self.date = date
    }
}

final class NotificationsPersistenceManager {
    private let storageKey = "com.notifications.persistence.notifications"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func save(_ notifications: [NotificationItem]) -> Bool {
        do {
            let data = try encoder.encode(notifications)
            userDefaults.set(data, forKey: storageKey)
            return true
        } catch {
            return false
        }
    }

    func load() -> [NotificationItem] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return []
        }
        do {
            let notifications = try decoder.decode([NotificationItem].self, from: data)
            return notifications
        } catch {
            return []
        }
    }

    func add(_ notification: NotificationItem) -> Bool {
        var current = load()
        current.append(notification)
        return save(current)
    }

    func remove(_ notification: NotificationItem) -> Bool {
        var current = load()
        current.removeAll { $0.id == notification.id }
        return save(current)
    }
}
