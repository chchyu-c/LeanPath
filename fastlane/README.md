# Fastlane / CI 使用说明

## Lane 一览

| 命令 | 作用 | 需要的前置条件 |
|---|---|---|
| `fastlane android_test` | 跑 Flutter 单测 | Flutter SDK |
| `fastlane android_build` | 生成签名 AAB + 分架构 APK | `android/key.properties` + keystore |
| `fastlane android_china_stores` | 国内商店分发（华为可选自动上传） | 商店开放平台凭据 |
| `fastlane android_pgyer` | 上传蒲公英内测 | `PGYER_API_KEY` |
| `fastlane ios_beta` | gym 打包 + 上传 TestFlight | 证书/描述文件 + `APPLE_TEAM_ID` + ASC API Key |
| `fastlane ios_release` | 上传构建 + 输出中国区提审指引 | 同上 + App 备案号 |

> lane 中的 `flutter`、`build/...` 路径均以**仓库根目录**为工作目录。
> 若你的环境提示找不到 `pubspec.yaml`，请在命令前加 `cd .. &&`。

## 本地首次准备

1. `bundle install`
2. `flutter pub get && flutter gen-l10n`
3. Android 签名：复制 `android/key.properties.example` → `android/key.properties`，
   指向本机 keystore；该文件已在 `.gitignore` 中，禁止提交。
4. iOS：用 Xcode 打开 `ios/Runner.xcworkspace`，补全 Team / Bundle ID / Signing；
   本脚手架不含 `.xcodeproj` 的签名配置，需人工或改用 `fastlane match` 管理。

## 中国大陆差异

- 不使用 `upload_to_play_store` / FCM；Android 产物交给国内商店后台或 Publishing API。
- iOS 中国区上架需在 App Store Connect 填写 **App 备案号**，详见 `docs/CHINA_RELEASE.md`。
- 华为 AppGallery Connect 提供 Publishing API，可自行实现 `scripts/huawei_upload.py`
  后由 `android_china_stores` 调用；仓库刻意不提供占位式假实现。
- 小米 / OPPO / vivo / 应用宝 目前没有统一的 fastlane action，按文档人工上传。

## 敏感资产

证书、keystore、p8 私钥、API Key 全部通过 GitHub Secrets 注入环境变量，
release workflow 结束时会删除临时 keystore 与 `key.properties`。
**绝不要把 keystore、`key.properties`、`.p12`、`.p8`、`.mobileprovision` 提交到仓库。**
