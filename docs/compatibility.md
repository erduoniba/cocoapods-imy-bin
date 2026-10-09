# 兼容性评估与升级路线

## 评估快照

以下结论基于 2026-09-07 的本地代码与环境，只表示已执行的检查，不等于正式支持声明。

| 检查项 | 环境/结果 |
| --- | --- |
| Ruby 语法 | `lib/`、`spec/` 全部通过 `ruby -c` |
| 插件入口 | Ruby 3.1.2 + CocoaPods 1.16.2，可注册 `Pod::Command::Bin` |
| native patch | CocoaPods 1.16.2，可完成加载；未执行真实依赖解析 |
| Bundler | 当前工作机 `bundle check` 失败，缺少 generate、parallel 和测试依赖 |
| 自动化测试 | 仅一个命令注册用例，无核心功能覆盖 |
| Xcode | 工作机为 Xcode 26.4，未完成 archive 端到端验证 |
| 私有基础设施 | 未提供可用源码源、二进制源和上传服务，未验证发布闭环 |

补齐临时依赖后，插件在 CocoaPods 1.16.2 下可以加载。对比 CocoaPods 1.16.2 与 1.17.0 gem，resolver 等本插件主要覆写文件没有接口变化，因此 1.17.0 具备继续验证的基础；但仍需配套 Xcodeproj 1.28.0 和真实工程测试，不能直接标记为支持。

## 版本状态

| 项目 | 当前状态 | 风险 |
| --- | --- | --- |
| 插件源码版本 | `0.3.1.2` | 低于锁文件/公开 gem 的 `0.3.1.21` |
| `Gemfile.lock` | CocoaPods 1.15.2、Xcodeproj 1.25.0 | 可作为旧基线，但不是最新环境 |
| CocoaPods | 官方最新 1.17.0 | 插件依赖未设置上限，`bundle update` 可能意外升级 |
| `cocoapods-generate` | 固定 2.2.5 | 最新发布仍为 2023 年版本，属于关键老化依赖 |
| 构建产物 | 静态 `.a`/framework + zip | 不包含 XCFramework，模拟器仅 `x86_64` |

参考：[CocoaPods 版本](https://rubygems.org/gems/cocoapods)、[CocoaPods 维护状态](https://github.com/CocoaPods/CocoaPods)、[cocoapods-imy-bin 版本](https://rubygems.org/gems/cocoapods-imy-bin/versions/0.3.1.21)、[cocoapods-generate 2.2.5](https://rubygems.org/gems/cocoapods-generate/versions/2.2.5)。

## 使用决策

### 可以继续使用

- 已有工程已经在固定 CocoaPods/Xcode 组合上稳定运行；
- 团队控制源码私有源、二进制源和上传服务；
- 能保留一套真实组件回归工程，并为 fork 持续投入维护；
- 接受暂时使用传统 framework 或仅在 Intel/Rosetta 模拟器验证。

### 应先改造再使用

- 新项目以 Apple Silicon 模拟器为主；
- 需要支持 Xcode 26、CocoaPods 1.17 或未来 1.x；
- 组件大量使用 Swift、resource bundle、subspec、modular headers 或 vendored framework；
- CI 要求制品可追溯、上传失败可回滚或凭据不可出现在命令日志中。

### 不建议直接采用

- 没有团队维护 Ruby/CocoaPods monkey patch；
- 无法建立源码/二进制双私有源和制品服务；
- 希望开箱即用并自动支持未来 Xcode；
- 需要多平台、动态 framework 或标准 XCFramework 分发。

## 已知高风险点

1. **环境分裂**：系统 Ruby、RVM Ruby、Bundler 和 `pod` 可能来自不同目录，导致已安装 gem 仍然无法加载。
2. **版本不可追溯**：源码、锁文件和公开 gem 版本不一致，且 Gemfile 默认解析公开包。
3. **构建模型老化**：真机 `arm64` 与模拟器 `x86_64` 通过 `lipo` 合并，并传递 `-fembed-bitcode`；缺少 `arm64-simulator` 和 XCFramework。
4. **内部 API 耦合**：resolver、installer、analyzer 等类被直接覆写，CocoaPods 小版本升级也可能改变语义。
5. **测试不足**：没有 source 切换、缺失回退、podspec 转换、编译或上传测试。
6. **配置与命令安全**：`BinPodfile` 被 `eval`，上传和部分文件操作通过字符串 shell 命令执行，只应处理可信输入。
7. **示例配置损坏**：仓库 `BinArchive.json` 带尾逗号，当前无法被标准 JSON 解析。

## 建议升级顺序

1. **P0：建立可复现环境**：统一 Ruby，修正 Gemfile 的本地引用，显式限制 CocoaPods，统一插件版本号，修复 `BinArchive.json`。
2. **P0：增加验收测试**：建立本地 fixture spec 源、假上传服务和最小 Objective-C/Swift 组件，覆盖成功与回退路径。
3. **P1：现代化制品**：分别 archive `iphoneos`、`iphonesimulator`，使用 `xcodebuild -create-xcframework`，移除 bitcode 假设。
4. **P1：减少 monkey patch**：逐个比对 CocoaPods 1.17 接口，为覆写方法增加契约测试和版本保护。
5. **P1：加固发布**：使用结构化 HTTP 客户端和原子化发布流程，明确失败回滚与制品校验和。
6. **P2：扩展支持矩阵**：在 CI 中测试目标 Ruby、CocoaPods、Xcode，以及 `use_frameworks!` 开关组合。

完成 P0 且真实工程的 install、archive、auto、code 全链路通过后，才应把对应工具链标记为“支持”；只通过命令加载或单元测试应标记为“实验性”。
