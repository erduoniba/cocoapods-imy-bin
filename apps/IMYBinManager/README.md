# IMYBinManager

原生 macOS SwiftUI MVP，通过子进程调用当前 Ruby 插件，不复制 MTool 的代码、品牌、资源或内部服务。

## 运行

```bash
cd apps/IMYBinManager
swift run IMYBinManager
```

应用会从登录 shell 读取环境，并自动识别工作区中的 `.imy-infra/home`（`CP_HOME_DIR`）与本地插件源码目录（`RUBYLIB`）。选择工作区根目录（如 `ImyBin`）、宿主 App 目录（如 `HDImyBinApp`）或单个组件目录（如 `HDDynamicPod`）后，应用会自动关联合并宿主 App 的 `Podfile` 与所有可发布组件的 `.podspec`。

## 核心功能

1. **App 依赖与安装管理（`App 依赖与安装` 页）**
   - 扫描宿主 App `Podfile` 中的 `imy_pod` / `pod` 组件声明及 `.imy-bin-modes.yml` 本地覆盖状态。
   - 支持单组件与全局三态切换（`local` 本地开发源码 / `source` 版本化源码 / `binary` XCFramework 二进制）及 `--reset` 重置。
   - 一键执行 `pod bin install`、`pod bin update`、`pod bin status`，并支持勾选**“切换模式后自动执行 pod bin install”**。
   - 联动 `binary-server` 实时标识当前 `Podfile` 声明版本是否已发布二进制制品。

2. **组件发布管理（`组件发布管理` 页）**
   - 自动解析工作区及 `Podfile` `:path` 关联组件的 `.podspec`（名称、当前版本、`ios.deployment_target`、静/动态 XCFramework 类型）。
   - **版本管理**：支持一键递增版本号（`Patch +1` / `Minor +1` / `Major +1` 或手动输入），写入 `.podspec`，并可选**自动同步更新宿主 App `Podfile` 中的版本声明**与**自动提交组件 Git 仓库版本变更**。
   - **发布前状态检查**：实时检测组件仓库 Git 分支、工作区是否干净（列出未提交文件）、当前版本 Git Tag 是否已存在，以及 `binary-server` 上的已发布版本列表。
   - **构建与发布编排**：支持配置 `dev` / `debug_iphoneos` / `release_iphoneos`、`Release` / `Debug`、`--code-dependencies`、`--no-clean`、`--skip-tag`、`--skip-code-spec`；提供**仅构建二进制 (`pod bin archive`)**、**发布预检 (`pod bin publish --dry-run`)** 与带二次确认弹窗的**正式发布组件 (`pod bin publish`)**。

## 验证

```bash
swift build
swift test
```

## 打包本地 App

```bash
./Scripts/package_app.sh
open .build/IMYBinManager.app
```

生成的 `.app` 使用 ad-hoc 签名，仅用于本地开发。正式分发需配置独立 Bundle ID、Developer ID、Hardened Runtime 和 notarization。

工程依赖页现可读取本地 `.imy-bin-policy.json`，并通过 `pod bin sync`、`pod bin switch` 启动实验性策略同步和个人模式切换；详见 [团队平台第一阶段实现](../../docs/platform-foundation.md)。这不是生产发布界面。

## 当前限制

- 尚未开放 `pod bin auto`，避免在没有发布预检和二次确认时上传制品。
- 制品服务暂只支持列表查询，不支持上传和删除。
- 尚未解析 CocoaPods 日志为结构化进度；当前按原始文本显示。
- 未提供模块市场、审批、CI 或聊天能力；这些功能应在现有 `binary-server` 生产化后扩展。
- 当前 Ruby 插件本身仍需完成 Xcode 26/Apple Silicon/XCFramework 兼容改造。
