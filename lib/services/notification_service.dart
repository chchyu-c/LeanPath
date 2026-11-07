import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/plan.dart';

/// 每日定时提醒 + 闹铃式响铃。
///
/// 双端差异（详见 docs/ARCHITECTURE.md）：
/// - Android：`AndroidScheduleMode.alarmClock` 走 AlarmManager 精确闹钟，配合
///   `fullScreenIntent` + Importance.max 通道实现锁屏全屏「闹铃」；重启后由
///   `ScheduledNotificationBootReceiver`（插件自带）与 App 启动重排双保险。
/// - iOS：本地通知最多 64 个待触发项，因此只滚动排未来 7 天；系统限制
///   通知声音最长 30 秒、无真正的后台常驻闹铃，用 Time Sensitive 级别 +
///   操作按钮 + 稍后提醒逼近体验。Critical Alerts 需 Apple 单独授权，不默认申请。
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const MethodChannel _deviceChannel =
      MethodChannel('cn.leanpath.app/device');
  static const String _channelId = 'leanpath_alarm';
  static const int _baseNotificationId = 1000;
  static const int _maxPending = 60; // iOS 上限 64，留出余量

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// actionId: 'done' / 'snooze' / 'open'；taskId 为通知 payload。
  void Function(String taskId, String actionId)? onAction;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    // 中国大陆首发默认 Asia/Shanghai；其它地区由原生 MethodChannel 返回设备 IANA ID。
    var zoneName = 'Asia/Shanghai';
    try {
      final deviceZone = await _deviceChannel.invokeMethod<String>('getTimeZone');
      if (deviceZone != null && deviceZone.isNotEmpty) zoneName = deviceZone;
    } on PlatformException {
      // 原生通道未就绪时保持默认时区。
    } on MissingPluginException {
      // 同上。
    }
    try {
      tz.setLocalLocation(tz.getLocation(zoneName));
    } catch (_) {
      // 未知时区 ID 或设备返回异常：按中国大陆首发默认时区兜底。
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(
          android: androidInit, iOS: darwinInit, macOS: darwinInit),
      onDidReceiveNotificationResponse: _onForegroundResponse,
    );

    await _ensureAndroidChannel();
    // iOS 通知操作按钮的 category 注册 API 在不同插件版本差异较大，
    // 这里不重复调用 initialize（会覆盖上面的回调）。按所用插件版本的
    // CHANGELOG 在 AppDelegate 中注册 UNNotificationCategory 即可，
    // 未注册时自动降级为「点击通知进入 App 再打卡」。
    _initialized = true;
  }

  Future<void> _ensureAndroidChannel() async {
    if (!Platform.isAndroid) return;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        '每日运动闹铃',
        description: '减肥计划每日任务的锁屏闹铃提醒，含完成打卡与稍后提醒操作',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
  }

  /// 通知权限与身体活动权限分开申请，且只在实际需要时调用（最小必要）。
  Future<PermissionSummary> requestPermissions() async {
    var notificationGranted = false;
    var activityGranted = false;

    if (Platform.isAndroid) {
      notificationGranted = (await Permission.notification.request()).isGranted;
      activityGranted =
          (await Permission.activityRecognition.request()).isGranted;
      // Android 12+ 的 SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM 属于系统设置项，
      // 需在设置页由用户授予：见 docs/PERMISSIONS.md。
    } else if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      notificationGranted =
          await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
              false;
      // iOS 计步/活动识别通过 Info.plist 的 NSMotionUsageDescription 声明，
      // 首次访问由系统弹窗，无需 permission_handler。
      activityGranted = true;
    }

    return PermissionSummary(
      notification: notificationGranted,
      activityRecognition: activityGranted,
    );
  }

  /// 打开电池优化设置页（国内厂商 ROM 保活的关键一步）。
  Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _deviceChannel.invokeMethod<void>('openBatterySettings');
    } on PlatformException {
      await openAppSettings();
    }
  }

  /// 全量重排：计划变更、时间修改、App 从后台恢复或重启后调用。
  Future<int> rescheduleAll(WeightPlan? plan, ReminderSettings settings) async {
    await init();
    await _plugin.cancelAll();
    if (plan == null || !settings.enabled) return 0;

    final now = tz.TZDateTime.now(tz.local);
    final daysAhead = Platform.isIOS ? 7 : 14;
    var scheduled = 0;

    for (var i = 0; i < daysAhead && scheduled < _maxPending; i++) {
      final day = DateTime(now.year, now.month, now.day + i);
      final task = plan.primaryTaskOn(day);
      if (task == null || task.isDone) continue;

      final at = tz.TZDateTime(tz.local, day.year, day.month, day.day,
          settings.hour, settings.minute);
      if (!at.isAfter(now)) continue;

      await _scheduleOne(
        id: _baseNotificationId + i,
        taskId: task.id,
        title: '该动一动啦',
        body: '${task.title} · ${task.targetMinutes} 分钟'
            '${task.targetSteps > 0 ? ' / ${task.targetSteps} 步' : ''}',
        at: at,
        settings: settings,
      );
      scheduled++;
    }
    return scheduled;
  }

  Future<void> snooze(String taskId, ReminderSettings settings) async {
    await init();
    await _scheduleOne(
      id: _baseNotificationId + 900,
      taskId: taskId,
      title: '该动一动啦（稍后提醒）',
      body: '现在开始也来得及，完成后记得打卡',
      at: tz.TZDateTime.now(tz.local)
          .add(Duration(minutes: settings.snoozeMinutes)),
      settings: settings,
    );
  }

  Future<void> _scheduleOne({
    required int id,
    required String taskId,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required ReminderSettings settings,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      '每日运动闹铃',
      channelDescription: '减肥计划每日任务的锁屏闹铃提醒',
      importance: Importance.max,
      priority: Priority.high,
      category: settings.alarmMode
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      fullScreenIntent: settings.alarmMode,
      ongoing: false,
      autoCancel: true,
      visibility: NotificationVisibility.public,
      // 若需自定义闹铃声，把音频放到 android/app/src/main/res/raw/alarm.mp3
      // 后启用：sound: const RawResourceAndroidNotificationSound('alarm')
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction('done', '完成打卡',
            showsUserInterface: false),
        AndroidNotificationAction('snooze', '稍后提醒'),
      ],
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      // 自定义铃声需 <=30s 且放在 iOS bundle，见 docs/ARCHITECTURE.md。
      interruptionLevel: settings.alarmMode
          ? InterruptionLevel.timeSensitive
          : InterruptionLevel.active,
      categoryIdentifier: 'LEANPATH_TASK',
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      at,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: settings.alarmMode
          ? AndroidScheduleMode.alarmClock
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: taskId,
    );
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  static void _onForegroundResponse(NotificationResponse response) {
    final taskId = response.payload;
    if (taskId == null) return;
    instance.onAction?.call(taskId, response.actionId ?? 'open');
  }
}

class PermissionSummary {
  final bool notification;
  final bool activityRecognition;

  const PermissionSummary({
    required this.notification,
    required this.activityRecognition,
  });

  bool get allGranted => notification && activityRecognition;
}
