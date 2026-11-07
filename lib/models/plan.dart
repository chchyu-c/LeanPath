import 'dart:convert';

/// 每日任务类型。UI 展示文案走 ARB 资源，不在这里硬编码中文。
enum TaskKind { cardio, strength, diet, weighIn, rest }

class DailyTask {
  final String id;
  final DateTime date;
  final TaskKind kind;
  final String title;
  final int targetMinutes;
  final int targetSteps;

  /// 完成状态：null = 未完成；'sensor' / 'manual' / 'notification' = 完成来源。
  final String? doneSource;
  final DateTime? doneAt;

  const DailyTask({
    required this.id,
    required this.date,
    required this.kind,
    required this.title,
    required this.targetMinutes,
    required this.targetSteps,
    this.doneSource,
    this.doneAt,
  });

  bool get isDone => doneSource != null;
  bool get confirmedBySensor => doneSource == 'sensor';

  DailyTask copyWith({String? doneSource, DateTime? doneAt}) => DailyTask(
        id: id,
        date: date,
        kind: kind,
        title: title,
        targetMinutes: targetMinutes,
        targetSteps: targetSteps,
        doneSource: doneSource ?? this.doneSource,
        doneAt: doneAt ?? this.doneAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'kind': kind.name,
        'title': title,
        'targetMinutes': targetMinutes,
        'targetSteps': targetSteps,
        'doneSource': doneSource,
        'doneAt': doneAt?.toIso8601String(),
      };

  factory DailyTask.fromJson(Map<String, dynamic> json) => DailyTask(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        kind: TaskKind.values.byName(json['kind'] as String),
        title: json['title'] as String,
        targetMinutes: json['targetMinutes'] as int,
        targetSteps: json['targetSteps'] as int,
        doneSource: json['doneSource'] as String?,
        doneAt: json['doneAt'] == null
            ? null
            : DateTime.parse(json['doneAt'] as String),
      );

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class WeightPlan {
  final DateTime startDate;
  final int days;
  final double startWeightKg;
  final double targetWeightKg;
  final int baseStepGoal;
  final List<DailyTask> tasks;

  const WeightPlan({
    required this.startDate,
    required this.days,
    required this.startWeightKg,
    required this.targetWeightKg,
    required this.baseStepGoal,
    required this.tasks,
  });

  DateTime get endDate => DateTime(
      startDate.year, startDate.month, startDate.day + days - 1);

  List<DailyTask> tasksOn(DateTime day) {
    final key = DailyTask.dateKey(day);
    return tasks
        .where((t) => DailyTask.dateKey(t.date) == key)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  DailyTask? primaryTaskOn(DateTime day) {
    final list = tasksOn(day);
    if (list.isEmpty) return null;
    return list.firstWhere(
      (t) => t.kind != TaskKind.rest && t.kind != TaskKind.weighIn,
      orElse: () => list.first,
    );
  }

  /// 线性参考曲线，仅用于图表展示，不作为疗效承诺。
  double referenceWeightOn(DateTime day) {
    final elapsed = day.difference(startDate).inDays.clamp(0, days - 1);
    return startWeightKg +
        (targetWeightKg - startWeightKg) * (elapsed / (days - 1));
  }

  int get completedDays {
    final keys = <String>{};
    for (final t in tasks) {
      if (t.isDone && t.kind != TaskKind.weighIn) {
        keys.add(DailyTask.dateKey(t.date));
      }
    }
    return keys.length;
  }

  WeightPlan withTask(String taskId, DailyTask updated) => WeightPlan(
        startDate: startDate,
        days: days,
        startWeightKg: startWeightKg,
        targetWeightKg: targetWeightKg,
        baseStepGoal: baseStepGoal,
        tasks: tasks.map((t) => t.id == taskId ? updated : t).toList(),
      );

  Map<String, dynamic> toJson() => {
        'startDate': startDate.toIso8601String(),
        'days': days,
        'startWeightKg': startWeightKg,
        'targetWeightKg': targetWeightKg,
        'baseStepGoal': baseStepGoal,
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };

  factory WeightPlan.fromJson(Map<String, dynamic> json) => WeightPlan(
        startDate: DateTime.parse(json['startDate'] as String),
        days: json['days'] as int,
        startWeightKg: (json['startWeightKg'] as num).toDouble(),
        targetWeightKg: (json['targetWeightKg'] as num).toDouble(),
        baseStepGoal: json['baseStepGoal'] as int,
        tasks: (json['tasks'] as List<dynamic>)
            .map((e) => DailyTask.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String encode() => jsonEncode(toJson());
  static WeightPlan decode(String raw) =>
      WeightPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

class ReminderSettings {
  final bool enabled;
  final int hour;
  final int minute;

  /// true = 闹铃式（精确闹钟 + 全屏提醒 + 通知操作按钮）；false = 普通通知。
  final bool alarmMode;
  final int snoozeMinutes;

  const ReminderSettings({
    this.enabled = true,
    this.hour = 7,
    this.minute = 30,
    this.alarmMode = true,
    this.snoozeMinutes = 10,
  });

  ReminderSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    bool? alarmMode,
    int? snoozeMinutes,
  }) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        alarmMode: alarmMode ?? this.alarmMode,
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'alarmMode': alarmMode,
        'snoozeMinutes': snoozeMinutes,
      };

  factory ReminderSettings.fromJson(Map<String, dynamic> json) =>
      ReminderSettings(
        enabled: json['enabled'] as bool? ?? true,
        hour: json['hour'] as int? ?? 7,
        minute: json['minute'] as int? ?? 30,
        alarmMode: json['alarmMode'] as bool? ?? true,
        snoozeMinutes: json['snoozeMinutes'] as int? ?? 10,
      );
}
