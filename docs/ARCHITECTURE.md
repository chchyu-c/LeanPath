# 轻计划 LeanPath 架构设计

## 一、结论先行

**Flutter 3.x 单代码库 + 原生 MethodChannel 补平台能力 + 纯本地存储（无账号、无服务端）**，
是最适合本需求 MVP 的方案：定时闹铃与运动感知都是「平台系统能力」而非「复杂 UI」，
Flutter 只需把 `AlarmManager` / `UNUserNotificationCenter` / `CMPedometer`
通过成熟插件与少量原生代码桥接出来，双端 UI 与计划引擎完全复用。

| 维度 | 选择 | 依据 / 代价 |
|---|---|---|
| 技术栈 | Flutter（Dart 3） | 双端一套代码，CI 只需一条 Flutter 工具链；原生桥接工作量集中在 2 个文件 |
| 状态管理 | Provider + ChangeNotifier | MVP 规模足够，避免引入 Riverpod/BLoC 的学习与模板成本 |
| 存储 | SharedPreferences + JSON | 计划/打卡数据量小；无账号体系 → 隐私风险最低、无需备案数据接口 |
| 架构 | UI → Controller(VM) → Service → Model | 纯函数计划引擎可单测；服务层可替换（感知/通知） |
| 后台策略 | 本地通知由系统调度，**无常驻后台服务** | 省电、易过审；代价是 iOS 无「持续响铃」 |
| 首发地区 | 中国大陆 | 无 Google Play / FCM；本地通知方案恰好不依赖推送通道 |

**没有选择的方案**：原生双端（能力最稳但工作量翻倍）、Firebase（国内不可达）、
前台服务常驻（耗电 + 商店审核风险）。

## 二、分层与目录

```
lib/
├── main.dart                      # 入口：初始化、Provider、生命周期重排
├── models/plan.dart               # DailyTask / WeightPlan / ReminderSettings
├── models/diet.dart               # DietLog / MealRecord / 执行统计 / 三餐提醒设置
├── services/
│   ├── plan_engine.dart           # 纯函数：生成 N 天渐进式减肥路径
│   ├── diet_presets.dart          # 内置 3 套 × 7 天 × 三餐 方案（内容数据，中英双语）
│   ├── diet_engine.dart           # 纯函数：创建计划时的方案推荐
│   ├── plan_store.dart            # 离线持久化（运动 + 饮食，SharedPreferences + JSON）
│   ├── notification_service.dart  # 精确闹钟 / 三餐提前提醒 / 操作按钮 / 权限
│   ├── activity_sensing_service.dart # 计步 + 活动状态 → 感知判定
│   └── check_in_service.dart      # 打卡兜底、连续天数、完成率
├── state/plan_controller.dart     # 编排层：运动与饮食两条业务流汇合
├── ui/                           # 首页 / 计划设置 / 运动提醒 / 饮食计划 / 三餐提醒
└── l10n/                         # gen-l10n 生成物（不提交）
i18n/l10n/*.arb                   # 中英文案源
android/ · ios/                   # 原生壳（flutter create 生成 + 本仓库配置覆盖）
.github/workflows/ · fastlane/    # CI/CD
docs/ · store-listing/            # 合规、架构、上架素材
```

## 三、五个功能怎么实现

### 1. 减肥路径规划
`PlanEngine.generate()`：输入起始/目标体重、天数、基础步数 → 生成每日任务。
渐进加量（步数目标随周期上调最多 30%）、周日休息、每周称重、每日饮食记录；
只输出「参考体重曲线」，**不做减重效果承诺**（健康类合规红线）。

### 2. 每天定时提醒 + 闹铃
`NotificationService.rescheduleAll()` 逐日排未来 7（iOS）/ 14（Android）天的本地通知：

| | Android | iOS |
|---|---|---|
| 调度 | `zonedSchedule` + `AndroidScheduleMode.alarmClock`（AlarmManager 精确闹钟） | `UNUserNotificationCenter` 本地通知 |
| 闹铃感 | `Importance.max` 通道 + `fullScreenIntent` + 锁屏/亮屏 + 震动 | Time Sensitive 级别 + 声音 + 操作按钮 |
| 上限 | 无硬限制，仍滚动排 14 天 | 系统最多 64 个待触发 → 只排 7 天并滚动重排 |
| 声音 | 可放 `res/raw/alarm.mp3` 自定义长铃 | 自定义声音 ≤30 秒，无法持续循环 |
| 重启恢复 | 插件 `ScheduledNotificationBootReceiver` + App 启动重排 | App 回到前台时重排 |
| 操作 | 「完成打卡」「稍后提醒」通知按钮 | 同（AppDelegate 注册 `LEANPATH_TASK` category） |

> **诚实边界**：iOS 不允许第三方 App 常驻后台播放闹铃，系统通知声音最长 30 秒。
> 真正的持续响铃需要 **Critical Alerts 特殊授权**（Apple 审批，通常只给医疗/安全类应用），
> 本版本不申请。当前方案是「高优先级通知 + 重复提醒 + 一键打卡」，体验接近但不等价。

### 3. 手机感知「正在做这件事」
`ActivitySensingService` 双通道：`Pedometer.stepCountStream`（累计步数差）+ `pedestrianStatusStream`（walking/still）。

判定规则（只在「提醒窗口」内采样，不常驻后台）：
```
detected = 窗口内步数 ≥ minSteps
        OR (状态 = walking 且 步数 ≥ minSteps/2)
minSteps = clamp(今日目标步数 × 0.15, 60, 400)
```
- Android：`TYPE_STEP_COUNTER` + `ACTIVITY_RECOGNITION`；
- iOS：`CMPedometer` + `CMMotionActivityManager`（`NSMotionUsageDescription` 必填）；
- 传感器不可用、权限被拒、误判 → 一律降级为**手动打卡**，不阻塞用户。

### 4. 打卡兜底
`CheckInService` 记录完成来源 `sensor` / `manual` / `notification`。
即使传感器判定成功，也由用户最终确认后才写入完成记录，避免误判污染连续天数。

**关键时序**：
```
系统到点 → 本地通知（锁屏/横幅）
   → 用户点开 App / 通知按钮
   → beginWindow() 记录步数基线
   → 传感器流实时刷新首页「已感知到你在运动」
   → 用户点「完成打卡」→ 写本地 → 重排通知（跳过已完成任务）
```

### 5. 饮食计划（v1.1 新增）

与运动计划**平行**的一条数据流，不改动 `WeightPlan` 结构：

```
内置方案(常量) → DietEngine.recommend / buildLog → DietLog(本机)
                                                  ↓
三餐提醒设置 → NotificationService._scheduleMeals → 通知按钮 → PlanController.recordMeal
                                                  ↓
                                    DietLog.stats() → 饮食页统计 / 日历 / 首页概览
```

- **内置**：3 套方案 × 7 天循环 × 三餐，纯 Dart 常量，不联网、不读健康平台。
- **推荐**：按每周目标减重速率与基础步数选方案，理由在计划创建页明示，可随时改选。
- **提醒**：用餐时间 − 提前分钟数；独立 `leanpath_meal` 通道、普通通知（非闹铃），
  iOS 7 天 × 4 = 28、Android 14 天 × 4 = 56 条，均在 64 上限内。
- **统计**：只统计截至昨天的已结束日期，三餐全 `followed` 才算按计划执行；
  「按计划天数 + 未按计划天数 = 已结束天数」，并列出未按计划的具体日期。
- **迁移**：旧版本用户有运动计划但无饮食日志时，启动时自动补一份默认方案。

完整设计见 `docs/DIET_PLAN.md`。

## 四、双端差异对照（实现与审核风险）

| 项 | Android | iOS |
|---|---|---|
| 精确闹钟权限 | `SCHEDULE_EXACT_ALARM` 需用户在设置页授予；`USE_EXACT_ALARM` 为 normal 权限 | 无此概念 |
| 通知权限 | Android 13+ `POST_NOTIFICATIONS` 运行时申请 | 首次请求弹窗，`requestPermissions` |
| 身体活动权限 | `ACTIVITY_RECOGNITION`（敏感权限，需先告知） | `NSMotionUsageDescription`，首次访问弹窗 |
| 后台保活 | 国内厂商 ROM 需自启动 + 关闭电池优化，App 内提供一键跳转 | 不需要，系统调度通知 |
| 持久化 | SharedPreferences（非敏感配置） | UserDefaults |
| 商店 | 华为/小米/OPPO/vivo/应用宝（无 Google Play） | 中国区 App Store，需 App 备案号 |

## 五、隐私与安全基线

- 体重、步数、饮食打卡记录**全部留在本机**，不上传、不接第三方统计 SDK（MVP）。
  饮食方案是内置静态内容，不采集用户实际摄入、不拍照、不读取 Health Connect / HealthKit。
- 权限「用时申请 + 申请前弹窗说明目的」，拒绝后功能降级而非退出。
- release 开启 R8 混淆与资源压缩；日志不含健康数据。
- 后续若接入云同步：需单独同意、HTTPS + 证书绑定、敏感字段加密、境内存储、账号注销与数据导出。

## 六、测试与质量门禁

| 层级 | 内容 | 命令 / 工具 |
|---|---|---|
| 单元 | `PlanEngine` 边界值、`DietEngine` 推荐分支、`DietLog` 统计口径与序列化、`MealReminderSettings` 跨天提醒、`CheckInService` 连续天数 | `flutter test` |
| Widget | 首页空态 / 有任务 / 感知状态 / 打卡按钮 | `flutter test` |
| 静态 | `flutter analyze`、`dart format` | CI `quality` job |
| E2E | 通知触发 → 打卡 → 次日提醒跳过 | Maestro（建议后续补） |
| 真机矩阵 | 华为/小米/OPPO/vivo（精确闹钟与保活）、iOS 15~18 | 手工 + TestFlight / 蒲公英 |

性能基线建议：冷启动 < 1.5s、通知准时率 > 99%（厂商白名单机型）、
感知采样日耗电增量 < 2%、release APK < 25MB（分架构）。

## 七、已知限制 / 下一步

1. iOS 无持续响铃（见上文）；如确需，申请 Critical Alerts 授权或改用系统闹钟 Deep Link。
2. Android 部分深度定制 ROM 仍可能延迟精确闹钟 → 需按品牌做白名单引导与实测。
3. 无账号/云同步 → 换机数据丢失；后续可接境内 BaaS（`docs/baas-optional` 为可选骨架，
   注意 Supabase 国内需自托管或替换）。
4. 计划引擎与饮食方案目前是通用规则，未做个性化（年龄/性别/基础代谢/过敏原）；
   健康类算法与菜单上线前建议由专业营养/运动人员复核，且必须保留免责声明。
5. 饮食执行统计基于用户主动打卡，未按计划 ≠ 实际没按计划吃（可能是忘记记录）；
   UI 用「未记录」与「未按计划」两种状态区分，不做自动判定。
