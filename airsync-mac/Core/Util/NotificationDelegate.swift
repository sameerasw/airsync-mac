//
//  NotificationDelegate.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-30.
//

import SwiftUI
import UserNotifications
import AppKit
internal import Combine

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didRemoveDeliveredNotifications identifiers: [String]) {
        for nid in identifiers {
            print("[notification-delegate] User dismissed system notification with nid: \(nid)")
            DispatchQueue.main.async {
                AppState.shared.removeNotificationById(nid)
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        // Handle Live Activities actions
        handleLiveActivitiesAction(response)
        let userInfo = response.notification.request.content.userInfo
        
        if response.actionIdentifier == "OPEN_LINK" {
            if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
        // Handle view action
        else if response.actionIdentifier == "VIEW_ACTION" {
            if let package = userInfo["package"] as? String,
               let ip = AppState.shared.device?.ipAddress,
               let name = AppState.shared.device?.name {

                ADBConnector.startScrcpy(
                    ip: ip,
                    port: AppState.shared.adbPort,
                    deviceName: name,
                    package: package
                )
            } else {
                print("[notification-delegate] Missing device details or package for scrcpy.")
            }
        }
        // Handle custom actions
        else if response.actionIdentifier.hasPrefix("ACT_") {
            let actionName = String(response.actionIdentifier.dropFirst(4))
            let nid = userInfo["nid"] as? String ?? response.notification.request.identifier

            var replyText: String? = nil
            if let textResp = response as? UNTextInputNotificationResponse {
                replyText = textResp.userText
            }
            WebSocketServer.shared.sendNotificationAction(id: nid, name: actionName, text: replyText)
        }

        completionHandler()
    }
    
    private func handleLiveActivitiesAction(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        
        switch response.actionIdentifier {
        // Live Call Actions
        case "LIVE_CALL_ANSWER":
            print("[live-activities] User answered call")
            WebSocketServer.shared.sendCallAction("answer")
            
        case "LIVE_CALL_DECLINE":
            print("[live-activities] User declined call")
            WebSocketServer.shared.sendCallAction("hangup")
            if let callId = userInfo["callId"] as? String {
                if #available(macOS 13.0, *) {
                    LiveActivitiesManager.shared.endCallActivity(callId)
                }
            }
            
        // Live SMS Actions
        case "LIVE_SMS_REPLY":
            if let textResponse = response as? UNTextInputNotificationResponse,
               let threadId = userInfo["threadId"] as? String,
               let phoneNumber = userInfo["phoneNumber"] as? String {
                print("[live-activities] User replied to SMS: \(textResponse.userText)")
                WebSocketServer.shared.sendSms(to: phoneNumber, message: textResponse.userText)
                if #available(macOS 13.0, *) {
                    LiveActivitiesManager.shared.endSmsActivity(threadId)
                }
            }
            
        case "LIVE_SMS_MARK_READ":
            if let messageId = userInfo["messageId"] as? String,
               let threadId = userInfo["threadId"] as? String {
                print("[live-activities] User marked SMS as read")
                WebSocketServer.shared.markSmsAsRead(messageId: messageId)
                if #available(macOS 13.0, *) {
                    LiveActivitiesManager.shared.endSmsActivity(threadId)
                }
            }
            
        // Live Health Actions
        case "LIVE_HEALTH_VIEW":
            print("[live-activities] User wants to view health details")
            // Navigate to health tab
            DispatchQueue.main.async {
                AppState.shared.selectedTab = .health
            }
            
        default:
            break
        }
    }

}
