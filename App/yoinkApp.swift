//
//  yoinkApp.swift
//  yoink
//
//  Created by user on 20.01.2026.
//

import SwiftUI
import UserNotifications

@main
struct yoinkApp: App {
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLogger.shared.log("Notification auth error: \(error.localizedDescription)")
            } else {
                AppLogger.shared.log("Notification auth granted: \(granted)")
            }
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            AppLogger.shared.log("Notification settings — authorizationStatus: \(settings.authorizationStatus.rawValue), alertStyle: \(settings.alertStyle.rawValue), alertSetting: \(settings.alertSetting.rawValue), notificationCenterSetting: \(settings.notificationCenterSetting.rawValue), soundSetting: \(settings.soundSetting.rawValue)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 760)
        }
        Settings {
            SettingsView()
        }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        AppLogger.shared.log("Notification will present in foreground: \(notification.request.content.title)")
        completionHandler([.banner, .sound])
    }
}
