# CI/CD 与上线路径（GitHub Actions + Fastlane）

## 一、三条流水线

| 文件 | 触发 | 做什么 | 产物 | 需要密钥 |
|---|---|---|---|---|
| `.github/workflows/cloud-build.yml` | 手动 Run workflow / push main 相关路径变更 | 云端自动生成原生壳 → `pub get` → `gen-l10n` → `analyze` → `test` → 构建 APK/AAB/未签名 IPA | Android APK / AAB、iOS unsigned IPA（Artifacts 30 天） | **零** |
| `.github/workflows/ci.yml` | PR / push main / 手动 | 格式检查 → `analyze` → `test` → 双端 debug 冒烟构建 | debug APK、构建日志 | 零 |
| `.github/workflows/release.yml` | tag `v*` / 手动（可选 iOS 轨道） | 从 Secrets 恢复签名 → AAB + 分架构 APK / IPA → TestFlight → 可选蒲公英内测、华为商店上传 | 正式签名产物 | 全部 |

> 「零密钥云端编译」的完整说明、产物限制与触发方式见 `docs/CLOUD_BUILD.md`。
> 三条流水线的构建 job 都先运行 `scripts/prepare_native_shells.py`，无需本地提交原生壳。

发布节奏：`v1.0.0-beta.1` → 蒲公英/TestFlight 内测 → `v1.0.0` → 国内商店灰度（先 10%）→ 全量。

## 二、GitHub Secrets 清单

> 只有 `release.yml` 需要下表；`cloud-build.yml` 与 `ci.yml` 完全不需要 Secrets。

| Secret | 平台 | 用途 | 必填 |
|---|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | Android | release.jks 的 Base64 | ✅ |
| `ANDROID_KEYSTORE_PASSWORD` | Android | keystore 口令 | ✅ |
| `ANDROID_KEY_ALIAS` | Android | 密钥别名 | ✅ |
| `ANDROID_KEY_PASSWORD` | Android | 密钥口令 | ✅ |
| `IOS_CERTIFICATE_P12_BASE64` | iOS | Distribution 证书 p12 | ✅ |
| `IOS_CERTIFICATE_PASSWORD` | iOS | p12 口令 | ✅ |
| `IOS_PROVISIONING_PROFILE_BASE64` | iOS | AppStore 描述文件 | ✅ |
| `IOS_PROFILE_NAME` | iOS | 描述文件名（gym `export_options.provisioningProfiles` 用） | 建议 |
| `APPLE_TEAM_ID` | iOS | gym `signingStyle: manual` 的 Team ID | 建议 |
| `KEYCHAIN_PASSWORD` | iOS | CI 临时钥匙串口令（任意强随机值） | ✅ |
| `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_PRIVATE_KEY` | iOS | App Store Connect API Key（避免 2FA） | ✅ |
| `PGYER_API_KEY` | Android | 蒲公英内测分发 | 可选 |
| `HUAWEI_CLIENT_ID` / `HUAWEI_CLIENT_SECRET` / `HUAWEI_APP_ID` | Android | 华为 AppGallery Publishing API | 可选 |

生成本地资产的 Base64（不要提交原文件）：

```bash
# Git Bash / Linux
base64 -w0 release.jks > keystore.b64
base64 -w0 cert.p12 > cert.b64
# Windows PowerShell
# [Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks"))
```

## 三、首次接入步骤

1. **建仓库并推送代码**（云端编译的唯一前置动作）：
   `git init && git add . && git commit -m "init" && git remote add origin <url> && git push -u origin main`。
   推送需要 GitHub PAT 或 SSH Key，不要把 token 写进仓库。
2. **先跑一次零密钥云端编译**：Actions → `cloud-build` → Run workflow（platform=both,
   build_mode=debug）→ 下载 Artifacts。这一步验证整条工具链，不依赖任何签名资产。
3. 原生壳工程有两种模式，脚本会自动判断：
   - **模式 A（默认）**：不提交 `android/`、`ios/` 壳，CI 每次用
     `scripts/prepare_native_shells.py` 在临时目录生成并恢复定制配置；
   - **模式 B**：本地执行
     `flutter create --platforms=android,ios --org cn.leanpath.app --project-name leanpath .`，
     把本仓库的 `AndroidManifest.xml`、`build.gradle.kts`、`MainActivity.kt`、
     `proguard-rules.pro`、`Info.plist`、`AppDelegate.swift` 覆盖回去后提交壳工程，
     脚本检测到壳已存在会跳过生成。适合需要自定义 Xcode Signing 的场景。
4. iOS 正式签名：用 Xcode 打开 `ios/Runner.xcworkspace` 设置 Team / Bundle ID
   `cn.leanpath.app` / Signing；或在 `release.yml` 用 `APPLE_TEAM_ID` + 描述文件走手动签名。
5. 生成 Android 签名密钥（妥善离线备份，丢失将无法更新应用）：
   `keytool -genkey -v -keystore release.jks -alias leanpath -keyalg RSA -keysize 2048 -validity 10000`
6. 在仓库 Settings → Secrets 里按上表填入；推 `v0.9.0-beta.1` 验证签名与上传链路。
7. 按 `docs/CHINA_RELEASE.md` 完成软著、App 备案、隐私政策后再提正式审核。

## 四、上线路径（单次发布）

```
git tag v1.0.0 && git push origin v1.0.0
   │
   ├─ cloud-build.yml / ci.yml（日常云端编译与质量门禁，不进入发布链）
   │
   └─ release.yml
        ├─ prepare_native_shells.py → pub get → gen-l10n
        ├─ Android：签名 → AAB + split APK → Artifacts
        │            ├─ 蒲公英内测（PGYER_API_KEY 存在时）
        │            └─ 华为商店（凭据存在时）/ 其余商店人工上传
        └─ iOS：预热 Pods → 导入证书 → gym → TestFlight
                 └─ App Store Connect 选构建 + 填 App 备案号 → 提交审核
                          └─ 过审后手动/定时发布，先灰度再全量
```

## 五、回滚与应急

- **Android**：国内商店后台撤回待发布版本 / 下架；已发布版本无法覆盖，只能发新版本号
  （`versionCode` 必须递增）。用功能开关（`docs/feature-flags`）远程关闭「闹铃」等高风险功能。
- **iOS**：停止 TestFlight 外部测试；已上架版本可「下架」或在紧急情况下提交加急审核的新版本。
- **热修复**：Flutter 不具备官方热更新能力，国内 Android 商店对热修复/动态下发有严格限制，
  iOS 禁止下发可执行代码；生产问题优先用功能开关降级 + 发版修复。

## 六、常见失败

| 现象 | 原因与处理 |
|---|---|
| 编译报缺 `android/gradle/wrapper` 或 `Runner.xcodeproj` | 该 job 没有运行 `prepare_native_shells.py`；或勾 `regenerate_shell` 强制重建 |
| `flutter: command not found` | 缺少 `subosito/flutter-action` 步骤，或 Python 脚本跑在 flutter-action 之前 |
| `flutter pub get` 版本冲突 | `pubspec.yaml` 里插件版本为参考基线，按 pub.dev 最新稳定版调整 |
| `gen-l10n` 失败 | 检查 `.arb` 是否为合法 JSON（无尾随逗号）、是否含 `@@locale` |
| CocoaPods 报最低系统版本过低 | 调 `scripts/prepare_native_shells.py` 里的 `IOS_DEPLOYMENT_TARGET` |
| Android 通知不准时 | 精确闹钟权限未授予 / 厂商 ROM 电池优化，见 `docs/PERMISSIONS.md` |
| iOS gym 报签名错误 | 描述文件与 Bundle ID 不匹配、`IOS_PROFILE_NAME` 不对，或缺 `APPLE_TEAM_ID` |
| Ruby 安装慢 | `fastlane/Gemfile` 切换到 `gems.ruby-china.com` 镜像 |
