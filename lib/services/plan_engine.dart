import '../models/plan.dart';

/// 生成计划的输入参数。UI 层负责校验，本引擎再做一次防御式校验。
class PlanInput {
  final DateTime startDate;
  final int days;
  final double startWeightKg;
  final double targetWeightKg;
  final int baseStepGoal;

  const PlanInput({
    required this.startDate,
    required this.days,
    required this.startWeightKg,
    required this.targetWeightKg,
    this.baseStepGoal = 6000,
  });
}

/// 纯函数式计划引擎：不依赖 Flutter、不依赖网络，便于单元测试与离线使用。
///
/// 设计取舍：
/// - 渐进式加量：步数目标随周期线性上调最多 30%，避免开局过猛；
/// - 每周日休息、每 7 天一次称重，其余日子有氧/力量交替；
/// - 每日固定附带「饮食记录」，这是打卡兜底的低门槛任务；
/// - 只输出参考曲线，不做任何减重效果承诺（合规要求，见 docs/CHINA_RELEASE.md）。
class PlanEngine {
  const PlanEngine();

  WeightPlan generate(PlanInput input) {
    if (input.days < 7) {
      throw ArgumentError.value(input.days, 'days', '计划至少 7 天');
    }
    if (input.targetWeightKg >= input.startWeightKg) {
      throw ArgumentError.value(
          input.targetWeightKg, 'targetWeightKg', '目标体重需小于起始体重');
    }
    if (input.baseStepGoal < 1000) {
      throw ArgumentError.value(input.baseStepGoal, 'baseStepGoal', '步数目标过低');
    }

    final start = DateTime(
        input.startDate.year, input.startDate.month, input.startDate.day);
    final tasks = <DailyTask>[];

    for (var i = 0; i < input.days; i++) {
      final date = DateTime(start.year, start.month, start.day + i);
      final progress = i / (input.days - 1);
      final stepGoal = (input.baseStepGoal * (1 + 0.30 * progress)).round();
      final isRestDay = date.weekday == DateTime.sunday;
      final isWeighDay = i % 7 == 0;
      final key = DailyTask.dateKey(date);

      if (isWeighDay) {
        tasks.add(DailyTask(
          id: '$key-weigh',
          date: date,
          kind: TaskKind.weighIn,
          title: 'weighIn',
          targetMinutes: 2,
          targetSteps: 0,
        ));
      }

      final kind = isRestDay
          ? TaskKind.rest
          : (i % 2 == 0 ? TaskKind.cardio : TaskKind.strength);
      tasks.add(DailyTask(
        id: '$key-main',
        date: date,
        kind: kind,
        title: kind.name,
        targetMinutes: isRestDay ? 10 : 20 + (10 * progress).round(),
        targetSteps: isRestDay ? 0 : stepGoal,
      ));

      tasks.add(DailyTask(
        id: '$key-diet',
        date: date,
        kind: TaskKind.diet,
        title: 'diet',
        targetMinutes: 3,
        targetSteps: 0,
      ));
    }

    return WeightPlan(
      startDate: start,
      days: input.days,
      startWeightKg: input.startWeightKg,
      targetWeightKg: input.targetWeightKg,
      baseStepGoal: input.baseStepGoal,
      tasks: tasks,
    );
  }
}
