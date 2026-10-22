# IMYBinManager

原生 macOS SwiftUI MVP，通过子进程调用当前 Ruby 插件，不复制 MTool 的代码、品牌、资源或内部服务。

## 运行

```bash
cd apps/IMYBinManager
swift run IMYBinManager
```

应用会从登录 shell 读取环境，并自动识别工作区中的 `.imy-infra/home`（`CP_HOME_DIR`）与本地插件源码目录（`RUBYLIB`）。选择工作区根目录（如 `ImyBin`）、宿主 App 目录（如 `HDImyBinApp`）或单个组件目录（如 `HDDynamicPod`）后，应用会自动关联合并宿主 App 的 `Podfile` 与所有可发布组件的 `.podspec`。

## 核心功能（双窗口分离架构）

1. **窗口 1：App 依赖管理工作台（快捷键 `⇧⌘1`）**
   - 面向宿主 App，自动生成并维护 `.imy-bin-config.json` 配置表（`Podfile` 仅保留 `imy_bin_config_dependencies`，保持 `Podfile` 零修改以避免 Git 冲突）。
   - 支持编辑各组件的启用状态、目标版本号（可从 `binary-server` 已发布版本下拉选择或一键采用本地 `podspec` 版本）及 `local` / `source` / `binary` 三态模式。
   - 一键执行 `生成配置表并安装 (pod bin install)`、`pod bin update`、`pod bin status`，并支持勾选**“切换模式后自动执行 pod bin install”**。

2. **窗口 2：组件管理与发布工作台（快捷键 `⇧⌘2`）**
   - **组件依赖管理页**：
     - **组件对外依赖（`.podspec` `s.dependency`）**：可视化查看、添加、修改版本约束或删除 `<Component>.podspec` 中的 `s.dependency`。
     - **组件 Example 调试工程配置表（`<Component>/Example/.imy-bin-config.json`）**：管理组件自身 `Example` 工程的下层依赖（支持切换 `local` / `source` / `binary` 模式与版本），并一键在 `Example` 目录执行 `pod bin install` / `pod bin update`。
   - **组件版本与发布页**：
     - **版本管理**：支持一键递增版本号（`Patch +1` / `Minor +1` / `Major +1`），写入 `.podspec`，自动同步至宿主 App 的 `.imy-bin-config.json` 配置表（不修改 `Podfile`），并自动提交组件 Git 仓库版本变更。
     - **发布前状态检查**：实时检测组件仓库 Git 分支、工作区干净状态、当前版本 Git Tag 状态及 `binary-server` 已发布版本列表。
     - **构建与发布编排**：提供**仅构建二进制 (`pod bin archive`)**、**发布预检 (`pod bin publish --dry-run`)** 与带二次确认弹窗的**正式发布组件 (`pod bin publish`)**。

## 验证

```bash
swift build
swift test
```

## 打包与分发 App

```bash
./Scripts/package-app.sh
open dist/IMYBinManager.app
```

默认会生成带有 ad-hoc 本地签名的 `.app`，以及用于分发的 `.zip` 和 `.dmg` 镜像（位于 `dist/` 目录下）。详细参数与发布指南详见 [Scripts/README.md](Scripts/README.md)。正式对外分发需配置独立 Bundle ID、Developer ID、Hardened Runtime 和 notarization。

工程依赖页现可读取本地 `.imy-bin-policy.json`，并通过 `pod bin sync`、`pod bin switch` 启动实验性策略同步和个人模式切换；详见 [团队平台第一阶段实现](../../docs/platform-foundation.md)。这不是生产发布界面。

## 当前限制

- 尚未开放 `pod bin auto`，避免在没有发布预检和二次确认时上传制品。
- 制品服务暂只支持列表查询，不支持上传和删除。
- 尚未解析 CocoaPods 日志为结构化进度；当前按原始文本显示。
- 未提供模块市场、审批、CI 或聊天能力；这些功能应在现有 `binary-server` 生产化后扩展。
- 当前 Ruby 插件本身仍需完成 Xcode 26/Apple Silicon/XCFramework 兼容改造。
