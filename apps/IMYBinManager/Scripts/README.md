# IMYBinManager 打包与分发脚本说明

本目录下的 `package-app.sh` 脚本负责将 `IMYBinManager` macOS Swift 客户端编译为正式的 Release 应用程序，并完成代码签名与发布产物（ZIP / DMG）制作。

---

## 1. 脚本定位与功能

* **Release 模式自动编译**：通过 Swift Package Manager 编译生成优化后的可执行文件；
* **构建标准 .app Bundle 结构**：自动配置 `MacOS/`、`Resources/`、`PkgInfo` 以及包含完整应用标识与版本的 `Info.plist`；
* **本地代码签名（Code Signing）**：默认自动进行 Ad-hoc 代码签名，免去从终端运行或被 Gatekeeper 拦截的困扰，同时支持指定正式的 Developer ID 证书；
* **分发归档与校验和计算**：自动生成 `.zip` 压缩包和 `.dmg` 磁盘安装镜像，并计算输出 SHA-256 校验和供发布验证。

---

## 2. 快速使用

进入 `IMYBinManager` 项目根目录后执行：

### 2.1 完整发布打包（默认）

生成 `.app`、`.zip` 归档以及 `.dmg` 镜像：

```bash
cd apps/IMYBinManager
./Scripts/package-app.sh
```

### 2.2 本地快速调试打包（仅生成 .app）

如果仅为了在本地测试运行，跳过耗时的 DMG 压缩：

```bash
./Scripts/package-app.sh --app-only
open dist/IMYBinManager.app
```

### 2.3 指定版本号打包

```bash
./Scripts/package-app.sh -v 1.2.0
```

### 2.4 指定正式证书签名（用于公开发布）

```bash
./Scripts/package-app.sh --sign-identity "Developer ID Application: Your Name (XXXXXXXXXX)"
```

---

## 3. 命令行参数详解

| 参数选项 | 说明 | 默认值 |
| :--- | :--- | :--- |
| `-v, --version <ver>` | 指定应用程序版本号（写入 `CFBundleShortVersionString`） | `1.0.0` |
| `--app-only` | 快速模式：仅生成并签名 `.app`，跳过 ZIP 与 DMG 制作 | 否 |
| `--no-dmg` | 跳过 `.dmg` 生成（仅保留 `.app` 和 `.zip`） | 否 |
| `--sign-identity <id>`| 指定 `codesign` 签名证书身份 | `"-"`（Ad-hoc 本地签名） |
| `-h, --help` | 查看帮助文档与示例 | - |

---

## 4. 输出产物说明

执行完成后，所有文件均输出至 `apps/IMYBinManager/dist/` 目录：

```text
dist/
├── IMYBinManager.app      # 标准 macOS 应用程序包，可直接拖至 /Applications
├── IMYBinManager.zip      # ZIP 压缩包，适用于 GitHub Release 上传或快速归档
└── IMYBinManager.dmg      # Apple 磁盘镜像，方便终端用户双击挂载安装
```

---

## 5. 常见问题排查 (FAQ)

### Q: 双击打开时提示“无法打开，因为无法验证开发者”？
脚本默认使用的是本地 **Ad-hoc 代码签名**。如果 macOS Gatekeeper 阻止运行，可执行以下命令清除隔离属性：
```bash
xattr -cr dist/IMYBinManager.app
```
或者在 macOS **系统设置 -> 隐私与安全性** 中点击“仍要打开”。

### Q: 如何支持 Apple Notarization（公证）？
若要公开发布给广大开发者安装，需在打包后使用 Developer ID 证书，并通过 Apple `notarytool` 进行公证与 stapler 缝合：
```bash
./Scripts/package-app.sh --sign-identity "Developer ID Application: xxx"
xcrun notarytool submit dist/IMYBinManager.dmg --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple dist/IMYBinManager.dmg
```
