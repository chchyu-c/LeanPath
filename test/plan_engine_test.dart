import 'package:flutter_test/flutter_test.dart';
import 'package:leanpath/models/plan.dart';
import 'package:leanpath/services/plan_engine.dart';

void main() {
  const engine = PlanEngine();

  PlanInput input({
    int days = 28,
    double start = 70,
    double target = 64,
    int steps = 6000,
  }) =>
      PlanInput(
        startDate: DateTime(2026, 1, 5),
        days: days,
        startWeightKg: start,
        targetWeightKg: target,
        baseStepGoal: steps,
      );

  group('PlanEngine.generate', () {
    test('每天恰好生成一条主任务', () {
      final plan = engine.generate(input());
      final mainTasks =
          plan.tasks.where((t) => t.id.endsWith('-main')).toList();
      expect(mainTasks.length, 28);
      expect(plan.days, 28);
    });

    test('步数目标渐进增加', () {
      final plan = engine.generate(input());
      final mainTasks =
          plan.tasks.where((t) => t.id.endsWith('-main')).toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      expect(mainTasks.last.targetSteps,
          greaterThan(mainTasks.first.targetSteps));
    });

    test('参考体重曲线是线性插值', () {
      final plan = engine.generate(input(days: 11));
      expect(plan.referenceWeightOn(DateTime(2026, 1, 5)),
          closeTo(70, 0.001));
      expect(plan.referenceWeightOn(DateTime(2026, 1, 15)),
          closeTo(64, 0.001));
      expect(plan.referenceWeightOn(DateTime(2026, 1, 10)),
          closeTo(67, 0.001));
    });

    test('非法参数被拒绝', () {
      expect(() => engine.generate(input(days: 3)), throwsArgumentError);
      expect(() => engine.generate(input(target: 75)), throwsArgumentError);
      expect(() => engine.generate(input(steps: 100)), throwsArgumentError);
    });

    test('每周日安排休息日', () {
      final plan = engine.generate(input());
      final restDays = plan.tasks
          .where((t) => t.id.endsWith('-main') && t.kind == TaskKind.rest)
          .toList();
      expect(restDays, isNotEmpty);
      expect(restDays.every((t) => t.date.weekday == DateTime.sunday), isTrue);
    });
  });

  group('WeightPlan 序列化', () {
    test('encode / decode 往返不丢数据', () {
      final plan = engine.generate(input());
      final restored = WeightPlan.decode(plan.encode());
      expect(restored.days, plan.days);
      expect(restored.tasks.length, plan.tasks.length);
      expect(restored.startWeightKg, plan.startWeightKg);
      expect(restored.targetWeightKg, plan.targetWeightKg);
    });
  });
}
