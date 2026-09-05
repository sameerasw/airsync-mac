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
    var id: String { nid }
    let title: String
    let body: String
    let app: String
    let nid: String
    let package: String
    let priority: String?
    let actions: [NotificationAction]
    let progress: Int?
    let progressMax: Int?
    let progressIndeterminate: Bool?
    let ongoing: Bool?

    init(
        title: String,
        body: String,
        app: String,
        nid: String,
        package: String,
        priority: String? = nil,
        actions: [NotificationAction] = [],
        progress: Int? = nil,
        progressMax: Int? = nil,
        progressIndeterminate: Bool? = nil,
        ongoing: Bool? = nil
    ) {
        self.title = title
        self.body = body
        self.app = app
        self.nid = nid
        self.package = package
        self.priority = priority
        self.actions = actions
        self.progress = progress
        self.progressMax = progressMax
        self.progressIndeterminate = progressIndeterminate
        self.ongoing = ongoing
    }

    private enum CodingKeys: String, CodingKey {
        case title, body, app, nid, package, priority, actions
        case progress, progressMax, progressIndeterminate, ongoing
    }
}
