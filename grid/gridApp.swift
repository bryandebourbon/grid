//
//  gridApp.swift
//  grid
//
//  Created by Bryan de Bourbon on 5/24/25.
//

import SwiftUI
import CloudKit
import UserNotifications
import UIKit

// AppDelegate to handle push notifications and app lifecycle
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // Add a reference to MessagingService to handle notification taps
    private let messagingService = MessagingService()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        UNUserNotificationCenter.current().delegate = self
        if GridUITestHarness.isActive {
            return true
        }

        NotificationPermissionService.registerIfAlreadyAuthorized()
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("Successfully registered for remote notifications")
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // NEW: Handle app becoming active
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("App became active")
        NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)
    }
    
    // NEW: Handle app going to background/inactive
    func applicationWillResignActive(_ application: UIApplication) {
        print("App will resign active")
        NotificationCenter.default.post(name: .appWillResignActive, object: nil)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let queryNotification = notification as? CKQueryNotification else {
            completionHandler(.noData)
            return
        }

        print("Received CloudKit push notification for recordID: \(queryNotification.recordID?.recordName ?? "unknown")")
        MessageDeliveryTrace.log("push.apns sub=\(queryNotification.subscriptionID ?? "?") record=\(queryNotification.recordID?.recordName.prefix(8) ?? "?")")

        if queryNotification.subscriptionID == "public-grid-updates" {
            print("Received grid update notification - will refresh public profiles")
            NotificationCenter.default.post(name: .newGridUpdate, object: nil)
            completionHandler(.newData)
            return
        }

        guard let recordID = queryNotification.recordID else {
            completionHandler(.noData)
            return
        }

        // Persist the record name first so a later launch can fetch even if iOS
        // suspends us before CloudKit returns. Fetch by record ID is strongly
        // consistent; the chat query is not.
        PendingMessageFetchStore.enqueue(recordID.recordName)
        messagingService.fetchMessage(withRecordID: recordID, currentDeviceID: nil, announce: true) { result in
            switch result {
            case .success:
                completionHandler(.newData)
            case .failure:
                completionHandler(.failed)
            }
        }
    }
    
    // Handle notification taps when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        if let sender = userInfo[MessageBannerNotifier.senderDeviceIDKey] as? String,
           sender == ForegroundChatState.partnerDeviceID {
            completionHandler([])
            return
        }
        if notification.request.content.body == "New message received!" {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification taps
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        print("AppDelegate: Notification tap received with userInfo: \(userInfo)")
        
        if let senderDeviceID = userInfo[MessageBannerNotifier.senderDeviceIDKey] as? String {
            NotificationCenter.default.post(
                name: .didTapPushNotificationForChat,
                object: nil,
                userInfo: ["senderDeviceID": senderDeviceID]
            )
            completionHandler()
            return
        }

        messagingService.handlePushNotificationTap(userInfo: userInfo)
        
        completionHandler()
    }
}

// Notification names for communication between AppDelegate and app
extension Notification.Name {
    static let newCloudKitMessage = Notification.Name("newCloudKitMessage")
    static let newGridUpdate = Notification.Name("newGridUpdate")
    static let appDidBecomeActive = Notification.Name("appDidBecomeActive") // NEW
    static let appWillResignActive = Notification.Name("appWillResignActive") // NEW
}

@main
struct gridApp: App {
    // Add AppDelegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
