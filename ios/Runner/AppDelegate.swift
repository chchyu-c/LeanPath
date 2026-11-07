import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // flutter_local_notifications 依赖 AppDelegate 作为通知中心 delegate 转发事件。
    UNUserNotificationCenter.current().delegate = self

    // 注册「完成打卡 / 稍后提醒」操作按钮，与 Dart 层 categoryIdentifier 一致。
    let done = UNNotificationAction(
      identifier: "done", title: "完成打卡", options: [])
    let snooze = UNNotificationAction(
      identifier: "snooze", title: "稍后提醒", options: [])
    let category = UNNotificationCategory(
      identifier: "LEANPATH_TASK",
      actions: [done, snooze],
      intentIdentifiers: [],
      options: [.customDismissAction])
    UNUserNotificationCenter.current().setNotificationCategories([category])

    // 设备 IANA 时区，供 Dart 层精确调度本地通知。
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "cn.leanpath.app/device",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "getTimeZone":
          result(NSTimeZone.local.identifier)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // App 在前台时也以横幅 + 声音呈现闹铃提醒。
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
}
