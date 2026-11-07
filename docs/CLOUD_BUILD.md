# 云端编译指南（GitHub Actions）

## 一、先说结论：能实现到哪一步

**「云端编译」已经配置完成**：把仓库推到 GitHub 后，无需本地 Flutter SDK / Android SDK /
Xcode / 任何密钥，就能在云端编译出 Android APK（含 AAB）与 iOS 构建产物，并从 Actions
的 Artifacts 下载。

**但我无法在当前会话里直接替你按下「运行」**：本机没有 Flutter/Dart/Java/Android SDK/Xcode，
没有 GitHub CLI、token，目录也还不是 git 仓库。真实构建必须由 GitHub 的 Runner 执行，
需要你先把代码推到远程仓库（见第三节）。

## 二、三条流水线怎么选

| 工作流 | 触发 | 需要密钥 | 产出 | 用途 |
|---|---|---|---|---|
| `cloud-build.yml` | 手动 Run workflow；或 push main 且改动 `lib/`、`pubspec.yaml` 等 | **零** | debug/release APK、release AAB、未签名 IPA | 日常云端编译、验证代码能不能编过、给同事发内测包 |
| `ci.yml` | PR / push main / 手动 | 零 | debug APK、iOS debug .app | 质量门禁：格式、analyze、test、双端冒烟构建 |
| `release.yml` | tag `v*` / 手动 | 全部签名 Secrets | 正式签名 AAB / APK / IPA | 提审与上架（见 `docs/CICD.md`） |

`cloud-build.yml` 手动触发时可选：`platform`（android / ios / both）、
`build_mode`（debug / release）、`regenerate_shell`（强制重建原生壳）。

## 三、最短接入路径

```bash
cd leanpath
git init
git add .
git commit -m "init LeanPath"
# 在 GitHub 建一个空仓库后：
git remote add origin https://github.com/<你的账号>/leanpath.git
git push -u origin main
```

然后：GitHub 仓库 → **Actions** → 左侧 `cloud-build` → **Run workflow** →
选平台与模式 → 运行结束在该次 Run 页面底部 **Artifacts** 下载。

> 推送需要 GitHub 账号凭据（PAT 或 SSH Key）。**不要**把 token 写进仓库或命令历史。
> 若希望由我直接触发并回收构建结果，需要先在 WorkBuddy 中连接 GitHub 类集成或授权仓库访问。

## 四、关键设计：CI 自己生成原生壳

仓库里只提交了我们定制的 `AndroidManifest.xml`、`build.gradle.kts`、`MainActivity.kt`、
`Info.plist`、`AppDelegate.swift`，**没有** `flutter create` 生成的 gradle wrapper、
`Runner.xcodeproj`、Podfile 等壳文件。直接编译必然失败。

`scripts/prepare_native_shells.py` 解决这个问题：

```
1. 快照 6 个定制文件的字节内容
2. 在系统临时空目录执行 flutter create --org cn.leanpath --project-name app
   （--org + --project-name 组合得到的 applicationId / Bundle ID 正好是 cn.leanpath.app）
3. 只把临时项目的 android/ 与 ios/ 拷回仓库（不碰 pubspec.yaml / lib/ / i18n/）
4. patch Runner.xcodeproj 的 PRODUCT_BUNDLE_IDENTIFIER 与 IPHONEOS_DEPLOYMENT_TARGET=13.0，
   并取消注释 Podfile 的 platform
5. 恢复 6 个定制文件，覆盖 Flutter 默认模板
```

在**临时目录**生成而不在项目根跑 `flutter create`，是因为后者会重写 `pubspec.yaml`
和 `lib/main.dart`，把依赖与业务代码冲掉。

`ci.yml` / `cloud-build.yml` / `release.yml` 的三个构建 job 都在 `flutter-action` 之后调用它；
本机没有 Flutter SDK 时可用 `python3 scripts/prepare_native_shells.py --dry-run` 自检。

### 两种模式

| 模式 | 做法 | 适用 |
|---|---|---|
| A · 纯云端（默认） | 什么都不做，CI 每次自动生成壳 | 无本地 Flutter 环境、想最快跑通 |
| B · 本地提交壳 | 本地 `flutter create ...` 并把定制文件覆盖回来，提交 `android/`、`ios/` | 需要自定义 Xcode Signing / 原生依赖，构建更稳定 |

脚本检测到壳工程已存在会自动跳过生成，因此两种模式可无缝切换；
手动触发时勾 `regenerate_shell` 可强制重建。

## 五、产物说明与限制

| 产物 | 签名 | 能做什么 |
|---|---|---|
| debug APK | Android 默认 debug key | 直接装 Android 真机测试 |
| release APK / AAB | **debug key**（零密钥时 `build.gradle.kts` 自动回退） | 内测、验证 release 混淆；**不能上架**，商店会拒绝 debug 签名 |
| LeanPath-unsigned.ipa | 未签名 | 仅证明 iOS 编译通过、供后续重签名；**不能装真机**，也不是模拟器包 |
| release.yml 的 IPA / AAB | 正式签名 | 提审上架，需 Secrets |

iOS 编译跑在 `macos-14` Runner 上（Linux 无法编译 iOS）；GitHub Actions 的 macOS
分钟数与免费额度不同，若开通了 push 触发会消耗较多，可删掉 `cloud-build.yml` 里的
`push` 段改为纯手动触发。

## 六、什么时候才需要 Secrets

| 场景 | 需要 |
|---|---|
| 云端编译 / 冒烟构建 / 内测 debug 包 | 无 |
| 正式签名 Android 包 | `ANDROID_KEYSTORE_*` 四个 |
| 正式签名 iOS 包 / TestFlight | `IOS_CERTIFICATE_*`、`IOS_PROVISIONING_PROFILE_BASE64`、 `IOS_PROFILE_NAME`、`APPLE_TEAM_ID`、`KEYCHAIN_PASSWORD`、`ASC_*` 三个 |
| 蒲公英内测分发 | `PGYER_API_KEY` |
| 华为商店自动上传 | `HUAWEI_*` 三个 |

完整清单见 `docs/CICD.md`。**任何私钥/keystore 都不要提交仓库**。

## 七、常见失败

| 现象 | 处理 |
|---|---|
| `flutter: command not found` | 该 job 缺少 `subosito/flutter-action` 步骤 |
| `pub get` 版本冲突 | `pubspec.yaml` 插件版本是参考基线，按 pub.dev 最新稳定版调整 |
| `pub get` 报 `intl ... version solving failed` | `flutter_localizations` 随 Flutter stable 升级会改变 `intl` 约束（当前 stable 为 `^0.20.3`）；同步修改 `pubspec.yaml` 的 `intl` 版本 |
| CocoaPods 报最低版本过低 | 调 `prepare_native_shells.py` 里的 `IOS_DEPLOYMENT_TARGET` |
| Xcode signing 失败（release） | 补 `APPLE_TEAM_ID` / 描述文件名，或用 Xcode 本地补全 Signing 后走模式 B |
| `gen-l10n` 报错 | 检查 `.arb` 是否合法 JSON、是否含 `@@locale` |
| iOS 构建排队久 | macOS Runner 资源有限，改纯手动触发或换用第三方云编译服务 |

## 八、备选云端编译服务

| 服务 | 特点 | 适用 |
|---|---|---|
| GitHub Actions（当前方案） | 配置即代码、免费额度、macOS Runner | 已选方案 |
| Codemagic | Flutter 专用、自带签名管理、iOS 构建体验好 | 团队想少维护 CI YAML |
| Bitrise | 移动 CI 成熟、步骤商店丰富 | 已有移动 CI 体系 |
| Gitee Go / CODING / 云效 | 境内访问稳定、可提供 macOS 构建机 | GitHub 访问不稳或数据合规要求境内 |

换服务时，`scripts/prepare_native_shells.py` 可直接复用，只需把三条 workflow 的步骤
翻译成对应平台的构建脚本；中国大陆上架的合规要求不变（`docs/CHINA_RELEASE.md`）。
