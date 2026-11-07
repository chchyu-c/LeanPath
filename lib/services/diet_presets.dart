import '../models/diet.dart';

/// 内置饮食方案的单餐模板。
///
/// 文案内置中英双语而不放进 ARB：63 条菜单文案属于「内容数据」而非 UI 文案，
/// 放到数据层可以让方案独立增删，也让 gen_l10n 只负责界面字符串。
/// 热量区间仅为参考范围，不构成任何疗效或营养处方承诺。
class MealTemplate {
  final MealType type;
  final String nameZh;
  final String nameEn;
  final String noteZh;
  final String noteEn;
  final int kcalMin;
  final int kcalMax;

  const MealTemplate({
    required this.type,
    required this.nameZh,
    required this.nameEn,
    required this.noteZh,
    required this.noteEn,
    required this.kcalMin,
    required this.kcalMax,
  });

  String name(String languageCode) =>
      languageCode == 'zh' ? nameZh : nameEn;

  String note(String languageCode) =>
      languageCode == 'zh' ? noteZh : noteEn;

  String get kcalRange => '$kcalMin–$kcalMax';
}

class DietDayMenu {
  /// 顺序必须与 MealType.values 一致：早 / 午 / 晚。
  final List<MealTemplate> meals;

  const DietDayMenu({required this.meals});
}

class DietPreset {
  final String id;
  final String nameZh;
  final String nameEn;
  final String descZh;
  final String descEn;

  /// 周一到周日共 7 天，按星期循环，可覆盖任意长度的计划。
  final List<DietDayMenu> cycle;

  const DietPreset({
    required this.id,
    required this.nameZh,
    required this.nameEn,
    required this.descZh,
    required this.descEn,
    required this.cycle,
  });

  String name(String languageCode) =>
      languageCode == 'zh' ? nameZh : nameEn;

  String description(String languageCode) =>
      languageCode == 'zh' ? descZh : descEn;

  MealTemplate mealOn(DateTime day, MealType type) =>
      cycle[(day.weekday - 1) % 7].meals[type.index];
}

/// 三套内置方案：均衡减脂（默认）、高蛋白保肌、高纤维轻食。
/// 三套都保留每日三餐，以满足三餐提前提醒的产品约束。
const List<DietPreset> kDietPresets = <DietPreset>[
  DietPreset(
    id: 'balanced',
    nameZh: '均衡减脂',
    nameEn: 'Balanced',
    descZh: '三餐配比均衡、食材常见，适合长期坚持',
    descEn: 'Balanced everyday meals built for long-term adherence',
    cycle: <DietDayMenu>[
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '燕麦牛奶粥 + 水煮蛋',
            nameEn: 'Oat porridge, milk & boiled egg',
            noteZh: '复合碳水搭配蛋白质，更耐饿',
            noteEn: 'Slow carbs plus protein keep you full longer',
            kcalMin: 320,
            kcalMax: 400),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '杂粮饭 + 清炒鸡胸 + 时蔬',
            nameEn: 'Mixed-grain rice, chicken breast & greens',
            noteZh: '主食减半、蔬菜加倍',
            noteEn: 'Half the rice, double the vegetables',
            kcalMin: 500,
            kcalMax: 620),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '番茄豆腐汤 + 蒸南瓜',
            nameEn: 'Tomato tofu soup & steamed pumpkin',
            noteZh: '晚餐清淡，少油少盐',
            noteEn: 'Light dinner, less oil and salt',
            kcalMin: 380,
            kcalMax: 480),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '全麦三明治 + 无糖豆浆',
            nameEn: 'Whole-wheat sandwich & unsweetened soy milk',
            noteZh: '用鸡蛋生菜替代沙拉酱',
            noteEn: 'Use egg and lettuce instead of mayo',
            kcalMin: 330,
            kcalMax: 420),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '荞麦面 + 卤牛肉 + 青菜',
            nameEn: 'Buckwheat noodles, lean beef & greens',
            noteZh: '面条控制在一份',
            noteEn: 'Keep noodles to one portion',
            kcalMin: 520,
            kcalMax: 640),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '清蒸鲈鱼 + 凉拌黄瓜',
            nameEn: 'Steamed bass & cucumber salad',
            noteZh: '蒸代替煎，减少用油',
            noteEn: 'Steam instead of frying',
            kcalMin: 400,
            kcalMax: 500),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '玉米 + 鸡蛋 + 无糖酸奶',
            nameEn: 'Corn, egg & plain yogurt',
            noteZh: '简单组合，蛋白质别省',
            noteEn: 'Simple combo, do not skip the protein',
            kcalMin: 320,
            kcalMax: 400),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '糙米饭 + 西兰花炒虾仁',
            nameEn: 'Brown rice, shrimp & broccoli',
            noteZh: '虾仁低脂高蛋白',
            noteEn: 'Shrimp is lean and protein-rich',
            kcalMin: 500,
            kcalMax: 620),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '鸡蓉菌菇汤 + 半根玉米',
            nameEn: 'Chicken mushroom soup & half a corn',
            noteZh: '汤类增加饱腹感',
            noteEn: 'Soup adds satiety',
            kcalMin: 360,
            kcalMax: 460),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '红薯 + 水煮蛋 + 小番茄',
            nameEn: 'Sweet potato, boiled egg & cherry tomatoes',
            noteZh: '主食换成粗粮',
            noteEn: 'Swap refined carbs for whole foods',
            kcalMin: 320,
            kcalMax: 400),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '藜麦饭 + 番茄牛肉（少油）',
            nameEn: 'Quinoa with lean tomato beef',
            noteZh: '去掉可见脂肪',
            noteEn: 'Trim visible fat',
            kcalMin: 520,
            kcalMax: 640),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '蒜蓉娃娃菜 + 蒸蛋',
            nameEn: 'Garlic cabbage & steamed egg custard',
            noteZh: '少油，控制粉丝用量',
            noteEn: 'Less oil, watch the starch',
            kcalMin: 380,
            kcalMax: 480),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '小米粥 + 鸡蛋 + 凉拌菠菜',
            nameEn: 'Millet porridge, egg & spinach',
            noteZh: '小米粥不加糖',
            noteEn: 'No sugar in the porridge',
            kcalMin: 300,
            kcalMax: 380),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '杂粮饭 + 少油香煎龙利鱼',
            nameEn: 'Mixed-grain rice & light pan-seared sole',
            noteZh: '用不粘锅少油煎',
            noteEn: 'Use a non-stick pan with minimal oil',
            kcalMin: 500,
            kcalMax: 620),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '冬瓜瘦肉丸汤 + 清炒芦笋',
            nameEn: 'Winter melon lean meatball soup & asparagus',
            noteZh: '丸子选瘦肉',
            noteEn: 'Choose lean meat for the balls',
            kcalMin: 380,
            kcalMax: 470),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '全麦包子 + 无糖豆浆',
            nameEn: 'Whole-wheat bun & unsweetened soy milk',
            noteZh: '控制包子大小',
            noteEn: 'Watch the bun size',
            kcalMin: 330,
            kcalMax: 420),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '鸡胸肉沙拉 + 一小份土豆',
            nameEn: 'Chicken salad with a small potato',
            noteZh: '沙拉酱换成油醋汁',
            noteEn: 'Use vinaigrette instead of creamy dressing',
            kcalMin: 480,
            kcalMax: 600),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '菌菇豆腐煲 + 半碗糙米饭',
            nameEn: 'Mushroom tofu pot & half bowl brown rice',
            noteZh: '周末也保持节奏',
            noteEn: 'Keep the rhythm on weekends',
            kcalMin: 400,
            kcalMax: 500),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '燕麦鸡蛋饼 + 牛奶',
            nameEn: 'Oat egg pancake & milk',
            noteZh: '不粘锅无油煎',
            noteEn: 'Cook without oil in a non-stick pan',
            kcalMin: 340,
            kcalMax: 420),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '去皮清炖鸡汤 + 杂粮饭',
            nameEn: 'Skinless chicken soup & mixed-grain rice',
            noteZh: '撇去表面浮油',
            noteEn: 'Skim the surface fat',
            kcalMin: 520,
            kcalMax: 630),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '白灼虾 + 蔬菜拼盘',
            nameEn: 'Poached shrimp & vegetable platter',
            noteZh: '休息日晚餐适当减量',
            noteEn: 'A lighter dinner on rest days',
            kcalMin: 360,
            kcalMax: 460),
      ]),
    ],
  ),
  DietPreset(
    id: 'highProtein',
    nameZh: '高蛋白保肌',
    nameEn: 'High protein',
    descZh: '提高蛋白质占比，配合较大运动量或较快的减重节奏',
    descEn: 'More protein to support higher training loads',
    cycle: <DietDayMenu>[
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '鸡蛋两枚 + 无糖希腊酸奶',
            nameEn: 'Two eggs & plain Greek yogurt',
            noteZh: '训练日早餐补足蛋白质',
            noteEn: 'Front-load protein on training days',
            kcalMin: 340,
            kcalMax: 420),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '香煎鸡胸 + 糙米饭 + 西兰花',
            nameEn: 'Chicken breast, brown rice & broccoli',
            noteZh: '鸡胸约一掌大小',
            noteEn: 'One palm-sized portion of chicken',
            kcalMin: 540,
            kcalMax: 660),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '清蒸鳕鱼 + 菠菜蛋花汤',
            nameEn: 'Steamed cod & spinach egg-drop soup',
            noteZh: '晚餐优先鱼虾与蛋类',
            noteEn: 'Prefer fish and eggs at dinner',
            kcalMin: 400,
            kcalMax: 500),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '蛋白粉燕麦杯 + 蓝莓',
            nameEn: 'Protein oat bowl & blueberries',
            noteZh: '乳糖不耐可换无糖豆浆',
            noteEn: 'Swap to soy milk if lactose intolerant',
            kcalMin: 350,
            kcalMax: 430),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '瘦牛肉荞麦面 + 青菜',
            nameEn: 'Lean beef buckwheat noodles & greens',
            noteZh: '力量训练日主食别省',
            noteEn: 'Keep carbs on strength days',
            kcalMin: 560,
            kcalMax: 680),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '虾仁蒸蛋 + 凉拌秋葵',
            nameEn: 'Shrimp steamed egg & okra salad',
            noteZh: '低脂蛋白搭配膳食纤维',
            noteEn: 'Lean protein plus fiber',
            kcalMin: 390,
            kcalMax: 490),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '全麦吐司 + 煎蛋 + 低脂奶',
            nameEn: 'Whole-wheat toast, fried egg & low-fat milk',
            noteZh: '煎蛋用不粘锅少油',
            noteEn: 'Use minimal oil in a non-stick pan',
            kcalMin: 360,
            kcalMax: 440),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '鸡腿去皮 + 藜麦饭 + 芦笋',
            nameEn: 'Skinless chicken thigh, quinoa & asparagus',
            noteZh: '去皮后脂肪明显下降',
            noteEn: 'Removing skin cuts fat significantly',
            kcalMin: 550,
            kcalMax: 670),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '豆腐牛肉末 + 清炒油麦菜',
            nameEn: 'Tofu with minced beef & sauteed lettuce',
            noteZh: '动植物蛋白搭配',
            noteEn: 'Mix plant and animal protein',
            kcalMin: 410,
            kcalMax: 510),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '鸡蛋蔬菜卷 + 无糖豆浆',
            nameEn: 'Egg vegetable roll & unsweetened soy milk',
            noteZh: '卷饼里加足蔬菜',
            noteEn: 'Load the wrap with vegetables',
            kcalMin: 340,
            kcalMax: 420),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '三文鱼（少油煎）+ 杂粮饭',
            nameEn: 'Lightly seared salmon & mixed-grain rice',
            noteZh: '三文鱼控制在一掌大小',
            noteEn: 'Keep salmon to one palm-sized portion',
            kcalMin: 570,
            kcalMax: 690),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '鸡胸菌菇汤 + 半根玉米',
            nameEn: 'Chicken mushroom soup & half a corn',
            noteZh: '运动后补水补蛋白',
            noteEn: 'Rehydrate and refuel after training',
            kcalMin: 390,
            kcalMax: 490),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '低脂奶酪 + 水煮蛋 + 全麦饼干',
            nameEn: 'Low-fat cheese, boiled egg & whole-wheat crackers',
            noteZh: '注意奶酪的钠含量',
            noteEn: 'Watch the sodium in cheese',
            kcalMin: 350,
            kcalMax: 430),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '卤牛腱 + 荞麦面 + 时蔬',
            nameEn: 'Lean beef shank, buckwheat noodles & greens',
            noteZh: '牛腱比牛腩更瘦',
            noteEn: 'Shank is leaner than brisket',
            kcalMin: 550,
            kcalMax: 670),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '白灼虾 + 蒸蛋 + 生菜',
            nameEn: 'Poached shrimp, steamed egg & lettuce',
            noteZh: '晚餐减少主食',
            noteEn: 'Fewer starches at dinner',
            kcalMin: 380,
            kcalMax: 480),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '牛奶燕麦 + 水煮蛋两枚',
            nameEn: 'Milk oats & two boiled eggs',
            noteZh: '长距离运动前别空腹',
            noteEn: 'Do not train fasted before long sessions',
            kcalMin: 380,
            kcalMax: 460),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '烤鸡胸沙拉 + 红薯',
            nameEn: 'Grilled chicken salad & sweet potato',
            noteZh: '运动日补一份优质碳水',
            noteEn: 'Add quality carbs on training days',
            kcalMin: 540,
            kcalMax: 660),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '番茄龙利鱼汤 + 豆腐',
            nameEn: 'Tomato sole soup & tofu',
            noteZh: '汤底不额外加油',
            noteEn: 'No extra oil in the broth',
            kcalMin: 390,
            kcalMax: 490),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '鸡蛋牛奶燕麦粥',
            nameEn: 'Egg and milk oat porridge',
            noteZh: '休息日早餐照常补蛋白',
            noteEn: 'Keep protein up even on rest days',
            kcalMin: 350,
            kcalMax: 430),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '去皮鸡汤 + 糙米饭 + 青菜',
            nameEn: 'Skinless chicken soup, brown rice & greens',
            noteZh: '撇去浮油',
            noteEn: 'Skim the surface fat',
            kcalMin: 530,
            kcalMax: 650),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '清蒸虾 + 凉拌西兰花',
            nameEn: 'Steamed shrimp & broccoli salad',
            noteZh: '休息日晚餐减量',
            noteEn: 'Lighter dinner on rest days',
            kcalMin: 360,
            kcalMax: 460),
      ]),
    ],
  ),
  DietPreset(
    id: 'highFiber',
    nameZh: '高纤维轻食',
    nameEn: 'High fiber',
    descZh: '以蔬菜、豆类与全谷物为主，饱腹感持久，适合温和减重节奏',
    descEn: 'Vegetables, legumes and whole grains for steady satiety',
    cycle: <DietDayMenu>[
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '燕麦奇亚籽粥 + 苹果',
            nameEn: 'Oat chia porridge & apple',
            noteZh: '可溶性纤维帮助延长饱腹',
            noteEn: 'Soluble fiber keeps you full',
            kcalMin: 300,
            kcalMax: 380),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '鹰嘴豆杂粮饭 + 烤时蔬',
            nameEn: 'Chickpea mixed-grain bowl & roasted vegetables',
            noteZh: '豆类补足植物蛋白',
            noteEn: 'Legumes add plant protein',
            kcalMin: 480,
            kcalMax: 600),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '蔬菜豆腐汤 + 蒸山药',
            nameEn: 'Vegetable tofu soup & steamed yam',
            noteZh: '晚餐以汤和根茎类为主',
            noteEn: 'Soup and roots for dinner',
            kcalMin: 360,
            kcalMax: 460),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '全麦面包 + 牛油果 + 无糖豆浆',
            nameEn: 'Whole-wheat bread, avocado & unsweetened soy milk',
            noteZh: '牛油果控制半颗',
            noteEn: 'Half an avocado is enough',
            kcalMin: 320,
            kcalMax: 400),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '扁豆糙米饭 + 凉拌海带丝',
            nameEn: 'Lentil brown rice & kelp salad',
            noteZh: '高纤维主食组合',
            noteEn: 'A high-fiber staple combo',
            kcalMin: 490,
            kcalMax: 610),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '蒜香西兰花 + 蒸南瓜',
            nameEn: 'Garlic broccoli & steamed pumpkin',
            noteZh: '蔬菜量加倍',
            noteEn: 'Double the vegetables',
            kcalMin: 350,
            kcalMax: 450),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '小米南瓜粥 + 水煮蛋',
            nameEn: 'Millet pumpkin porridge & boiled egg',
            noteZh: '不加糖，配一枚蛋补蛋白',
            noteEn: 'No sugar, add an egg for protein',
            kcalMin: 300,
            kcalMax: 380),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '荞麦面 + 木耳炒时蔬',
            nameEn: 'Buckwheat noodles & wood-ear mushroom vegetables',
            noteZh: '菌菇与木耳增加膳食纤维',
            noteEn: 'Mushrooms add fiber',
            kcalMin: 480,
            kcalMax: 600),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '番茄鹰嘴豆汤 + 生菜',
            nameEn: 'Tomato chickpea soup & lettuce',
            noteZh: '豆类汤饱腹又清淡',
            noteEn: 'Light but filling legume soup',
            kcalMin: 360,
            kcalMax: 460),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '紫薯 + 无糖酸奶 + 莓果',
            nameEn: 'Purple sweet potato, plain yogurt & berries',
            noteZh: '天然甜味替代加糖',
            noteEn: 'Natural sweetness instead of added sugar',
            kcalMin: 300,
            kcalMax: 380),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '藜麦蔬菜碗 + 毛豆',
            nameEn: 'Quinoa vegetable bowl & edamame',
            noteZh: '毛豆补植物蛋白',
            noteEn: 'Edamame for plant protein',
            kcalMin: 490,
            kcalMax: 610),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '冬瓜菌菇汤 + 蒸玉米',
            nameEn: 'Winter melon mushroom soup & steamed corn',
            noteZh: '少油少盐',
            noteEn: 'Less oil and salt',
            kcalMin: 350,
            kcalMax: 450),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '蔬菜鸡蛋全麦卷',
            nameEn: 'Whole-wheat vegetable egg wrap',
            noteZh: '一份卷饼塞足两类蔬菜',
            noteEn: 'Pack two kinds of vegetables in the wrap',
            kcalMin: 310,
            kcalMax: 390),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '糙米饭 + 家常豆腐 + 炒青菜',
            nameEn: 'Brown rice, home-style tofu & greens',
            noteZh: '豆腐选老豆腐更少油',
            noteEn: 'Firm tofu absorbs less oil',
            kcalMin: 490,
            kcalMax: 610),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '凉拌菠菜 + 蒸红薯',
            nameEn: 'Spinach salad & steamed sweet potato',
            noteZh: '晚餐主食换成根茎类',
            noteEn: 'Swap dinner starches for roots',
            kcalMin: 350,
            kcalMax: 450),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '燕麦豆浆糊 + 香蕉半根',
            nameEn: 'Oat soy blend & half a banana',
            noteZh: '周末也别跳过早餐',
            noteEn: 'Do not skip breakfast on weekends',
            kcalMin: 310,
            kcalMax: 390),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '杂豆饭 + 烤蔬菜拼盘',
            nameEn: 'Mixed-bean rice & roasted vegetable platter',
            noteZh: '豆类提前浸泡更好消化',
            noteEn: 'Soak beans beforehand for digestion',
            kcalMin: 480,
            kcalMax: 600),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '海带豆腐汤 + 凉拌黄瓜',
            nameEn: 'Kelp tofu soup & cucumber salad',
            noteZh: '清淡收尾',
            noteEn: 'A light finish',
            kcalMin: 340,
            kcalMax: 440),
      ]),
      DietDayMenu(meals: <MealTemplate>[
        MealTemplate(
            type: MealType.breakfast,
            nameZh: '玉米蔬菜粥 + 鸡蛋',
            nameEn: 'Corn vegetable porridge & egg',
            noteZh: '休息日早餐仍保持规律',
            noteEn: 'Keep a regular breakfast on rest days',
            kcalMin: 300,
            kcalMax: 380),
        MealTemplate(
            type: MealType.lunch,
            nameZh: '全麦意面 + 番茄菌菇',
            nameEn: 'Whole-wheat pasta with tomato & mushrooms',
            noteZh: '酱汁别加奶油',
            noteEn: 'Skip cream-based sauces',
            kcalMin: 500,
            kcalMax: 620),
        MealTemplate(
            type: MealType.dinner,
            nameZh: '蒸蔬菜拼盘 + 豆腐',
            nameEn: 'Steamed vegetable platter & tofu',
            noteZh: '休息日晚餐减量',
            noteEn: 'Lighter dinner on rest days',
            kcalMin: 340,
            kcalMax: 440),
      ]),
    ],
  ),
];
