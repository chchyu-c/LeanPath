import '../models/diet.dart';
import '../models/plan.dart' show WeightPlan;
import 'diet_presets.dart';
import 'plan_engine.dart' show PlanInput;

/// 推荐依据（UI 按此枚举取对应文案，便于向用户解释「为什么推荐这套」）。
enum DietReason { intensive, gentle, balanced }

class DietRecommendation {
  final DietPreset preset;
  final DietReason reason;

  const DietRecommendation({required this.preset, required this.reason});

  String get presetId => preset.id;
}

/// 饮食方案推荐引擎：纯函数、无 Flutter 依赖，可直接单元测试。
///
/// 只用用户已经填写的计划参数，不额外采集身高/病史等敏感信息：
/// - 每周目标减重 ≥ 0.7kg 或基础步数 ≥ 9000 → 高蛋白保肌（节奏偏快/运动量大）；
/// - 每周目标减重 ≤ 0.35kg → 高纤维轻食（温和节奏，靠饱腹感自然控量）；
/// - 其余 → 均衡减脂（默认，最易长期坚持）。
///
/// 阈值只是产品上的推荐倾向，不是医学建议；用户可在创建页随时改选。
class DietEngine {
  const DietEngine();

  static const String defaultPresetId = 'balanced';

  List<DietPreset> get presets => kDietPresets;

  DietPreset preset(String id) => kDietPresets.firstWhere(
        (p) => p.id == id,
        orElse: () => kDietPresets.first,
      );

  DietRecommendation recommend(PlanInput input) {
    final weeks = input.days / 7.0;
    final weeklyLoss = weeks <= 0
        ? 0.0
        : (input.startWeightKg - input.targetWeightKg) / weeks;

    if (weeklyLoss >= 0.7 || input.baseStepGoal >= 9000) {
      return DietRecommendation(
          preset: preset('highProtein'), reason: DietReason.intensive);
    }
    if (weeklyLoss <= 0.35 && input.startWeightKg > input.targetWeightKg) {
      return DietRecommendation(
          preset: preset('highFiber'), reason: DietReason.gentle);
    }
    return DietRecommendation(
        preset: kDietPresets[0], reason: DietReason.balanced);
  }

  /// 生成与运动计划同起止的饮食日志；未知 presetId 归一化为默认方案。
  DietLog buildLog({required String presetId, required WeightPlan plan}) =>
      DietLog(
        presetId: preset(presetId).id,
        startDate: plan.startDate,
        days: plan.days,
      );
}
