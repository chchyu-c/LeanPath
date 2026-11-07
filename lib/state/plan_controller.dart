import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/plan.dart';
import '../services/activity_sensing_service.dart';
import '../services/check_in_service.dart';
import '../services/notification_service.dart';
import '../services/plan_engine.dart';
import '../services/plan_store.dart';

/// 全局编排层（MVVM 的 ViewModel）：计划、提醒、感知、打卡在这里汇合。
class PlanController extends ChangeNotifier {
  PlanController._(
    this._store,
    this._engine,
    this._notifications,
    this._sensing,
    this._checkIn,
  );

  static Future<PlanController> create() async {
    final store = await PlanStore.open();
    final controller = PlanController._(
      store,
      const PlanEngine(),
      NotificationService.instance,
      ActivitySensingService(),
      CheckInService(store),
    );
    await controller._bootstrap();
    return controller;
  }

  final PlanStore _store;
  final PlanEngine _engine;
  final NotificationService _notifications;
  final ActivitySensingService _sensing;
  final CheckInService _checkIn;

  StreamSubscription<SensingVerdict>? _verdictSub;

  WeightPlan? plan;
  ReminderSettings settings = const ReminderSettings();
  SensingVerdict verdict = SensingVerdict.unavailable;
  PermissionSummary? permissions;
  String? error;
  String? focusTaskId;
  int scheduledCount = 0;
  bool ready = false;

  DailyTask? get todayTask =>
      plan?.primaryTaskOn(DateTime.now());

  Future<void> _bootstrap() async {
    plan = _store.loadPlan();
    settings = _store.loadSettings();

    await _notifications.init();
    _notifications.onAction = _onNotificationAction;

    await _sensing.start();
    _verdictSub = _sensing.verdicts.listen((v) {
      verdict = v;
      notifyListeners();
    });
    _sensing.beginWindow(minSteps: _minStepsForToday());

    scheduledCount =
        await _notifications.rescheduleAll(plan, settings);
    ready = true;
    notifyListeners();
  }

  int _minStepsForToday() {
    final task = todayTask;
    if (task == null || task.targetSteps <= 0) {
      return ActivitySensingService.defaultMinSteps;
    }
    // 观察窗口只要求达成目标的一个小片段，避免用户必须走满全程才被识别。
    return (task.targetSteps * 0.15).round().clamp(60, 400);
  }

  /// 权限只在用户主动开启提醒 / 感知时申请，符合最小必要与「时机合理」。
  Future<PermissionSummary> ensurePermissions() async {
    final result = await _notifications.requestPermissions();
    permissions = result;
    notifyListeners();
    return result;
  }

  Future<void> createPlan(PlanInput input) async {
    error = null;
    try {
      final generated = _engine.generate(input);
      await _store.savePlan(generated);
      plan = generated;
      scheduledCount =
          await _notifications.rescheduleAll(plan, settings);
    } on ArgumentError catch (e) {
      error = e.message?.toString() ?? e.toString();
    }
    notifyListeners();
  }

  Future<void> updateSettings(ReminderSettings next) async {
    settings = next;
    await _store.saveSettings(next);
    scheduledCount = await _notifications.rescheduleAll(plan, next);
    notifyListeners();
  }

  Future<void> checkIn(String taskId, {String source = 'manual'}) async {
    final updated = await _checkIn.checkIn(taskId, source: source);
    if (updated != null) {
      plan = updated;
      // 已完成任务不需要再响铃，重排时会自动跳过。
      scheduledCount =
          await _notifications.rescheduleAll(plan, settings);
      notifyListeners();
    }
  }

  Future<void> _onNotificationAction(String taskId, String actionId) async {
    if (actionId == 'done') {
      await checkIn(taskId, source: 'notification');
    } else if (actionId == 'snooze') {
      await _notifications.snooze(taskId, settings);
    } else {
      focusTaskId = taskId;
      notifyListeners();
    }
  }

  /// App 回到前台：开启新的观察窗口，并在需要时重排通知（开机/升级后的兜底）。
  Future<void> onAppResumed() async {
    _sensing.beginWindow(minSteps: _minStepsForToday());
    if (_store.consumeNeedsReschedule() || scheduledCount == 0) {
      scheduledCount = await _notifications.rescheduleAll(plan, settings);
    }
    notifyListeners();
  }

  void clearFocus() {
    focusTaskId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // ChangeNotifier.dispose 是同步接口，取消订阅与关闭流按 fire-and-forget 处理。
    _verdictSub?.cancel();
    _notifications.onAction = null;
    _sensing.stop();
    super.dispose();
  }
}
