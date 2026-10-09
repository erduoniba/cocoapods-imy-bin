# Repository Guidelines

## Project Structure & Module Organization

The repository root contains user-facing documentation (`README.md`, `使用教程.md`), screenshots in `img/`, and demos in `演示视频/`. The actual Ruby gem lives in `cocoapods-imy-bin/`; run development commands from that directory. Production code is under `lib/cocoapods-imy-bin/`: `command/bin/` defines `pod bin` subcommands, `helpers/` handles building and uploading, `config/` manages plugin settings, and `native/` contains CocoaPods compatibility patches. Tests live in `spec/`, mirroring command behavior. Gem metadata and the version are in `cocoapods-imy-bin.gemspec` and `lib/cocoapods-imy-bin/gem_version.rb`.

## Build, Test, and Development Commands

```bash
cd cocoapods-imy-bin
bundle install
bundle exec rake specs
bundle exec bacon spec/command/bin_spec.rb
gem build cocoapods-imy-bin.gemspec
```

`bundle install` installs development dependencies. `rake specs` is also the default Rake task and runs all shuffled `*_spec.rb` files. Invoke Bacon directly for a focused test, and use `gem build` to verify packaging. CocoaPods and Xcode-dependent workflows require macOS and a usable iOS toolchain.

## Coding Style & Naming Conventions

Follow the existing Ruby style: two-space indentation, snake_case methods and files, CamelCase classes/modules, and predicate names ending in `?`. Keep command classes small and place reusable build or spec logic in `helpers/`. Preserve compatibility branches based on `Pod.match_version?`; native patches support multiple CocoaPods releases and should not assume only the newest API. No formatter or linter is configured, so match nearby code and avoid unrelated reformatting.

## Testing Guidelines

Tests use Bacon with `mocha-on-bacon`, not RSpec. Name files `*_spec.rb`, group behavior with `describe`, and write focused `it` examples. Add regression coverage for command parsing, configuration, or patched CocoaPods behavior when changing those areas. Run the full suite before submitting changes.

## Commit & Pull Request Guidelines

Recent history uses concise, imperative Chinese summaries, sometimes prefixed by a scope such as `fix:` or `docs:`. Keep each commit focused; examples include `fix: 保留 podspec subspecs` and `docs: 更新使用说明`. Pull requests should explain the problem, implementation, tested CocoaPods/Xcode versions, and commands run. Link related issues and include logs or screenshots when CLI output or user-facing behavior changes.

## Configuration & Safety Notes

Do not commit private spec-repository URLs, upload credentials, or generated build artifacts. Treat `BinArchive.json` and paths below `/private/var/tmp/imy_release/` as behavior-sensitive: path changes can break archive generation and source-debug symlinks.
