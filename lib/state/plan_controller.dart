import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/diet.dart';
import '../models/plan.dart';
import '../services/activity_sensing_service.dart';
import '../services/check_in_service.dart';
import '../services/diet_engine.dart';
import '../services/notification_service.dart';
import '../services/plan_engine.dart';
import '../services/plan_store.dart';

/// 全局编排层（MVVM 的 ViewModel）：运动计划、饮食计划、提醒、感知、打卡在这里汇合。
class PlanController extends ChangeNotifier {
  PlanController._(
    this._store,
    this._engine,
    this._dietEngine,
    this._notifications,
    this._sensing,
    this._checkIn,
  );

  static Future<PlanController> create() async {
    final store = await PlanStore.open();
    final controller = PlanController._(
      store,
      const PlanEngine(),
      const DietEngine(),
      NotificationService.instance,
      ActivitySensingService(),
      CheckInService(store),
    );
    await controller._bootstrap();
    return controller;
  }

  final PlanStore _store;
  final PlanEngine _engine;
  final DietEngine _dietEngine;
  final NotificationService _notifications;
  final ActivitySensingService _sensing;
  final CheckInService _checkIn;

  StreamSubscription<SensingVerdict>? _verdictSub;

  WeightPlan? plan;
  ReminderSettings settings = const ReminderSettings();
  DietLog? dietLog;
  MealReminderSettings mealSettings = const MealReminderSettings();
  SensingVerdict verdict = SensingVerdict.unavailable;
  PermissionSummary? permissions;
  String? error;
  String? focusTaskId;

  /// 三餐通知点击后待展示的日期（'yyyy-MM-dd'），DietPage 消费后清空。
  String? focusMealKey;
  int scheduledCount = 0;
  bool ready = false;

  DailyTask? get todayTask => plan?.primaryTaskOn(DateTime.now());

  Future<int> _reschedule() => _notifications.rescheduleAll(
        plan,
        settings,
        dietLog: dietLog,
        mealSettings: mealSettings,
      );

  Future<void> _bootstrap() async {
    plan = _store.loadPlan();
    settings = _store.loadSettings();
    dietLog = _store.loadDietLog();
    mealSettings = _store.loadMealReminderSettings();

    // 旧版本升级兼容：已有运动计划但没有饮食日志时，按默认方案补齐一份，
    // 起止日期沿用运动计划，不触碰任何已有的运动打卡数据。
    if (plan != null && dietLog == null) {
      final migrated = _dietEngine.buildLog(
          presetId: DietEngine.defaultPresetId, plan: plan!);
      await _store.saveDietLog(migrated);
      dietLog = migrated;
    }

    await _notifications.init();
    _notifications.onAction = _onNotificationAction;

    await _sensing.start();
    _verdictSub = _sensing.verdicts.listen((v) {
      verdict = v;
      notifyListeners();
    });
    _sensing.beginWindow(minSteps: _minStepsForToday());

    scheduledCount = await _reschedule();
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

  /// 创建计划时一并生成饮食方案：用户已选则用所选，否则按目标节奏推荐。
  Future<void> createPlan(PlanInput input) async {
    error = null;
    try {
      final generated = _engine.generate(input);
      final presetId = input.dietPresetId ??
          _dietEngine.recommend(input).presetId;
      final diet = _dietEngine.buildLog(
          presetId: presetId, plan: generated);

      await _store.savePlan(generated);
      await _store.saveDietLog(diet);
      plan = generated;
      dietLog = diet;
      scheduledCount = await _reschedule();
    } on ArgumentError catch (e) {
      error = e.message?.toString() ?? e.toString();
    }
    notifyListeners();
  }

  Future<void> updateSettings(ReminderSettings next) async {
    settings = next;
    await _store.saveSettings(next);
    scheduledCount = await _reschedule();
    notifyListeners();
  }

  Future<void> updateMealSettings(MealReminderSettings next) async {
    mealSettings = next;
    await _store.saveMealReminderSettings(next);
    scheduledCount = await _reschedule();
    notifyListeners();
  }

  Future<void> checkIn(String taskId, {String source = 'manual'}) async {
    final updated = await _checkIn.checkIn(taskId, source: source);
    if (updated != null) {
      plan = updated;
      // 已完成任务不需要再响铃，重排时会自动跳过。
      scheduledCount = await _reschedule();
      notifyListeners();
    }
  }

  /// 单餐打卡：followed / replaced / skipped 三态，支持通知按钮直接写入。
  Future<void> recordMeal(
    DateTime day,
    MealType type,
    MealStatus status, {
    String source = 'manual',
  }) async {
    final updated =
        await _store.markMeal(day, type, status, source: source);
    if (updated != null) {
      dietLog = updated;
      scheduledCount = await _reschedule();
      notifyListeners();
    }
  }

  Future<void> _onNotificationAction(String taskId, String actionId) async {
    final mealTarget = MealNotificationTarget.parse(taskId);
    if (mealTarget != null) {
      if (actionId == 'done') {
        await recordMeal(mealTarget.date, mealTarget.type,
            MealStatus.followed,
            source: 'notification');
      } else if (actionId == 'snooze') {
        await _notifications.snooze(taskId, settings);
      } else {
        focusMealKey = mealTarget.dateKey;
        notifyListeners();
      }
      return;
    }

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
      scheduledCount = await _reschedule();
    }
    notifyListeners();
  }

  void clearFocus() {
    focusTaskId = null;
    focusMealKey = null;
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
