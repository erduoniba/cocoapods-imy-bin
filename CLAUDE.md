# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 仓库定位

`cocoapods-imy-bin` 是一个 CocoaPods 插件（Ruby gem），用于在**源码依赖**与**二进制依赖**之间无感切换，从而大幅提升 iOS 工程编译速度。核心思路：维护两个私有源（源码私有源 + 二进制私有源），通过 hook CocoaPods 的解析/安装流程，在依赖解析阶段动态替换 spec 的 source，实现「有二进制用二进制、没有则自动回退源码」。参考自 [cocoapods-bin](https://github.com/tripleCC/cocoapods-bin) 与美团 zsource 方案。

**注意目录层级**：仓库根目录是外层壳，真正的 gem 源码在 `cocoapods-imy-bin/` 子目录下（gemspec、Gemfile、lib、spec 都在这里）。开发时先 `cd cocoapods-imy-bin`。

## 常用命令

所有开发命令都在 `cocoapods-imy-bin/` 子目录下执行：

```bash
cd cocoapods-imy-bin

bundle install                      # 安装开发依赖
bundle exec rake specs              # 跑全部测试（bacon 框架）
bundle exec bacon spec/command/bin_spec.rb   # 跑单个测试文件
gem build cocoapods-imy-bin.gemspec # 打包 gem
```

测试框架是 **bacon / mocha-on-bacon**（非 RSpec）。`rake specs`（默认 task）会 shuffle 后拼接 `spec/**/*_spec.rb` 交给 bacon 运行。

### 版本环境约束

- gemspec 硬锁 `cocoapods-generate = 2.2.5`，同时依赖 `parallel`、`cocoapods`。
- 大量代码用 `Pod.match_version?('~> 1.x')`（定义在 `gem_version.rb`）做 CocoaPods 版本分支，兼容 1.4 ~ 1.15.2。改动 native 层时务必考虑多版本兼容，不要假设单一 CocoaPods 版本。
- 版本号维护在 `lib/cocoapods-imy-bin/gem_version.rb` 的 `CBin::VERSION`。

### 断点调试插件本身

`.vscode/launch.json` 已配置 `rdbg`（ruby debug）：脚本指向打包好的可执行文件，`cwd` 指向一个真实 iOS 组件目录，`args` 为 `["bin", "auto"]`。调试时需把 `cwd` 改成本机上真实的 podspec 组件目录。

## 插件加载链路

理解代码从这条 require 链入手（CocoaPods 通过 `cocoapods_plugin.rb` 自动加载）：

```
cocoapods_plugin.rb
 → command.rb → command/bin.rb           # 注册所有 pod bin 子命令
 → source_provider_hook.rb               # 注册 pre_install / source_provider 两个全局 hook
 → 各命令 initialize 时 require native.rb # 按 Pod 版本注入 monkey patch
```

`native.rb` 是**猴子补丁总入口**：只在 `Pod.match_version?('~> 1.4')` 成立时，覆写 CocoaPods 内部的 resolver、installer、analyzer、validator、podfile 等一系列类。修改任何依赖切换逻辑基本都要动 `native/` 目录。

## 核心架构

### 1. 命令层 `lib/cocoapods-imy-bin/command/bin/`

所有命令都是 `Pod::Command::Bin`（抽象命令）的子类。关键命令：

- **`archive`** — 把组件打包成静态库/framework。核心编排：`generate_project`（用 cocoapods-generate 生成沙盒工程）→ `build_root_spec`（编译主组件）→ `build_dependencies`（`--all-make` 时把缺失二进制的依赖也全部编译）。产物写到 `/private/var/tmp/imy_release/<工程名>-build-temp/`（见下文路径策略）。
- **`auto`** — 一键流程：内部构造参数调用 `archive` 生成产物 → 逐个 `Upload::Helper#upload` 上传 spec/zip → `pod repo update`。是日常最常用命令。
- **`code`** — 源码调试。核心是 `link` 方法：用 `dwarfdump` 读出二进制里编译时的 `AT_comp_dir` 路径，在本机上用 `ln -s` 软链接把下载的源码挂到那个路径，让断点能跳进源码。支持 `--list` / `--clean` / `--all-clean` / `--source`（本地源码路径）。
- **`install` / `update`** — 拦截原生 `pod install/update`。核心是 `Update.load_local_podfile`，把 `Podfile_local` 里的 DSL（`pod`、plugin、pre/post_install hook、开发组件白名单）合并进主 Podfile。开发组件会被自动加入源码白名单，避免被二进制化。
- **`init` / `initHotKey` / `imy`** — 初始化配置文件、配置/执行快捷键命令。
- **`repo/update`、`spec/create`、`spec/push`** — 私有源与 spec 相关子操作。

### 2. Native 猴子补丁层 `lib/cocoapods-imy-bin/native/`

依赖切换的**真正发生地**是 `resolver.rb` 的 `resolver_specs_by_target`：

1. 拿到 CocoaPods 原生解析出的 specs。
2. 若 `use_binaries?` 或有 `use_binaries_selector`，且组件不在 `use_source_pods` 白名单，则尝试从**二进制 source** 取同版本 spec 替换；否则用**源码 source**。
3. 若二进制 source 找不到对应版本（rescue），把该 spec 记入 `missing_binary_specs`，回退源码，并把这些 spec 传给 `Archive.missing_binary_specs`（供 `--all-make` 补编译）、同时缓存 podspec 到 `bin-spec` 目录。

其余 native 文件（`installer`、`analyzer`、`pod_source_installer`、`validator`、`podfile_generator` 等）都是为配合这套切换而做的兼容性覆写。`podfile_generator.rb` 覆写 cocoapods-generate 的 `podfile_for_specs`，处理 modular headers、dependencies 合并等生成沙盒工程的细节（含大量作者的中文注释说明「为什么这么改」）。

### 3. 全局 Hook `source_provider_hook.rb`

- **`pre_install`**：自动 `pod bin repo update` 更新二进制源；`dev` 环境 + 本地库时自动把本地库加入源码白名单；同步执行工程根目录的 `BinPodfile` 文件（`eval` 到 podfile 上下文）。
- **`source_provider`**：把源码私有源、二进制私有源加入 CocoaPods 的 source 列表（`use_binaries?` 时把二进制源提前）。

### 4. Podfile DSL 扩展 `native/podfile.rb`

为 Podfile 增加插件专用 DSL：`use_binaries!`、`use_binaries_with_spec_selector!`（block 选择哪些组件用二进制）、`set_use_source_pods`（源码白名单）、`set_configuration_env`。所有 DSL 值既可从 Podfile 内部 hash 读，也可从 ENV 读（便于 CI 注入）。用这些 DSL 前 Podfile 必须先声明 `plugin 'cocoapods-imy-bin'`。

### 5. 配置系统 `lib/cocoapods-imy-bin/config/`

- **`config.rb`（`CBin.config`）** — 用户级配置，存在 `~/.cocoapods/` 下的 yml 文件。按 `configuration_env` 分三套：`bin_dev.yml`、`bin_debug_iphoneos.yml`、`bin_release_iphoneos.yml`。字段见 `template_hash`：源码源地址、二进制源地址、二进制下载/上传 url、下载文件类型等。通过 `method_missing` 代理到 OpenStruct。
- **`config_builder.rb`（`CBin::Config::Builder.instance`，单例）** — 打包过程的路径与规则中心。从工程根目录的 **`BinArchive.json`** 读取：`archive-white-pod-list`（不打二进制的白名单）、`ignore-git-list`/`ignore-http-list`（跳过打包的 git/http 源）、`xcode_build_path`（Xcode 编译缓存路径）、`root_dir`。定义了所有产物目录：`bin-archive`（沙盒工程）、`bin-zip`、`bin-spec`、`bin-json`。

### 6. Helpers `lib/cocoapods-imy-bin/helpers/`

`build_helper.rb` 是编译核心：`build_static_framework`（调 `Framework::Builder`）→ 视组件类型走 `build_static_library` + `zip_static_library` 或 `zip_static_framework`。`framework_builder.rb` / `library_builder.rb` 封装 xcodebuild 与 lipo。`upload_helper.rb` 负责上传，`spec_creator.rb` / `spec_source_creator.rb` 负责生成二进制 podspec。

## 关键约定与易踩坑点

- **产物路径固定在 `/private/var/tmp/imy_release/`**（见 `config_builder.rb#root_dir`）。这是刻意为之：`pod bin code` 源码调试用 `ln -s` 建软链，指向用户目录路径可能因权限失败，放到 `/private/var/tmp` 可规避（见近期 commit）。改路径策略前先理解这个约束。
- **多设备源码调试**：`code.rb#link` 会 `dwarfdump` 出打包机上的编译路径再在本机重建，所以打包路径的一致性很重要。
- **`--all-make`** 会连带把所有「缺失二进制」的依赖组件一起编译，耗时大，注意白名单（`BinArchive.json`）和 git 忽略列表能过滤掉不该打的组件。
- 命令类里 `--help` 在 `validate!` 阶段处理，`bin.rb` 注释指出这会导致原生 `--help` 失效，属已知问题。
- 中文注释里 `by slj` / `注释by slj` 是原作者标注的关键改动点，改 native 层时值得先读这些注释理解意图。
