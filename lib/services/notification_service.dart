import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/diet.dart';
import '../models/plan.dart';
import 'diet_engine.dart';

/// 每日定时提醒 + 闹铃式响铃 + 三餐提前提醒。
///
/// 双端差异（详见 docs/ARCHITECTURE.md）：
/// - Android：`AndroidScheduleMode.alarmClock` 走 AlarmManager 精确闹钟，配合
///   `fullScreenIntent` + Importance.max 通道实现锁屏全屏「闹铃」；重启后由
///   `ScheduledNotificationBootReceiver`（插件自带）与 App 启动重排双保险。
/// - iOS：本地通知最多 64 个待触发项，因此只滚动排未来 7 天；系统限制
///   通知声音最长 30 秒、无真正的后台常驻闹铃，用 Time Sensitive 级别 +
///   操作按钮 + 稍后提醒逼近体验。Critical Alerts 需 Apple 单独授权，不默认申请。
///
/// 通知预算：iOS 7 天 × (1 运动 + 3 餐) = 28；Android 14 天 × 4 = 56，
/// 均低于 `_maxPending` 与系统 64 上限（详见 docs/DIET_PLAN.md）。
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const MethodChannel _deviceChannel =
      MethodChannel('cn.leanpath.app/device');
  static const String _channelId = 'leanpath_alarm';
  static const String _mealChannelId = 'leanpath_meal';
  static const int _baseNotificationId = 1000;
  static const int _mealBaseNotificationId = 4000;
  static const int _mealSnoozeId = 4900;
  static const int _maxPending = 60; // iOS 上限 64，留出余量

  /// 三餐通知 payload 前缀，Controller 依此把通知动作分流到饮食打卡。
  static const String mealPayloadPrefix = 'meal|';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// actionId: 'done' / 'snooze' / 'open'；taskId 为通知 payload。
  void Function(String taskId, String actionId)? onAction;

  String get _languageCode =>
      PlatformDispatcher.instance.locale.languageCode;

  static String mealPayload(String dateKey, MealType type) =>
      '$mealPayloadPrefix$dateKey|${type.name}';

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
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _mealChannelId,
        '三餐提醒',
        description: '三餐用餐前的提前提醒，含按计划打卡与稍后提醒操作',
        importance: Importance.high,
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
  /// 运动提醒与三餐提醒共用一次 cancelAll，避免互相清掉对方。
  Future<int> rescheduleAll(
    WeightPlan? plan,
    ReminderSettings settings, {
    DietLog? dietLog,
    MealReminderSettings? mealSettings,
  }) async {
    await init();
    await _plugin.cancelAll();
    if (plan == null) return 0;

    final now = tz.TZDateTime.now(tz.local);
    final daysAhead = Platform.isIOS ? 7 : 14;
    final lang = _languageCode;
    var scheduled = 0;

    if (settings.enabled) {
      for (var i = 0; i < daysAhead && scheduled < _maxPending; i++) {
        final day = DateTime(now.year, now.month, now.day + i);
        final task = plan.primaryTaskOn(day);
        if (task == null || task.isDone) continue;

        final at = tz.TZDateTime(tz.local, day.year, day.month, day.day,
            settings.hour, settings.minute);
        if (!at.isAfter(now)) continue;

        final steps = task.targetSteps > 0
            ? (lang == 'zh'
                ? ' / ${task.targetSteps} 步'
                : ' / ${task.targetSteps} steps')
            : '';
        await _scheduleOne(
          id: _baseNotificationId + i,
          taskId: task.id,
          title: lang == 'zh' ? '该动一动啦' : 'Time to move',
          body: lang == 'zh'
              ? '${task.targetMinutes} 分钟$steps'
              : '${task.targetMinutes} min$steps',
          at: at,
          alarmMode: settings.alarmMode,
        );
        scheduled++;
      }
    }

    if (dietLog != null && mealSettings != null && mealSettings.enabled) {
      scheduled += await _scheduleMeals(
        dietLog: dietLog,
        mealSettings: mealSettings,
        now: now,
        daysAhead: daysAhead,
        budget: _maxPending - scheduled,
        lang: lang,
      );
    }
    return scheduled;
  }

  /// 三餐提前提醒：提醒时刻 = 用餐时间 - leadMinutes，逐日滚动排程。
  Future<int> _scheduleMeals({
    required DietLog dietLog,
    required MealReminderSettings mealSettings,
    required tz.TZDateTime now,
    required int daysAhead,
    required int budget,
    required String lang,
  }) async {
    if (budget <= 0) return 0;
    final preset = const DietEngine().preset(dietLog.presetId);
    var count = 0;

    schedule:
    for (var i = 0; i < daysAhead; i++) {
      final day = DateTime(now.year, now.month, now.day + i);
      if (!dietLog.contains(day)) continue;
      for (final type in MealType.values) {
        if (count >= budget) break schedule;
        // 已「按计划吃」的餐不再打扰；换餐/没吃仍可补记录，故继续提醒。
        if (dietLog.recordOn(day, type)?.status == MealStatus.followed) {
          continue;
        }
        final at = tz.TZDateTime.from(
            mealSettings.remindAt(day, type), tz.local);
        if (!at.isAfter(now)) continue;

        final meal = preset.mealOn(day, type);
        final label = mealLabel(type, lang);
        await _scheduleOne(
          id: _mealBaseNotificationId +
              i * MealType.values.length +
              type.index,
          taskId: mealPayload(DietLog.dateKey(day), type),
          title: lang == 'zh' ? '该准备$label啦' : '$label is coming up',
          body: '${meal.name(lang)} · ${meal.kcalRange} kcal',
          at: at,
          // 三餐用普通通知，不用全屏闹铃：一天三次全屏打扰过重且更耗电。
          alarmMode: false,
          channelId: _mealChannelId,
          channelName: lang == 'zh' ? '三餐提醒' : 'Meal reminders',
          channelDescription: lang == 'zh'
              ? '三餐用餐前的提前提醒'
              : 'Reminders before each meal',
          doneLabel:
              lang == 'zh' ? '按计划吃了' : 'Ate as planned',
          snoozeLabel: lang == 'zh' ? '稍后提醒' : 'Snooze',
          categoryIdentifier: 'LEANPATH_MEAL',
        );
        count++;
      }
    }
    return count;
  }

  static String mealLabel(MealType type, String lang) {
    if (lang == 'zh') {
      switch (type) {
        case MealType.breakfast:
          return '早餐';
        case MealType.lunch:
          return '午餐';
        case MealType.dinner:
          return '晚餐';
      }
    }
    switch (type) {
      case MealType.breakfast:
        return 'Breakfast';
      case MealType.lunch:
        return 'Lunch';
      case MealType.dinner:
        return 'Dinner';
    }
  }

  Future<void> snooze(String taskId, ReminderSettings settings) async {
    await init();
    final isMeal = taskId.startsWith(mealPayloadPrefix);
    final lang = _languageCode;
    await _scheduleOne(
      id: isMeal ? _mealSnoozeId : _baseNotificationId + 900,
      taskId: taskId,
      title: isMeal
          ? (lang == 'zh' ? '别忘了记录这餐' : 'Log this meal when you can')
          : (lang == 'zh' ? '该动一动啦（稍后提醒）' : 'Time to move (snoozed)'),
      body: isMeal
          ? (lang == 'zh'
              ? '按计划吃了就点一下，统计才准'
              : 'Tap "Ate as planned" to keep your stats accurate')
          : (lang == 'zh'
              ? '现在开始也来得及，完成后记得打卡'
              : 'It is not too late — check in when done'),
      at: tz.TZDateTime.now(tz.local)
          .add(Duration(minutes: settings.snoozeMinutes)),
      alarmMode: settings.alarmMode && !isMeal,
      channelId: isMeal ? _mealChannelId : _channelId,
      channelName: isMeal ? '三餐提醒' : '每日运动闹铃',
      channelDescription: isMeal ? '三餐提醒（稍后）' : '每日运动闹铃（稍后）',
      doneLabel: isMeal
          ? (lang == 'zh' ? '按计划吃了' : 'Ate as planned')
          : (lang == 'zh' ? '完成打卡' : 'Check in'),
      snoozeLabel: lang == 'zh' ? '稍后提醒' : 'Snooze',
      categoryIdentifier: isMeal ? 'LEANPATH_MEAL' : 'LEANPATH_TASK',
    );
  }

  Future<void> _scheduleOne({
    required int id,
    required String taskId,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required bool alarmMode,
    String channelId = _channelId,
    String channelName = '每日运动闹铃',
    String channelDescription = '减肥计划每日任务的锁屏闹铃提醒',
    String doneLabel = '完成打卡',
    String snoozeLabel = '稍后提醒',
    String categoryIdentifier = 'LEANPATH_TASK',
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: alarmMode ? Importance.max : Importance.high,
      priority: Priority.high,
      category: alarmMode
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      fullScreenIntent: alarmMode,
      ongoing: false,
      autoCancel: true,
      visibility: NotificationVisibility.public,
      // 若需自定义闹铃声，把音频放到 android/app/src/main/res/raw/alarm.mp3
      // 后启用：sound: const RawResourceAndroidNotificationSound('alarm')
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('done', doneLabel,
            showsUserInterface: false),
        AndroidNotificationAction('snooze', snoozeLabel),
      ],
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      // 自定义铃声需 <=30s 且放在 iOS bundle，见 docs/ARCHITECTURE.md。
      interruptionLevel: alarmMode
          ? InterruptionLevel.timeSensitive
          : InterruptionLevel.active,
      categoryIdentifier: categoryIdentifier,
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      at,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: alarmMode
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

/// 解析三餐通知 payload，避免 Controller 里再写一遍字符串协议。
class MealNotificationTarget {
  final String dateKey;
  final MealType type;

  const MealNotificationTarget({required this.dateKey, required this.type});

  static MealNotificationTarget? parse(String payload) {
    if (!payload.startsWith(NotificationService.mealPayloadPrefix)) {
      return null;
    }
    final parts = payload
        .substring(NotificationService.mealPayloadPrefix.length)
        .split('|');
    if (parts.length != 2) return null;
    MealType? type;
    for (final candidate in MealType.values) {
      if (candidate.name == parts[1]) type = candidate;
    }
    if (type == null) return null;
    return MealNotificationTarget(dateKey: parts[0], type: type);
  }

  /// 'yyyy-MM-dd' -> DateTime（本地零点）。
  DateTime get date {
    final parts = dateKey.split('-');
    if (parts.length != 3) return DateTime.now();
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return DateTime.now();
    return DateTime(year, month, day);
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
