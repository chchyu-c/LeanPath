# 权限矩阵与申请时机

原则：**最小必要 + 用时申请 + 申请前告知 + 拒绝可降级**。健康/运动数据属敏感个人信息，
本版本全部留在本机，不上传、不共享第三方。

| 权限 | 平台 / 版本 | 用途 | 申请时机 | 拒绝后降级 |
|---|---|---|---|---|
| `POST_NOTIFICATIONS` | Android 13+ (API 33) | 每日定时提醒、闹铃 | 用户点「制定计划 / 开启提醒」时 | 关闭提醒，App 内仍可查看计划与手动打卡 |
| `SCHEDULE_EXACT_ALARM` | Android 12+ (API 31) | 精确时间触发闹铃 | 引导至系统设置页授予 | 降级 `inexactAllowWhileIdle`，可能延迟数分钟 |
| `USE_EXACT_ALARM` | Android 13+ (API 33) | 闹钟类应用精确调度 | 安装即授予（normal） | — |
| `ACTIVITY_RECOGNITION` | Android 10+ (API 29) | 计步 / 判定是否在运动 | 同通知权限，先弹说明再申请 | 关闭自动感知，保留手动打卡 |
| `RECEIVE_BOOT_COMPLETED` | Android 全版本 | 开机后恢复提醒 | 安装即授予 | 重启后直到打开 App 才恢复提醒 |
| `VIBRATE` / `WAKE_LOCK` | Android | 闹铃震动 / 亮屏 | 安装即授予 | — |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Android 6+ | 关闭电池优化，保证准时 | 用户主动点「去设置」 | 厂商 ROM 可能延迟或漏提醒 |
| `INTERNET` | 双端 | 隐私政策页 / 后续可选云同步 | 安装即授予 | 核心功能离线可用 |
| 通知授权 | iOS | 本地提醒 | 首次开启提醒时 | 同 Android |
| `NSMotionUsageDescription` | iOS | Core Motion 计步 / 活动识别 | 首次访问传感器时系统弹窗 | 手动打卡 |

## 厂商 ROM 保活（中国大陆重点）

本地精确闹钟不依赖推送通道，但厂商省电策略仍可能拦截。App 内提供一键跳转
（`MainActivity.openBatterySettings`），并引导用户完成：

| 品牌 | 需开启 |
|---|---|
| 华为 / 荣耀 | 应用启动管理 → 手动管理 → 允许自启动、关联启动、后台活动；设置 → 应用 → 电池 → 不允许电池优化 |
| 小米 / Redmi | 自启动、无障碍/后台弹出界面（部分机型）、省电策略改为「无限制」、神隐模式关闭 |
| OPPO / 一加 | 允许自动启动、允许后台运行、关闭「深度省电」 |
| vivo | 后台高耗电 → 允许、白名单、关闭「睡眠待机优化」 |
| 应用宝/其它 | 以各机型实际设置路径为准 |

测试建议：每个品牌至少覆盖「锁屏 30 分钟后是否准时响铃」「重启后是否恢复」两项。

## 商店申报注意

- Google Play（后续出海时）：`USE_EXACT_ALARM` 只允许闹钟/日历类应用使用，
  需在权限声明与数据安全表单中写清用途，否则可能被拒。
- 国内商店：需提交「权限清单与用途说明」，逐条对应上表，不得出现未使用权限。
- iOS：Info.plist 的用途描述必须具体，`NSMotionUsageDescription` 缺失会直接崩溃。
