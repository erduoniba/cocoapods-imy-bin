# 开发与测试

## 环境准备

开发必须在 macOS 上进行，并安装 Xcode、Command Line Tools、Ruby 和 Bundler。不要使用 macOS 系统 Ruby 作为长期开发环境；建议用 RVM、rbenv 或 asdf 固定 Ruby 3.1.2，并确保所有命令来自同一环境：

```bash
ruby -v
which ruby
which bundle
which pod
head -n 1 "$(which pod)"
xcodebuild -version
```

当前仓库可复现起点为 CocoaPods 1.15.2、Xcodeproj 1.25.0 和 `cocoapods-generate` 2.2.5。它是建议验证基线，不代表对新版本的永久限制。

## 安装依赖

```bash
cd cocoapods-imy-bin
bundle install
bundle check
```

当前 `Gemfile` 设置了 `SKIP_UNRELEASED_VERSIONS = true`，所以 `cp_gem` 会从 RubyGems 解析 `cocoapods-imy-bin`，不会自动引用当前目录。开发 fork 时应显式使用本地 path，并固定要支持的 CocoaPods 版本，例如：

```ruby
gem 'cocoapods', '1.15.2'
gem 'cocoapods-imy-bin', path: '.'
```

只有准备正式调整依赖策略时才提交该改动。否则需要确认测试加载的是 `lib/` 下的本地代码，而不是公开 gem。

## 自动化检查

```bash
# 检查全部 Ruby 文件语法
find lib spec -name '*.rb' -print0 | xargs -0 -n1 ruby -c

# 运行全部 Bacon 测试；也是默认 Rake task
bundle exec rake specs

# 运行单个测试文件
bundle exec bacon spec/command/bin_spec.rb

# 验证 gem 可打包
gem build cocoapods-imy-bin.gemspec
```

测试框架是 Bacon、Mocha 和 `mocha-on-bacon`，不是 RSpec。测试文件命名为 `*_spec.rb`，使用 `describe`/`it`。当前只有一个命令注册测试，测试通过不能证明 archive、resolver 或 upload 可用。

macOS 客户端使用 Swift Package Manager 和 Swift Testing：

```bash
cd apps/IMYBinManager
swift build
swift test
./Scripts/package_app.sh
```

`binary-server/` 当前没有有效的测试脚本；`npm test` 不能作为验收。修改服务端前应先为路由补集成测试，并使用临时 MongoDB 与临时制品目录，避免测试污染真实数据。

## 最小冒烟测试

依赖安装后，先验证本地插件可加载：

```bash
bundle exec ruby -Ilib -e \
  "require 'cocoapods_plugin'; puts Pod::Command.parse(%w[bin]).class"
```

然后在一次性测试组件中依次验证：

1. `pod bin init` 能生成三套配置，源码源和二进制源可读取；
2. `use_binaries!` 命中已有二进制，白名单组件仍使用源码；
3. 二进制版本缺失时自动回退源码；
4. `pod bin archive Example.podspec --no-clean` 产生可链接的制品；
5. Objective-C、Swift、含 subspec、含资源的组件分别通过真机与模拟器编译；
6. 在隔离测试仓库中执行 `auto`，验证上传、二进制 spec 和回滚方式；
7. `pod bin code` 能在另一台机器上重建 DWARF 源码路径。

不要用生产私有源执行首次 `auto` 验证。

## 修改原则

- Ruby 使用两空格缩进、snake_case 方法/文件名和 CamelCase 类名；避免顺带格式化旧代码。
- 修改 `native/` 时，先打开目标 CocoaPods 版本的同名原始类，比较方法参数、返回值和实例变量。
- 修改 resolver 时覆盖三类用例：二进制命中、二进制缺失回退、源码白名单。
- 修改 podspec 转换时覆盖 subspec、resource bundle、vendored framework/library 和 modular headers。
- 外部命令优先改为 `Open3.capture3` 或参数数组形式，避免路径空格及 shell 注入问题。

## 版本与发布

版本常量位于 `lib/cocoapods-imy-bin/gem_version.rb`。当前源码为 `0.3.1.2`，但 `Gemfile.lock` 和 RubyGems 最新包为 `0.3.1.21`；发布前必须先统一版本来源。

发布检查应至少包括：完整测试、真实组件 archive、生成 gem 内容检查、CHANGELOG、内部安装验证，以及确认不会把私有 URL、凭据或构建产物打入 gem。`gem build` 成功后再按团队权限流程发布，文档不默认授权执行 `gem push`。
