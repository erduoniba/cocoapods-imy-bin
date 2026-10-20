# cocoapods-imy-bin 技术文档

本文档描述当前 fork 的设计、配置、开发方式与兼容性边界。内容基于仓库提交 `1eb9f4a`，审阅日期为 2026-09-07。

本仓库是一套 CocoaPods 二进制化工具链：`cocoapods-imy-bin/` 负责依赖切换、构建和发布，`binary-server/` 保存并提供二进制制品，`apps/IMYBinManager/` 提供类似 MTool 的原生 macOS 操作入口。

## 阅读路径

| 文档 | 内容 | 适合读者 |
| --- | --- | --- |
| [架构设计](architecture.md) | 加载链路、Hook、依赖切换和构建发布流程 | 维护者、代码评审者 |
| [配置与运维](configuration-and-operations.md) | 私有源、Podfile DSL、命令和产物目录 | 接入方、CI 维护者 |
| [开发与测试](development.md) | Ruby 环境、依赖安装、测试及发布检查 | 插件开发者 |
| [兼容性评估](compatibility.md) | 已验证范围、已知风险和升级路线 | 技术负责人、迁移决策者 |
| [二进制服务端](binary-server.md) | HTTP 协议、存储方式、启动验证和生产化风险 | 服务端、运维、客户端开发者 |
| [团队平台第一阶段实现](platform-foundation.md) | 新平台 API、策略快照、开发联调和投产阻断项 | 维护者、试点接入方 |
| [macOS 应用设计](macos-app-design.md) | MTool 功能映射、产品边界与桌面端演进方案 | 产品、客户端开发者 |

## 当前结论

该 fork 可以继续维护并服务已有工程，但不应被视为已经适配最新工具链：

- 建议先以 Ruby 3.1.2、CocoaPods 1.15.2、`cocoapods-generate` 2.2.5 和 Xcodeproj 1.25.0 建立可复现基线。
- 插件入口和 native patch 已在 CocoaPods 1.16.2 下完成加载级验证；仓库虽包含配套上传服务，但没有真实私有源和示例组件，仍未完成端到端验收。
- `binary-server/` 的接口与插件协议匹配，但实现依赖老旧、无认证且存在版本删除误删风险，只适合隔离环境联调。
- `IMYBinManager` 已支持工程检查、CLI 任务、日志，以及只读检测和浏览二进制服务。
- 构建器仍生成传统静态 framework，模拟器仅构建 `x86_64`；Apple Silicon 模拟器与 Xcode 26 需要专项改造。
- 自动化测试仅覆盖 `pod bin` 命令注册，核心解析、构建、上传与调试流程依赖人工验证。

## 文档约定

除特别说明外，命令均从 gem 子目录执行：

```bash
cd cocoapods-imy-bin
```

示例中的仓库地址、服务地址和组件名均为占位符，接入时必须替换，且不得提交令牌或真实上传凭据。
