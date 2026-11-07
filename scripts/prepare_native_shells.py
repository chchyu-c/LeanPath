#!/usr/bin/env python3
"""在 CI / 本地生成 Flutter 原生壳工程，同时保留本仓库定制的双端配置。

解决的问题：仓库只提交了 AndroidManifest.xml / Info.plist / AppDelegate.swift 等
定制文件，没有 `flutter create` 生成的 gradle wrapper、Runner.xcodeproj 等壳文件。
直接推送到 GitHub 会编译失败。本脚本在**临时空目录**里生成壳工程，只把
android/ 与 ios/ 拷回来，再恢复定制文件，因此不会碰 pubspec.yaml / lib/ / i18n/。

用法：
  python3 scripts/prepare_native_shells.py              # 缺壳则生成，已有壳则跳过
  python3 scripts/prepare_native_shells.py --force     # 强制重新生成壳
  python3 scripts/prepare_native_shells.py --dry-run   # 只检查，不调用 flutter

CI 中由 cloud-build.yml / ci.yml / release.yml 在 flutter-action 之后调用。
本机没有 Flutter SDK 时可用 --dry-run 做自检，不会写入任何文件。
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "cn.leanpath.app"
IOS_DEPLOYMENT_TARGET = "13.0"

# --org cn.leanpath + --project-name app => applicationId / Bundle ID = cn.leanpath.app
CREATE_ORG = "cn.leanpath"
CREATE_PROJECT_NAME = "app"

# 注意：android/app/build.gradle.kts 刻意不覆盖，保留 Flutter 生成的模板。
# Flutter 3.47 / AGP 9 把旧 `android {}` / `kotlinOptions {}` DSL 的弃用用法
# 升级为编译错误，自定义脚本会直接让 Gradle script compilation 失败。
# 签名改由 CI 通过 android/gradle.properties 的 android.injected.signing.* 注入。
CUSTOM_FILES = (
    "android/app/src/main/AndroidManifest.xml",
    "android/app/proguard-rules.pro",
    "android/app/src/main/kotlin/cn/leanpath/app/MainActivity.kt",
    "ios/Runner/Info.plist",
    "ios/Runner/AppDelegate.swift",
)


def shell_exists() -> bool:
    return (
        (ROOT / "android/gradle/wrapper/gradle-wrapper.properties").is_file()
        and (ROOT / "ios/Runner.xcodeproj/project.pbxproj").is_file()
    )


def snapshot() -> dict[str, bytes]:
    return {
        rel: (ROOT / rel).read_bytes()
        for rel in CUSTOM_FILES
        if (ROOT / rel).is_file()
    }


def restore(saved: dict[str, bytes]) -> None:
    for rel, data in saved.items():
        path = ROOT / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        print(f"  restored {rel}")


def patch_ios_project() -> None:
    """对齐 Bundle ID 与最低系统版本，避免插件（通知/计步）编译期报错。"""
    pbx = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
    if pbx.is_file():
        text = pbx.read_text(encoding="utf-8")
        text, n_bundle = re.subn(
            r"(PRODUCT_BUNDLE_IDENTIFIER\s*=\s*)[^;]+;",
            lambda m: f"{m.group(1)}{BUNDLE_ID};",
            text,
        )
        text, n_target = re.subn(
            r"(IPHONEOS_DEPLOYMENT_TARGET\s*=\s*)[^;]+;",
            lambda m: f"{m.group(1)}{IOS_DEPLOYMENT_TARGET};",
            text,
        )
        pbx.write_text(text, encoding="utf-8")
        print(f"  patched bundle id ({n_bundle}) / deployment target ({n_target})")

    podfile = ROOT / "ios/Podfile"
    if podfile.is_file():
        text = podfile.read_text(encoding="utf-8")
        # Flutter 模板里 platform 行默认是注释，取消注释并抬高版本。
        text, n = re.subn(
            r"#\s*platform\s*:ios,\s*'[^']*'",
            f"platform :ios, '{IOS_DEPLOYMENT_TARGET}'",
            text,
        )
        podfile.write_text(text, encoding="utf-8")
        print(f"  patched Podfile platform ({n})")


def generate_shell() -> None:
    flutter = shutil.which("flutter")
    if flutter is None:
        sys.exit(
            "ERROR: 未在 PATH 找到 flutter。请先安装 Flutter SDK，"
            "或在 CI 中先运行 subosito/flutter-action。"
        )

    with tempfile.TemporaryDirectory(prefix="leanpath-shell-") as tmp:
        target = Path(tmp) / "shell"
        base = [
            flutter,
            "create",
            "--platforms=android,ios",
            f"--org={CREATE_ORG}",
            f"--project-name={CREATE_PROJECT_NAME}",
        ]
        try:
            subprocess.run([*base, "--no-pub", str(target)], check=True)
        except subprocess.CalledProcessError:
            print("  --no-pub 不被当前 Flutter 版本支持，回退默认 create")
            subprocess.run([*base, str(target)], check=True)

        for name in ("android", "ios"):
            shutil.copytree(target / name, ROOT / name, dirs_exist_ok=True)
            print(f"  copied {name}/ shell")

        patch_ios_project()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="生成 Flutter 原生壳并保留定制的双端配置"
    )
    parser.add_argument(
        "--force", action="store_true", help="即使壳工程已存在也重新生成"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="只检查，不调用 flutter、不写文件"
    )
    args = parser.parse_args()

    saved = snapshot()
    print(f"[prepare] root={ROOT}")
    print(f"[prepare] 定制文件 {len(saved)}/{len(CUSTOM_FILES)} 已找到")
    missing = [rel for rel in CUSTOM_FILES if rel not in saved]
    for rel in missing:
        print(f"  ! 缺失 {rel}（生成后将保留 Flutter 默认模板）")

    if args.dry_run:
        action = (
            "--force 强制重建"
            if args.force
            else ("需要生成壳工程" if not shell_exists() else "壳已存在，跳过生成")
        )
        print(f"[prepare] 壳工程状态: {'存在' if shell_exists() else '缺失'}")
        print(f"[prepare] dry-run -> {action}（未写入任何文件）")
        return 0

    if shell_exists() and not args.force:
        print("[prepare] 壳工程已存在，跳过 flutter create")
    else:
        print("[prepare] 正在临时目录生成原生壳 ...")
        generate_shell()

    restore(saved)
    print("[prepare] 完成。下一步：flutter pub get && flutter gen-l10n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
