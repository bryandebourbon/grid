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
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Request permission for push notifications
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Push notification permission granted")
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            } else {
                print("Push notification permission denied: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
        
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
        
        // Handle CloudKit notification
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            if let queryNotification = notification as? CKQueryNotification {
                print("Received CloudKit push notification for recordID: \(queryNotification.recordID?.recordName ?? "unknown")")
                
                // Check if this is a message notification or profile notification
                if let subscriptionID = queryNotification.subscriptionID {
                    if subscriptionID.starts(with: "new-messages-for-device-") {
                        // This is a message notification
                        if let recordID = queryNotification.recordID {
                            NotificationCenter.default.post(name: .newCloudKitMessage, object: recordID)
                        }
                    } else if subscriptionID == "public-grid-updates" {
                        // This is a profile/grid update notification
                        print("Received grid update notification - will refresh public profiles")
                        NotificationCenter.default.post(name: .newGridUpdate, object: nil)
                    }
                } else {
                    // Fallback: try to determine by record type or other means
                    if let recordID = queryNotification.recordID {
                        NotificationCenter.default.post(name: .newCloudKitMessage, object: recordID)
                    }
                }
            }
        }
        
        completionHandler(.newData)
    }
    
    // Handle notification taps when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.alert, .sound, .badge])
    }
    
    // Handle notification taps
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Extract chat information from notification and route to chat
        if let senderDeviceID = userInfo["senderDeviceID"] as? String {
            NotificationCenter.default.post(name: .openChat, object: senderDeviceID)
        }
        
        completionHandler()
    }
}

// Notification names for communication between AppDelegate and app
extension Notification.Name {
    static let newCloudKitMessage = Notification.Name("newCloudKitMessage")
    static let openChat = Notification.Name("openChat")
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
