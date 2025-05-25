import UIKit
import UserNotifications
import SwiftUI // For potential access to shared services if needed via App struct

// Ensure your MessagingService is accessible.
// This might be a globally available instance, or you might inject it.
// For this example, we'll assume it can be instantiated directly or retrieved.
// You might need to adjust this based on your app's architecture.
// If GridViewModel creates MessagingService, you might need a way to pass it here
// or make MessagingService a shared instance.

// Placeholder for accessing MessagingService:
// Option 1: Simple instantiation (if MessagingService has a default init and no complex dependencies needed early)
// let sharedMessagingService = MessagingService()

// Option 2: If your main App struct holds it or creates it, you might need a more complex way
// to make it available here, or pass relevant info. For now, we'll assume direct instantiation for simplicity.


class MyAppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // If MessagingService is an ObservableObject and used in SwiftUI views,
    // direct instantiation here might create a separate instance.
    // Consider how you manage shared instances of services.
    // For now, let's assume a new instance is okay for this example or you have a shared pattern.
    lazy var messagingService = MessagingService()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        UNUserNotificationCenter.current().delegate = self
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification authorization: \(error.localizedDescription)")
                return
            }
            if granted {
                print("Notification permission granted.")
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            } else {
                print("Notification permission denied.")
            }
        }
        
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate Methods

    // Called when a notification is delivered to a foreground app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        print("MyAppDelegate: Notification received in foreground: \(userInfo)")

        // Let MessagingService handle the payload for data update, but don't navigate from here.
        // This ensures message data is fetched if the app is open.
        messagingService.handlePushNotificationPayload(userInfo)
        
        // Decide how to present the notification (e.g., banner, sound, badge)
        // If you want the system to display the notification even if the app is in the foreground:
        completionHandler([.banner, .sound, .badge])
        // If you want to handle it silently or with custom UI, adjust accordingly:
        // completionHandler([]) 
    }

    // Called when a user taps on a notification (or performs an action).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("MyAppDelegate: Notification interaction (e.g., tap): \(userInfo)")

        // Check if the user tapped the main body of the notification
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            print("MyAppDelegate: User tapped notification. Forwarding to MessagingService for navigation handling.")
            messagingService.handlePushNotificationTap(userInfo)
        }
        
        // You can also handle custom notification actions here if you've defined them
        // else if response.actionIdentifier == "yourCustomActionIdentifier" { ... }

        completionHandler()
    }

    // MARK: - Remote Notification Registration Callbacks

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("MyAppDelegate: Registered for remote notifications with device token: \(token)")
        // You would typically send this token to your server if you were using a 3rd party push provider.
        // For CloudKit, this is handled more implicitly by subscribing to CKQuerySubscriptions.
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("MyAppDelegate: Failed to register for remote notifications: \(error.localizedDescription)")
    }
} 