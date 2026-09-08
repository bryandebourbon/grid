import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

enum NotificationPermissionService {
    static func requestAfterFirstChatIfNeeded(
        defaults: UserDefaults = .standard,
        center: UNUserNotificationCenter = .current()
    ) {
        let key = NotificationPermissionLogic.requestedDefaultsKey
        guard defaults.bool(forKey: key) == false else { return }
        defaults.set(true, forKey: key)

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                if settings.authorizationStatus == .authorized {
                    registerForRemoteNotifications()
                }
                return
            }
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error {
                    print("Notification permission error: \(error.localizedDescription)")
                }
                if granted {
                    registerForRemoteNotifications()
                }
            }
        }
    }

    static func registerIfAlreadyAuthorized(center: UNUserNotificationCenter = .current()) {
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                registerForRemoteNotifications()
            }
        }
    }

    private static func registerForRemoteNotifications() {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        #endif
    }
}
