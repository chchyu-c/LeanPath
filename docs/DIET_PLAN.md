# 饮食计划模块设计（LeanPath v1.1）

> 本文件说明「内置饮食方案 → 创建计划时推荐 → 三餐提前提醒 → 执行天数统计」的完整实现。
> 代码落盘于 `lib/models/diet.dart`、`lib/services/diet_presets.dart`、
> `lib/services/diet_engine.dart`、`lib/ui/diet_page.dart`、
> `lib/ui/meal_reminder_settings_page.dart`，以及既有 `plan_store` /
> `notification_service` / `plan_controller` / `plan_setup_page` / `home_page` 的扩展。

## 一、需求与落地对照

| 需求 | 实现方式 | 入口 |
|---|---|---|
| 设计一套饮食计划，内置到应用 | 3 套方案 × 7 天循环 × 每日三餐，中英双语、参考热量区间，纯数据常量、无需联网 | `diet_presets.dart` |
| 计划创建时就推荐吃这个 | `DietEngine.recommend()` 依据目标减重速率与运动量给出推荐 + 可解释理由；创建页默认选中推荐方案并允许改选 | `plan_setup_page.dart` |
| 看到多少天按计划执行、哪些天没按计划 | `DietLog.stats()` 输出按计划天数、未按计划天数、部分执行、连续天数、未按计划日期清单；首页概览卡 + 饮食页统计卡 + 执行日历 | `diet_page.dart`、`home_page.dart` |
| 每日三餐时提前提醒 | `MealReminderSettings`（三餐时间 + 提前分钟数）→ `NotificationService._scheduleMeals()` 滚动排本地通知，通知里可直接「按计划吃了」 | `notification_service.dart`、`meal_reminder_settings_page.dart` |

## 二、数据模型

```
DietLog
├── presetId        方案 ID（balanced / highProtein / highFiber）
├── startDate/days  与 WeightPlan 同起止
└── records         Map<"yyyy-MM-dd|breakfast" , MealRecord>

MealRecord
├── status          pending / followed / replaced / skipped
├── source          manual / notification
└── recordedAt
```

`MealReminderSettings` 独立存储（默认 07:30 / 12:00 / 18:00，提前 15 分钟），
不影响原有的运动 `ReminderSettings`，避免旧配置反序列化时字段错位。

三套方案都保留每日三餐：产品要求三餐都提醒，因此**不提供跳餐/断食方案**。
菜单按星期循环（`day.weekday - 1`），可覆盖任意长度的计划；内容数据自带 zh/en，
不放进 ARB——63 条菜单属于内容而非界面文案，拆开后 `gen-l10n` 只管 UI 字符串。

## 三、创建计划时的推荐规则

只用用户已填写的计划参数，不额外采集身高、病史等敏感信息：

| 条件 | 推荐方案 | 理由 |
|---|---|---|
| 每周目标减重 ≥ 0.7kg **或** 基础步数 ≥ 9000 | 高蛋白保肌 | 节奏偏快 / 运动量较大，减重期保留肌肉 |
| 每周目标减重 ≤ 0.35kg | 高纤维轻食 | 节奏温和，靠饱腹感自然控量 |
| 其余 | 均衡减脂（默认） | 配比均衡、食材常见，最易长期坚持 |

阈值是产品上的推荐倾向，**不是医学建议**；用户可在创建页随时改选，推荐理由在卡片上明示。
`PlanInput.dietPresetId` 为空时由 `DietEngine.recommend()` 兜底，未知 ID 会被归一化为默认方案。

## 四、三餐提前提醒

**提醒时刻 = 用餐时间 − `leadMinutes`**，用 `DateTime.subtract` 计算，可正确跨天
（例如 00:10 的早餐提前 30 分钟 → 前一天 23:40）。

| 项 | 运动提醒（原有） | 三餐提醒（新增） |
|---|---|---|
| Android 通道 | `leanpath_alarm`（Importance.max） | `leanpath_meal`（Importance.high） |
| 调度模式 | `alarmClock` 精确闹钟 + 全屏锁屏 | `inexactAllowWhileIdle` 普通通知 |
| iOS 级别 | Time Sensitive | Active |
| 通知操作 | 完成打卡 / 稍后提醒 | 按计划吃了 / 稍后提醒 |
| category | `LEANPATH_TASK` | `LEANPATH_MEAL` |
| payload | 运动任务 ID | `meal\|yyyy-MM-dd\|<mealType>` |

三餐**不用全屏闹铃**：一天三次全屏打扰过重且更耗电，用普通通知 + 提前量 + 一键打卡即可。

### 通知预算

iOS 待触发本地通知上限 64 个，工程内 `_maxPending = 60` 留余量：

| 平台 | 滚动天数 | 每日条数 | 合计 |
|---|---|---|---|
| iOS | 7 | 1 运动 + 3 餐 = 4 | 28 |
| Android | 14 | 4 | 56 |

两类通知共用一次 `cancelAll()` 后全量重排，避免互相清掉；已标记 `followed` 的餐不再排提醒，
`replaced` / `skipped` / 未记录仍会提醒（用户可能想补记录）。改动任何时间、打卡或计划后都会重排。

## 五、执行统计口径（重要）

```
已结束日期 = [startDate, 昨天] 与计划区间取交集
今天与未来日期不参与「按计划 / 未按计划」判定
```

理由是用户当天可能还没吃晚饭，把今天算成「未按计划」会误伤，也会让 56 天计划一开始就有
大量"未完成"红点。今日进度单独用「今日三餐」卡片展示。

单日状态：

| 状态 | 判定 | 计入 |
|---|---|---|
| `full` 三餐都按计划 | 3 餐均为 `followed` | 按计划执行天数 |
| `partial` 部分按计划 | 有 1–2 餐 `followed` | 未按计划（细项单列） |
| `offPlan` 未按计划 | 有记录但 0 餐 `followed` | 未按计划 |
| `noRecord` 未记录 | 3 餐都无记录 | 未按计划 |
| `future` 未开始 | 未来日期 | 不计入 |

因此 **按计划执行天数 + 未按计划天数 = 已结束天数**，两个数字相加自洽。
`offPlanSummaries` 按日期倒序给出所有未按计划的日期，页面上明确列出（最多展示 30 条 +
剩余条数），并支持点击日历格子查看当日三餐明细。
`currentStreak` 从今天（若今天已三餐全按计划）或昨天向前回溯连续的 `full` 天数。

## 六、存储与旧版本迁移

| Key | 内容 |
|---|---|
| `leanpath.plan.v1` | 运动计划（未改动格式） |
| `leanpath.reminder.v1` | 运动提醒设置（未改动格式） |
| `leanpath.diet.v1` | 新增：`DietLog` |
| `leanpath.meal_reminder.v1` | 新增：`MealReminderSettings` |

`PlanController._bootstrap()` 做了**惰性迁移**：若已有 `WeightPlan` 但没有 `DietLog`
（旧版本用户升级），自动按默认 `balanced` 方案补一份同起止的饮食日志，不改动任何运动打卡数据。
饮食数据同样只落本机 SharedPreferences，不上传。

## 七、合规

- 热量只给**参考区间**，不写「每日必须摄入 X 千卡」，不做疗效/绝对化承诺。
- 页面与商店文案带免责声明：不替代医师或注册营养师的个体化指导；慢性病、过敏、
  特殊生理阶段需咨询专业人士。
- 饮食记录属于健康类敏感个人信息：沿用个保法「最小必要 + 单独同意 + 仅存本机」，
  已补充到 `docs/PRIVACY.md` 收集清单。
- 三餐提醒只申请通知权限，不新增传感器/位置权限。

## 八、测试

`test/diet_plan_test.dart` 覆盖：内置方案完整性、按星期循环、推荐规则三分支、
`buildLog` 起止对齐、统计口径（含未来日期排除 / 今日排除 / 清单顺序 / 连续天数）、
`encode/decode` 往返、提前提醒时刻与跨天、设置序列化。

## 九、后续可扩展（本次未做）

- 用户在方案内自定义单餐内容 / 替换食材
- 饮食记录导出与删除入口（与隐私政策待办一并实现）
- 按周汇总图表、与体重曲线叠加
- 接入 Health Connect / HealthKit 读取实际摄入（需单独授权，本版本未引入）
