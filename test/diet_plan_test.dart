import 'package:flutter_test/flutter_test.dart';
import 'package:leanpath/models/diet.dart';
import 'package:leanpath/services/diet_engine.dart';
import 'package:leanpath/services/plan_engine.dart';

void main() {
  const engine = DietEngine();
  const planEngine = PlanEngine();

  PlanInput input({
    int days = 56,
    double start = 70,
    double target = 66,
    int steps = 6000,
  }) =>
      PlanInput(
        startDate: DateTime(2026, 1, 5),
        days: days,
        startWeightKg: start,
        targetWeightKg: target,
        baseStepGoal: steps,
      );

  DietLog seed(DietLog base, DateTime day, List<MealStatus> statuses) {
    var log = base;
    for (var i = 0; i < MealType.values.length; i++) {
      if (statuses[i] == MealStatus.pending) continue;
      log = log.withRecord(
        day,
        MealType.values[i],
        MealRecord(
          dateKey: DietLog.dateKey(day),
          type: MealType.values[i],
          status: statuses[i],
          source: 'manual',
          recordedAt: DateTime(2026, 1, 1),
        ),
      );
    }
    return log;
  }

  group('内置饮食方案', () {
    test('三套方案，每套 7 天且每天恰好三餐', () {
      expect(engine.presets.length, 3);
      for (final preset in engine.presets) {
        expect(preset.cycle.length, 7);
        for (final menu in preset.cycle) {
          expect(menu.meals.length, MealType.values.length);
          for (var i = 0; i < MealType.values.length; i++) {
            expect(menu.meals[i].type, MealType.values[i]);
            expect(menu.meals[i].kcalMax,
                greaterThan(menu.meals[i].kcalMin));
          }
        }
      }
    });

    test('菜单按星期循环，同一天三餐内容不同', () {
      final preset = engine.preset('balanced');
      final monday = DateTime(2026, 1, 5);
      final nextMonday = DateTime(2026, 1, 12);
      for (final type in MealType.values) {
        expect(preset.mealOn(monday, type).nameZh,
            preset.mealOn(nextMonday, type).nameZh);
      }
      expect(preset.mealOn(monday, MealType.breakfast).nameZh,
          isNot(preset.mealOn(monday, MealType.dinner).nameZh));
    });

    test('未知方案 ID 归一化为默认方案', () {
      expect(engine.preset('does-not-exist').id,
          DietEngine.defaultPresetId);
    });
  });

  group('DietEngine.recommend', () {
    test('减重节奏偏快或运动量大时推荐高蛋白', () {
      expect(engine.recommend(input(days: 14, start: 80, target: 70)).presetId,
          'highProtein');
      expect(engine.recommend(input(steps: 10000)).presetId, 'highProtein');
      expect(engine.recommend(input(days: 14, start: 80, target: 70)).reason,
          DietReason.intensive);
    });

    test('节奏温和时推荐高纤维', () {
      expect(engine.recommend(input(days: 56, start: 70, target: 68)).presetId,
          'highFiber');
    });

    test('节奏适中时推荐均衡减脂', () {
      expect(engine.recommend(input()).presetId, 'balanced');
      expect(engine.recommend(input()).reason, DietReason.balanced);
    });

    test('buildLog 与运动计划同起止', () {
      final plan = planEngine.generate(input(days: 28));
      final log = engine.buildLog(presetId: 'highFiber', plan: plan);
      expect(log.presetId, 'highFiber');
      expect(DietLog.dateKey(log.startDate),
          DietLog.dateKey(plan.startDate));
      expect(log.days, plan.days);
      expect(log.records, isEmpty);
    });
  });

  group('DietLog 执行统计', () {
    test('按计划 / 未按计划天数与日期清单', () {
      final start = DateTime(2026, 1, 5);
      final today = DateTime(2026, 1, 8);
      var log = DietLog(presetId: 'balanced', startDate: start, days: 4);

      log = seed(log, DateTime(2026, 1, 5), <MealStatus>[
        MealStatus.followed,
        MealStatus.followed,
        MealStatus.followed,
      ]);
      log = seed(log, DateTime(2026, 1, 6), <MealStatus>[
        MealStatus.followed,
        MealStatus.replaced,
        MealStatus.pending,
      ]);
      // 1/7 完全不记录
      // 今天 1/8 三餐都按计划，但今天尚未结束，不计入统计
      log = seed(log, today, <MealStatus>[
        MealStatus.followed,
        MealStatus.followed,
        MealStatus.followed,
      ]);

      final stats = log.stats(today: today);
      expect(stats.elapsedDays, 3);
      expect(stats.followedDays, 1);
      expect(stats.partialDays, 1);
      expect(stats.offPlanDays, 2);
      expect(stats.followedRate, closeTo(1 / 3, 0.0001));
      expect(stats.currentStreak, 1);
      expect(
        stats.offPlanSummaries
            .map((s) => DietLog.dateKey(s.date))
            .toList(),
        orderedEquals(<String>['2026-01-07', '2026-01-06']),
      );
      expect(stats.offPlanSummaries[1].status, DietDayStatus.partial);
      expect(stats.offPlanSummaries[0].status, DietDayStatus.noRecord);
      expect(log.summaryOn(DateTime(2026, 1, 9), today: today).status,
          DietDayStatus.future);
    });

    test('计划刚开始时没有已结束日期', () {
      final start = DateTime(2026, 1, 5);
      final log = DietLog(
          presetId: 'balanced', startDate: start, days: 7);
      final stats = log.stats(today: start);
      expect(stats.elapsedDays, 0);
      expect(stats.followedDays, 0);
      expect(stats.offPlanDays, 0);
      expect(stats.offPlanSummaries, isEmpty);
      expect(stats.followedRate, 0);
    });

    test('记录了但三餐都没按计划 = offPlan', () {
      final start = DateTime(2026, 1, 5);
      final log = DietLog(
          presetId: 'balanced', startDate: start, days: 2);
      final updated = seed(log, start, <MealStatus>[
        MealStatus.skipped,
        MealStatus.replaced,
        MealStatus.skipped,
      ]);
      final summary =
          updated.summaryOn(start, today: DateTime(2026, 1, 6));
      expect(summary.status, DietDayStatus.offPlan);
      expect(summary.followedMeals, 0);
      expect(summary.recordedMeals, 3);
    });

    test('encode / decode 往返不丢打卡记录', () {
      final log = DietLog(
          presetId: 'highProtein',
          startDate: DateTime(2026, 1, 5),
          days: 7);
      final seeded = seed(log, DateTime(2026, 1, 5), <MealStatus>[
        MealStatus.followed,
        MealStatus.replaced,
        MealStatus.skipped,
      ]);
      final restored = DietLog.decode(seeded.encode());
      expect(restored.presetId, 'highProtein');
      expect(restored.records.length, 3);
      expect(
          restored
              .recordOn(DateTime(2026, 1, 5), MealType.lunch)
              ?.status,
          MealStatus.replaced);
      expect(DietLog.dateKey(restored.endDate), '2026-01-11');
    });
  });

  group('MealReminderSettings 提前提醒', () {
    test('提醒时刻 = 用餐时间 - 提前分钟数', () {
      const settings = MealReminderSettings();
      final at = settings.remindAt(
          DateTime(2026, 1, 5), MealType.breakfast);
      expect(at.hour, 7);
      expect(at.minute, 15);
    });

    test('跨天提前提醒回退到前一日', () {
      const settings = MealReminderSettings(
          breakfastHour: 0, breakfastMinute: 10, leadMinutes: 30);
      final at = settings.remindAt(
          DateTime(2026, 1, 5), MealType.breakfast);
      expect(DietLog.dateKey(at), '2026-01-04');
      expect(at.hour, 23);
      expect(at.minute, 40);
    });

    test('序列化往返', () {
      const settings = MealReminderSettings(
          enabled: false, lunchHour: 13, leadMinutes: 20);
      final restored =
          MealReminderSettings.fromJson(settings.toJson());
      expect(restored.enabled, isFalse);
      expect(restored.lunchHour, 13);
      expect(restored.leadMinutes, 20);
    });
  });
}
