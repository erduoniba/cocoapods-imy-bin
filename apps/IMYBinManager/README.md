# IMYBinManager

原生 macOS SwiftUI MVP，通过子进程调用当前 Ruby 插件，不复制 MTool 的代码、品牌、资源或内部服务。

## 运行

```bash
cd apps/IMYBinManager
swift run IMYBinManager
```

应用会从登录 shell 读取环境，因此 `ruby`、`bundle`、`pod` 应来自同一个 RVM、rbenv 或 asdf 环境。选择组件工程后，可执行安装、更新和二进制构建，并在日志页查看输出或取消任务。“制品服务”页可连接仓库内的 `binary-server/`，只读浏览已上传组件与版本；默认地址为 `http://localhost:8080`。

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

## 当前限制

- 尚未开放 `pod bin auto`，避免在没有发布预检和二次确认时上传制品。
- 制品服务暂只支持列表查询，不支持上传和删除。
- 尚未解析 CocoaPods 日志为结构化进度；当前按原始文本显示。
- 未提供模块市场、审批、CI 或聊天能力；这些功能应在现有 `binary-server` 生产化后扩展。
- 当前 Ruby 插件本身仍需完成 Xcode 26/Apple Silicon/XCFramework 兼容改造。
