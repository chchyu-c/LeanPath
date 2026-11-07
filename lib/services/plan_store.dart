import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/diet.dart';
import '../models/plan.dart';

/// 离线优先：计划、打卡、提醒设置全部落本机 SharedPreferences。
/// 健康/运动数据属于敏感个人信息，本版本不上传任何服务端（个保法最小必要原则）。
class PlanStore {
  static const _planKey = 'leanpath.plan.v1';
  static const _settingsKey = 'leanpath.reminder.v1';
  static const _dietKey = 'leanpath.diet.v1';
  static const _mealReminderKey = 'leanpath.meal_reminder.v1';
  static const _rescheduleKey = 'leanpath.needs_reschedule.v1';

  final SharedPreferences _prefs;

  PlanStore(this._prefs);

  static Future<PlanStore> open() async =>
      PlanStore(await SharedPreferences.getInstance());

  WeightPlan? loadPlan() {
    final raw = _prefs.getString(_planKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return WeightPlan.decode(raw);
    } on FormatException {
      // 数据损坏时不让 App 崩溃，降级为「无计划」。
      return null;
    }
  }

  Future<void> savePlan(WeightPlan plan) =>
      _prefs.setString(_planKey, plan.encode());

  ReminderSettings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const ReminderSettings();
    try {
      return ReminderSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const ReminderSettings();
    }
  }

  Future<void> saveSettings(ReminderSettings settings) =>
      _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));

  // ---- 饮食计划 ----------------------------------------------------------

  DietLog? loadDietLog() {
    final raw = _prefs.getString(_dietKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return DietLog.decode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<void> saveDietLog(DietLog log) =>
      _prefs.setString(_dietKey, log.encode());

  MealReminderSettings loadMealReminderSettings() {
    final raw = _prefs.getString(_mealReminderKey);
    if (raw == null || raw.isEmpty) return const MealReminderSettings();
    try {
      return MealReminderSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const MealReminderSettings();
    }
  }

  Future<void> saveMealReminderSettings(MealReminderSettings settings) =>
      _prefs.setString(_mealReminderKey, jsonEncode(settings.toJson()));

  /// 单餐打卡：幂等写入，同一餐重复点同一状态不会刷新时间。
  Future<DietLog?> markMeal(
    DateTime day,
    MealType type,
    MealStatus status, {
    required String source,
  }) async {
    final log = loadDietLog();
    if (log == null) return null;
    if (log.recordOn(day, type)?.status == status) return log;
    final updated = log.withRecord(
      day,
      type,
      MealRecord(
        dateKey: DietLog.dateKey(day),
        type: type,
        status: status,
        source: source,
        recordedAt: DateTime.now(),
      ),
    );
    await saveDietLog(updated);
    return updated;
  }

  Future<WeightPlan?> markTaskDone(String taskId, String source) async {
    final plan = loadPlan();
    if (plan == null) return null;
    DailyTask? target;
    for (final t in plan.tasks) {
      if (t.id == taskId) {
        target = t;
        break;
      }
    }
    if (target == null || target.isDone) return plan;
    final updated = plan.withTask(
        taskId, target.copyWith(doneSource: source, doneAt: DateTime.now()));
    await savePlan(updated);
    return updated;
  }

  /// 开机 / 应用升级后，本地通知可能被系统清除，用一个标志位在下次启动时重排。
  Future<void> setNeedsReschedule(bool value) =>
      _prefs.setBool(_rescheduleKey, value);

  bool consumeNeedsReschedule() {
    final value = _prefs.getBool(_rescheduleKey) ?? true;
    if (value) {
      _prefs.setBool(_rescheduleKey, false);
    }
    return value;
  }
}
