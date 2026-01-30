//
//  Notification.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import Foundation

struct NotificationAction: Codable, Hashable, Identifiable {
    enum ActionType: String, Codable { case button, reply }
    var id: String { name }
    let name: String
    let type: ActionType
}

struct Notification: Codable, Identifiable, Equatable {
    let id = UUID()
    let title: String
    let body: String
    let app: String
    let nid: String
    let package: String
    let priority: String?
    let actions: [NotificationAction]

    private enum CodingKeys: String, CodingKey {
        case title, body, app, nid, package, priority, actions
    }
}
