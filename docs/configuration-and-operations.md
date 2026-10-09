# 配置与运维

## 用户级配置

执行 `pod bin init` 后，配置写入 CocoaPods home 目录（通常为 `~/.cocoapods/`）。插件按环境读取三个文件：

| 环境 | 文件 |
| --- | --- |
| `dev` | `bin_dev.yml` |
| `debug_iphoneos` | `bin_debug_iphoneos.yml` |
| `release_iphoneos` | `bin_release_iphoneos.yml` |

示例：

```yaml
configuration_env: dev
code_repo_url: git@code.example.com:ios/spec-source.git
binary_repo_url: git@code.example.com:ios/spec-binary.git
binary_download_url: https://artifacts.example.com/frameworks/%s/%s/zip
download_file_type: zip
```

`binary_download_url` 的两个 `%s` 依次替换为组件名和版本。当前上传地址通过直接去掉固定后缀 `/%s/%s/zip` 得到，因此该 URL 必须严格遵守此格式。配置文件不得包含访问令牌；SSH 凭据应由 Keychain、CI secret 或部署密钥提供。

仓库内的 `binary-server/` 正是该 URL 对应的配套服务。启动、接口和风险说明见[二进制服务端](binary-server.md)。它当前没有认证能力，只能在本机或隔离网络联调。

## 工程级配置

组件工程根目录可放置 `BinArchive.json`：

```json
{
  "archive-white-pod-list": ["YYTargetDemo", "YYModel"],
  "ignore-git-list": ["git@code.example.com:third-party/"],
  "ignore-http-list": ["https://code.example.com/third-party/"],
  "xcode_build_path": "xcode-build/Build/Intermediates.noindex/ArchiveIntermediates/Target/IntermediateBuildFilesPath/UninstalledProducts/iphoneos/"
}
```

- `archive-white-pod-list`：不生成二进制的组件名；
- `ignore-git-list` / `ignore-http-list`：按源码 URL 片段跳过依赖；
- `xcode_build_path`：已有 Xcode archive 产物的路径；
- `root_dir`：可选，自定义制品根目录。

仓库当前自带的 `BinArchive.json` 末尾有多余逗号，`JSON.parse` 会失败。复制示例时请使用上面的合法 JSON；后续应单独修复仓库文件。

## Podfile DSL

插件声明必须出现在 DSL 之前：

```ruby
plugin 'cocoapods-imy-bin'

set_configuration_env 'dev'
use_binaries!
set_use_source_pods %w[LocalFeature DebugTools]
```

也可以只选择部分组件使用二进制：

```ruby
plugin 'cocoapods-imy-bin'

use_binaries_with_spec_selector! do |spec|
  %w[FoundationKit NetworkKit].include?(spec.root.name)
end
```

支持的环境变量键为小写：`use_plugins`、`use_binaries`、`use_source_pods` 和 `allow_prerelease`。源码白名单以 `|` 分隔：

```bash
use_plugins=cocoapods-imy-bin \
use_binaries=true \
use_source_pods='LocalFeature|DebugTools' \
pod install
```

当前 `configuration_env` 的环境变量读取逻辑不能可靠覆盖默认值，CI 中应使用 `set_configuration_env` 或命令的 `--env` 参数。

## Podfile_local 与 BinPodfile

`pod bin install` 和 `pod bin update` 会读取工程根目录的 `Podfile_local`，合并同名 target 的 dependencies，并以本地 pre/post-install Hook 覆盖主 Podfile Hook。本地 `:path` 依赖会加入源码白名单。

`pre_install` 阶段还会用 `instance_eval` 执行 `BinPodfile`。它适合存放团队共享的插件 DSL，但具备执行任意 Ruby 代码的能力，只能接受经过评审的内容。

## 常用命令

| 命令 | 用途 |
| --- | --- |
| `pod bin init` | 交互生成当前环境配置 |
| `pod bin install` | 合并 `Podfile_local` 后执行 `pod install` |
| `pod bin update` | 合并 `Podfile_local` 后执行 `pod update` |
| `pod bin archive Foo.podspec --env=dev` | 构建组件二进制 |
| `pod bin archive Foo.podspec --all-make` | 同时构建缺失二进制的依赖 |
| `pod bin auto Foo.podspec --env=dev` | 构建、上传、推 spec 并更新仓库 |
| `pod bin code Foo` | 下载或连接源码，使二进制断点可跳转 |
| `pod bin code Foo --source=/path/to/Foo` | 连接指定本地源码 |
| `pod bin code --list` | 查看已下载源码 |
| `pod bin code Foo --clean` | 清理指定组件源码 |

先用 `archive --no-clean` 排查构建问题，确认 zip 和二进制 spec 正确后再运行 `auto`。`auto` 会上传制品和推送仓库，属于有外部副作用的发布操作，不应作为本地冒烟测试。

## 故障定位顺序

1. 用 `which ruby`、`which bundle`、`which pod` 确认三者来自同一个 Ruby 环境。
2. 执行 `bundle check`，确认锁文件依赖完整。
3. 检查三份 YAML 与所选 `--env` 一致，私有源可 clone、制品服务可访问。
   可先运行 `curl --fail http://localhost:8080/frameworks`，也可在 IMYBinManager 的“制品服务”页执行只读检测。
4. 保留 `bin-archive/` 和完整 `xcodebuild` 输出，先定位生成工程还是编译失败。
5. 检查 `bin-zip/`、`bin-json/`，再排查上传和 spec push。
6. 二进制存在但仍使用源码时，核对组件版本、源码白名单、selector 结果及源优先级。
