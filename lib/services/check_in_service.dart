import '../models/plan.dart';
import 'plan_store.dart';

/// 打卡兜底：传感器判定成功也要由用户最终确认，避免误判写入完成记录。
/// 来源分三类：sensor（感知后确认）、manual（纯手动）、notification（通知按钮）。
class CheckInService {
  final PlanStore _store;

  const CheckInService(this._store);

  Future<WeightPlan?> checkIn(String taskId, {required String source}) =>
      _store.markTaskDone(taskId, source);

  /// 连续完成天数：从今天（或最近一个完成日）向前回溯。
  int currentStreak(WeightPlan plan) {
    final doneDays = <String>{};
    for (final t in plan.tasks) {
      if (t.isDone && t.kind != TaskKind.weighIn && t.kind != TaskKind.diet) {
        doneDays.add(DailyTask.dateKey(t.date));
      }
    }
    if (doneDays.isEmpty) return 0;

    var cursor = DateTime.now();
    // 今天还没完成不算断签，从昨天开始回溯。
    if (!doneDays.contains(DailyTask.dateKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (doneDays.contains(DailyTask.dateKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  double completionRate(WeightPlan plan) {
    final mainTasks = plan.tasks
        .where((t) => t.kind != TaskKind.weighIn && t.kind != TaskKind.diet)
        .toList();
    if (mainTasks.isEmpty) return 0;
    final done = mainTasks.where((t) => t.isDone).length;
    return done / mainTasks.length;
  }
}
