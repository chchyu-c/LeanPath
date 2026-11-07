import 'dart:convert';

import 'plan.dart' show DailyTask;

/// 三餐类型。三餐都提醒是产品的硬要求，因此不提供「跳餐」方案。
enum MealType { breakfast, lunch, dinner }

/// 单餐打卡状态：
/// - pending 未记录；followed 按推荐吃；replaced 吃了别的；skipped 这餐没吃。
enum MealStatus { pending, followed, replaced, skipped }

/// 某一天的饮食执行口径（用于日历着色与统计）。
enum DietDayStatus { full, partial, offPlan, noRecord, future }

class MealRecord {
  final String dateKey;
  final MealType type;
  final MealStatus status;

  /// 完成来源：manual / notification。
  final String? source;
  final DateTime? recordedAt;

  const MealRecord({
    required this.dateKey,
    required this.type,
    required this.status,
    this.source,
    this.recordedAt,
  });

  bool get isFollowed => status == MealStatus.followed;
  bool get hasRecord => status != MealStatus.pending;

  static String recordKey(String dateKey, MealType type) =>
      '$dateKey|${type.name}';

  MealRecord copyWith({
    MealStatus? status,
    String? source,
    DateTime? recordedAt,
  }) =>
      MealRecord(
        dateKey: dateKey,
        type: type,
        status: status ?? this.status,
        source: source ?? this.source,
        recordedAt: recordedAt ?? this.recordedAt,
      );

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'type': type.name,
        'status': status.name,
        'source': source,
        'recordedAt': recordedAt?.toIso8601String(),
      };

  factory MealRecord.fromJson(Map<String, dynamic> json) => MealRecord(
        dateKey: json['dateKey'] as String,
        type: MealType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => MealType.breakfast,
        ),
        status: MealStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => MealStatus.pending,
        ),
        source: json['source'] as String?,
        recordedAt: json['recordedAt'] == null
            ? null
            : DateTime.parse(json['recordedAt'] as String),
      );
}

class DietDaySummary {
  final DateTime date;
  final DietDayStatus status;
  final int followedMeals;
  final int recordedMeals;

  const DietDaySummary({
    required this.date,
    required this.status,
    required this.followedMeals,
    required this.recordedMeals,
  });

  bool get isFull => status == DietDayStatus.full;
}

/// 统计口径见 docs/DIET_PLAN.md：只统计「已经完整结束的日期」（截至昨天），
/// 今天与未来日期不计入未按计划，避免用户还没吃晚饭就被判失败。
class DietStats {
  final int elapsedDays;
  final int followedDays;
  final int partialDays;
  final int offPlanDays;
  final int currentStreak;
  final List<DietDaySummary> offPlanSummaries;

  const DietStats({
    required this.elapsedDays,
    required this.followedDays,
    required this.partialDays,
    required this.offPlanDays,
    required this.currentStreak,
    required this.offPlanSummaries,
  });

  double get followedRate =>
      elapsedDays == 0 ? 0.0 : followedDays / elapsedDays;
}

/// 饮食计划日志：与 WeightPlan 平行存储，互不污染运动打卡数据。
class DietLog {
  final String presetId;
  final DateTime startDate;
  final int days;
  final Map<String, MealRecord> records;

  const DietLog({
    required this.presetId,
    required this.startDate,
    required this.days,
    this.records = const <String, MealRecord>{},
  });

  DateTime get endDate =>
      DateTime(startDate.year, startDate.month, startDate.day + days - 1);

  static String dateKey(DateTime d) => DailyTask.dateKey(d);

  bool contains(DateTime day) {
    final d0 = DateTime(day.year, day.month, day.day);
    final s0 = DateTime(startDate.year, startDate.month, startDate.day);
    return !d0.isBefore(s0) && !d0.isAfter(endDate);
  }

  MealRecord? recordOn(DateTime day, MealType type) =>
      records[MealRecord.recordKey(dateKey(day), type)];

  DietDaySummary summaryOn(DateTime day, {DateTime? today}) {
    final now = today ?? DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final d0 = DateTime(day.year, day.month, day.day);
    if (d0.isAfter(today0)) {
      return DietDaySummary(
          date: d0,
          status: DietDayStatus.future,
          followedMeals: 0,
          recordedMeals: 0);
    }

    var followed = 0;
    var recorded = 0;
    for (final type in MealType.values) {
      final rec = recordOn(d0, type);
      if (rec == null || !rec.hasRecord) continue;
      recorded++;
      if (rec.isFollowed) followed++;
    }

    final status = followed == MealType.values.length
        ? DietDayStatus.full
        : followed > 0
            ? DietDayStatus.partial
            : recorded > 0
                ? DietDayStatus.offPlan
                : DietDayStatus.noRecord;
    return DietDaySummary(
        date: d0,
        status: status,
        followedMeals: followed,
        recordedMeals: recorded);
  }

  DietStats stats({DateTime? today}) {
    final now = today ?? DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final s0 = DateTime(startDate.year, startDate.month, startDate.day);

    var followedDays = 0;
    var partialDays = 0;
    var elapsedDays = 0;
    final offPlan = <DietDaySummary>[];

    for (var i = 0; i < days; i++) {
      final d = DateTime(s0.year, s0.month, s0.day + i);
      // 今天尚未结束，不纳入「按计划 / 未按计划」的判定。
      if (!d.isBefore(today0)) break;
      elapsedDays++;
      final summary = summaryOn(d, today: now);
      if (summary.status == DietDayStatus.full) {
        followedDays++;
      } else {
        if (summary.status == DietDayStatus.partial) partialDays++;
        offPlan.add(summary);
      }
    }

    var cursor = today0;
    if (summaryOn(today0, today: now).status != DietDayStatus.full) {
      cursor = today0.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (!cursor.isBefore(s0) &&
        summaryOn(cursor, today: now).status == DietDayStatus.full) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return DietStats(
      elapsedDays: elapsedDays,
      followedDays: followedDays,
      partialDays: partialDays,
      offPlanDays: offPlan.length,
      currentStreak: streak,
      offPlanSummaries: offPlan.reversed.toList(),
    );
  }

  DietLog withRecord(DateTime day, MealType type, MealRecord record) {
    final next = Map<String, MealRecord>.from(records);
    next[MealRecord.recordKey(dateKey(day), type)] = record;
    return DietLog(
        presetId: presetId,
        startDate: startDate,
        days: days,
        records: next);
  }

  Map<String, dynamic> toJson() => {
        'presetId': presetId,
        'startDate': startDate.toIso8601String(),
        'days': days,
        'records': records.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory DietLog.fromJson(Map<String, dynamic> json) => DietLog(
        presetId: json['presetId'] as String? ?? 'balanced',
        startDate: DateTime.parse(json['startDate'] as String),
        days: json['days'] as int,
        records: (json['records'] as Map<String, dynamic>? ??
                <String, dynamic>{})
            .map((k, v) => MapEntry(
                k, MealRecord.fromJson(v as Map<String, dynamic>))),
      );

  String encode() => jsonEncode(toJson());
  static DietLog decode(String raw) =>
      DietLog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// 三餐提醒设置：用餐时间 + 提前量。提醒时刻 = 用餐时间 - leadMinutes。
/// 三餐提醒用普通通知（非闹铃式），避免一天三次全屏打扰并降低耗电。
class MealReminderSettings {
  final bool enabled;
  final int breakfastHour;
  final int breakfastMinute;
  final int lunchHour;
  final int lunchMinute;
  final int dinnerHour;
  final int dinnerMinute;
  final int leadMinutes;

  const MealReminderSettings({
    this.enabled = true,
    this.breakfastHour = 7,
    this.breakfastMinute = 30,
    this.lunchHour = 12,
    this.lunchMinute = 0,
    this.dinnerHour = 18,
    this.dinnerMinute = 0,
    this.leadMinutes = 15,
  });

  DateTime mealAt(DateTime day, MealType type) {
    switch (type) {
      case MealType.breakfast:
        return DateTime(
            day.year, day.month, day.day, breakfastHour, breakfastMinute);
      case MealType.lunch:
        return DateTime(day.year, day.month, day.day, lunchHour, lunchMinute);
      case MealType.dinner:
        return DateTime(
            day.year, day.month, day.day, dinnerHour, dinnerMinute);
    }
  }

  DateTime remindAt(DateTime day, MealType type) =>
      mealAt(day, type).subtract(Duration(minutes: leadMinutes));

  MealReminderSettings copyWith({
    bool? enabled,
    int? breakfastHour,
    int? breakfastMinute,
    int? lunchHour,
    int? lunchMinute,
    int? dinnerHour,
    int? dinnerMinute,
    int? leadMinutes,
  }) =>
      MealReminderSettings(
        enabled: enabled ?? this.enabled,
        breakfastHour: breakfastHour ?? this.breakfastHour,
        breakfastMinute: breakfastMinute ?? this.breakfastMinute,
        lunchHour: lunchHour ?? this.lunchHour,
        lunchMinute: lunchMinute ?? this.lunchMinute,
        dinnerHour: dinnerHour ?? this.dinnerHour,
        dinnerMinute: dinnerMinute ?? this.dinnerMinute,
        leadMinutes: leadMinutes ?? this.leadMinutes,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'breakfastHour': breakfastHour,
        'breakfastMinute': breakfastMinute,
        'lunchHour': lunchHour,
        'lunchMinute': lunchMinute,
        'dinnerHour': dinnerHour,
        'dinnerMinute': dinnerMinute,
        'leadMinutes': leadMinutes,
      };

  factory MealReminderSettings.fromJson(Map<String, dynamic> json) =>
      MealReminderSettings(
        enabled: json['enabled'] as bool? ?? true,
        breakfastHour: json['breakfastHour'] as int? ?? 7,
        breakfastMinute: json['breakfastMinute'] as int? ?? 30,
        lunchHour: json['lunchHour'] as int? ?? 12,
        lunchMinute: json['lunchMinute'] as int? ?? 0,
        dinnerHour: json['dinnerHour'] as int? ?? 18,
        dinnerMinute: json['dinnerMinute'] as int? ?? 0,
        leadMinutes: json['leadMinutes'] as int? ?? 15,
      );
}
