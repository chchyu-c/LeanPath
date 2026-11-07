# 轻计划 LeanPath

Flutter 双端（Android + iOS）减肥路径规划 App：生成每日计划 → 到点闹铃式提醒 →
手机自动感知你是否在运动 → 识别不到也能一键打卡。中国大陆首发，全部数据留在本机。

> 本仓库是**文件级工程产物**：本机无 Android SDK / Xcode / Flutter SDK，未执行真实编译、
> 打包或提审。但**云端编译链路已配好**，代码推到 GitHub 后无需任何本地 SDK 或密钥即可在
> Runner 上编出双端产物，详见 `docs/CLOUD_BUILD.md`。

## 已实现的四个功能

| 功能 | 关键文件 |
|---|---|
| 减肥路径规划（渐进加量、周休、称重、参考曲线） | `lib/services/plan_engine.dart`、`lib/models/plan.dart` |
| 每日定时提醒 + 闹铃（精确闹钟、全屏提醒、通知按钮、稍后提醒） | `lib/services/notification_service.dart`、`android/app/src/main/AndroidManifest.xml`、`ios/Runner/AppDelegate.swift` |
| 手机感知「正在做这件事」（计步 + 活动状态，窗口内采样） | `lib/services/activity_sensing_service.dart` |
| 打卡兜底（传感器/手动/通知三种来源、连续天数、完成率） | `lib/services/check_in_service.dart`、`lib/services/plan_store.dart` |

界面：`lib/ui/`（首页 / 计划设置 / 提醒设置），状态编排：`lib/state/plan_controller.dart`，
中英文案：`i18n/l10n/*.arb`。

## 快速开始：两种方式

### 方式 A · 纯云端编译（推荐，零本地环境）

不需要安装 Flutter / Android SDK / Xcode，也不需要任何签名密钥：

```bash
cd leanpath
git init && git add . && git commit -m "init LeanPath"
git remote add origin https://github.com/<你的账号>/leanpath.git
git push -u origin main
```

GitHub → **Actions** → `cloud-build` → **Run workflow**（可选平台 / debug|release）→
在该次 Run 的 **Artifacts** 下载 APK / AAB / IPA。
`scripts/prepare_native_shells.py` 会在 Runner 上自动补齐原生壳工程并保留本仓库定制配置，
详见 `docs/CLOUD_BUILD.md`。

### 方式 B · 本地开发调试

```bash
# 1) 生成原生壳工程（顺序很重要）
flutter create --platforms=android,ios --org cn.leanpath.app --project-name leanpath .

# 2) flutter create 会覆盖原生配置，把本仓库这些文件覆盖回来：
#    android/app/src/main/AndroidManifest.xml、android/app/build.gradle.kts、
#    android/app/proguard-rules.pro、android/app/src/main/kotlin/cn/leanpath/app/MainActivity.kt、
#    ios/Runner/Info.plist、ios/Runner/AppDelegate.swift
#    （用 git checkout -- <路径> 即可恢复）

# 3) 依赖与本地化
flutter pub get && flutter gen-l10n

# 4) 运行
flutter run                  # Android 真机优先，用于验证精确闹钟与保活
open ios/Runner.xcworkspace  # Xcode 补全 Team / Bundle ID / Signing
```

也可以直接用 `python3 scripts/prepare_native_shells.py` 代替第 1、2 步（自动备份 → 生成 → 恢复）。
`pubspec.yaml` 里插件版本是参考基线，若 `flutter pub get` 报冲突，按 pub.dev 最新稳定版调整。

## 云端编译

| 工作流 | 触发 | 密钥 | 产出 |
|---|---|---|---|
| `cloud-build.yml` | 手动 / push main 相关路径变更 | 零 | debug\|release APK、release AAB、未签名 IPA |
| `ci.yml` | PR / push / 手动 | 零 | 质量门禁 + 双端 debug 冒烟构建 |
| `release.yml` | tag `v*` / 手动 | 全部签名 Secrets | 正式签名 AAB / APK / IPA → 上架 |

零密钥产物用 debug 签名，**只能内测，不能上架**；iOS 产物未签名，仅用于验证编译。
正式发布需要配置 Secrets，见 `docs/CICD.md`。

## 目录

```
lib/                     业务代码（models / services / state / ui）
i18n/l10n/               中英文 ARB 源（gen-l10n 输出到 lib/l10n）
android/ · ios/          定制的原生配置（壳工程由 CI 或本地生成）
scripts/                 prepare_native_shells.py：云端生成/恢复原生壳
.github/workflows/       cloud-build.yml（云端编译）· ci.yml · release.yml
fastlane/                Fastfile / Gemfile / Appfile
docs/                    架构、云端编译、CI/CD、权限、隐私、国内上架、审核清单、功能开关、埋点
store-listing/           china/（首发用）· app-store/ · google-play/（出海参考）
```

## 双端关键差异（详见 `docs/ARCHITECTURE.md`）

| | Android | iOS |
|---|---|---|
| 闹铃 | AlarmManager 精确闹钟 + 全屏锁屏提醒 | 本地通知 + Time Sensitive，**无持续响铃**（声音 ≤30s） |
| 排期 | 滚动排 14 天 | 系统上限 64 个，只排 7 天并滚动重排 |
| 保活 | 需自启动 + 关闭电池优化（国内 ROM 必做） | 不需要，系统调度 |
| 感知 | `ACTIVITY_RECOGNITION` + 计步传感器 | Core Motion + `NSMotionUsageDescription` |

> iOS 真正「像闹铃一样一直响」需要 Critical Alerts 特殊授权（Apple 审批），本版本未申请，
> 当前用高优先级通知 + 稍后提醒 + 一键打卡逼近体验。

## CI/CD 与上线

- 中国大陆差异：不使用 `upload_to_play_store` / FCM；Android 交国内商店后台，
  iOS 中国区需 **App 备案号**。
- 发布节奏：`v1.0.0-beta.1` 内测 → `v1.0.0` 灰度 10% → 全量。
- 完整 Secrets 清单、发布流程与回滚见 `docs/CICD.md`。

## 合规（中国大陆，必读）

1. 三张硬门槛：**软件著作权、工信部 App 备案、可访问的隐私政策 URL**。
2. 健康/减肥类红线：禁疗效与绝对化承诺、禁医疗术语、必须带免责声明。
3. 体重与步数属敏感个人信息：单独同意、仅存本机、可撤回、政策需含双清单。
4. 详见 `docs/CHINA_RELEASE.md`、`docs/PERMISSIONS.md`、`docs/PRIVACY.md` 与 `docs/checklists/`。

## 下一步（需人工或 CI 执行）

- [ ] 创建 GitHub 仓库并推送代码，手动跑一次 `cloud-build` 验证云端编译
- [ ] 需要正式签名包时：生成 Android keystore、配置 GitHub Secrets、跑通 `v0.9.0-beta.1`
- [ ] Xcode 补全 Signing（方式 B / release 的 iOS 签名需要）
- [ ] 补齐 `docs/PRIVACY.md` 待办：隐私政策页、双清单、数据导出/删除入口
- [ ] 启动软著与 App 备案；按 `store-listing/china/metadata.md` 产出图标/截图
- [ ] 华为/小米/OPPO/vivo 真机验证：锁屏准点响铃、重启恢复、通知按钮打卡
- [ ] 补单元测试（PlanEngine 边界值、打卡连续天数）与 Maestro E2E

## 能力边界

本环境没有 Android SDK / Xcode / Flutter SDK，也没有 GitHub 凭据，因此**不能在此直接触发
真实构建**。所有编译、签名、提审需在你的开发机或 CI Runner 上执行。证书、keystore、私钥
一律只给配置方式与环境变量引用，仓库内不含任何明文密钥。
