import Foundation

public enum BinCommandBuilder {
    public static func install() -> CommandSpec {
        CommandSpec(
            executableName: "pod",
            arguments: ["bin", "install"],
            title: "安装依赖",
            mutatesProject: true,
            taskKind: .install
        )
    }

    public static func update() -> CommandSpec {
        CommandSpec(
            executableName: "pod",
            arguments: ["bin", "update"],
            title: "更新依赖",
            mutatesProject: true,
            taskKind: .update
        )
    }

    public static func archive(
        podspecURL: URL,
        environment: BinEnvironment,
        configuration: BuildConfiguration,
        buildMissingDependencies: Bool,
        keepIntermediates: Bool
    ) -> CommandSpec {
        var arguments = [
            "bin",
            "archive",
            podspecURL.path,
            "--env=\(environment.rawValue)",
            "--configuration=\(configuration.rawValue)",
        ]
        if buildMissingDependencies {
            arguments.append("--all-make")
        }
        if keepIntermediates {
            arguments.append("--no-clean")
        }
        return CommandSpec(
            executableName: "pod",
            arguments: arguments,
            title: "构建二进制",
            mutatesProject: false,
            taskKind: .archive
        )
    }

    public static func syncPolicy(project: String, revision: String?, server: String) -> CommandSpec {
        var arguments = ["bin", "sync", project, "--server=\(server)"]
        if let revision, !revision.isEmpty {
            arguments.append("--revision=\(revision)")
        }
        return CommandSpec(
            executableName: "pod",
            arguments: arguments,
            title: "同步工程策略",
            mutatesProject: true,
            taskKind: .custom
        )
    }

    public static func switchMode(component: String, mode: String) -> CommandSpec {
        CommandSpec(
            executableName: "pod",
            arguments: ["bin", "switch", component, mode],
            title: "切换 \(component) 为 \(mode)",
            mutatesProject: true,
            taskKind: .custom
        )
    }

    public static func switchAll(mode: String) -> CommandSpec {
        CommandSpec(
            executableName: "pod",
            arguments: ["bin", "switch", "--all", mode],
            title: "切换全部组件为 \(mode)",
            mutatesProject: true,
            taskKind: .custom
        )
    }

    public static func resetModes() -> CommandSpec {
        CommandSpec(
            executableName: "pod",
            arguments: ["bin", "switch", "--reset"],
            title: "重置组件模式覆盖",
            mutatesProject: true,
            taskKind: .custom
        )
    }

    public static func status(json: Bool = false) -> CommandSpec {
        var arguments = ["bin", "status"]
        if json {
            arguments.append("--json")
        }
        return CommandSpec(
            executableName: "pod",
            arguments: arguments,
            title: "查询组件依赖状态",
            mutatesProject: false,
            taskKind: .inspect
        )
    }

    public static func publish(
        podspecURL: URL,
        environment: BinEnvironment,
        configuration: BuildConfiguration,
        codeDependencies: Bool = false,
        keepIntermediates: Bool = false,
        skipTag: Bool = false,
        skipCodeSpec: Bool = false,
        dryRun: Bool = false,
        allowPrerelease: Bool = false,
        autoCommit: Bool = false,
        push: Bool = false
    ) -> CommandSpec {
        var arguments = [
            "bin",
            "publish",
            podspecURL.path,
            "--env=\(environment.rawValue)",
            "--configuration=\(configuration.rawValue)",
        ]
        if codeDependencies {
            arguments.append("--code-dependencies")
        }
        if keepIntermediates {
            arguments.append("--no-clean")
        }
        if skipTag {
            arguments.append("--skip-tag")
        }
        if skipCodeSpec {
            arguments.append("--skip-code-spec")
        }
        if dryRun {
            arguments.append("--dry-run")
        }
        if allowPrerelease {
            arguments.append("--allow-prerelease")
        }
        if autoCommit {
            arguments.append("--auto-commit")
        }
        if push {
            arguments.append("--push")
        }
        return CommandSpec(
            executableName: "pod",
            arguments: arguments,
            title: dryRun ? "发布预检（dry-run）" : "发布组件",
            mutatesProject: false,
            taskKind: .publish
        )
    }

    public static func gitAutoCommitAndPush(
        componentName: String,
        version: String,
        customMessage: String? = nil
    ) -> CommandSpec {
        let commitMsg = (customMessage?.isEmpty == false) ? customMessage! : "chore: release \(componentName) \(version)"
        let script = "git add -A && (git diff-index --quiet --cached HEAD 2>/dev/null || git commit -m \"\(commitMsg)\") && (git remote | grep -q \"^origin$\" && git push origin HEAD || true)"
        return CommandSpec(
            executableName: "sh",
            arguments: ["-c", script],
            title: "提交并推送代码变更 (Git commit & push)",
            mutatesProject: true,
            taskKind: .custom
        )
    }

    public static func gitTagAndPush(
        version: String
    ) -> CommandSpec {
        let script = "git tag -f \"\(version)\" && (git remote | grep -q \"^origin$\" && git push origin \"\(version)\" --force || true)"
        return CommandSpec(
            executableName: "sh",
            arguments: ["-c", script],
            title: "更新并推送 Git Tag \(version)",
            mutatesProject: true,
            taskKind: .custom
        )
    }

    public static func repoUpdate(name: String? = nil, all: Bool = false) -> CommandSpec {
        var arguments = ["bin", "repo", "update"]
        if all {
            arguments.append("--all")
        } else if let name, !name.isEmpty {
            arguments.append(name)
        }
        return CommandSpec(
            executableName: "pod",
            arguments: arguments,
            title: "更新私有 Spec 仓库",
            mutatesProject: false,
            taskKind: .inspect
        )
    }

    public static func cleanCocoaPodsCache() -> CommandSpec {
        CommandSpec(
            executableName: "pod",
            arguments: ["cache", "clean", "--all"],
            title: "清理全量 CocoaPods 缓存",
            mutatesProject: false,
            taskKind: .custom
        )
    }

    public static func testComponent(
        workspaceOrProjectURL: URL,
        scheme: String,
        destination: String? = nil
    ) -> CommandSpec {
        let isWorkspace = workspaceOrProjectURL.pathExtension == "xcworkspace"
        let flag = isWorkspace ? "-workspace" : "-project"
        let dest = (destination != nil && !destination!.isEmpty) ? destination! : resolveAvailableSimulatorDestination()
        return CommandSpec(
            executableName: "xcodebuild",
            arguments: [
                "test",
                flag,
                workspaceOrProjectURL.path,
                "-scheme",
                scheme,
                "-destination",
                dest,
            ],
            title: "运行单元测试: \(scheme)",
            mutatesProject: false,
            taskKind: .custom
        )
    }

    public static func resolveAvailableSimulatorDestination() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "available", "-j"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let devices = json["devices"] as? [String: [[String: Any]]] {
                // 1. First preference: booted iPhone simulator
                for (_, list) in devices {
                    if let booted = list.first(where: { ($0["state"] as? String) == "Booted" && (($0["name"] as? String)?.contains("iPhone") == true) }),
                       let name = booted["name"] as? String {
                        return "platform=iOS Simulator,name=\(name)"
                    }
                }
                // 2. Second preference: any available iPhone simulator
                for (_, list) in devices {
                    if let first = list.first(where: { (($0["name"] as? String)?.contains("iPhone") == true) }),
                       let name = first["name"] as? String {
                        return "platform=iOS Simulator,name=\(name)"
                    }
                }
            }
        } catch {}
        return "platform=iOS Simulator,name=iPhone 16"
    }

    public static func commitComponentVersion(
        podspecFileName: String,
        version: String
    ) -> CommandSpec {
        CommandSpec(
            executableName: "git",
            arguments: [
                "commit",
                "-m",
                "chore: 升级版本至 \(version)",
                "--",
                podspecFileName,
            ],
            title: "提交版本变更 \(version)",
            mutatesProject: true,
            taskKind: .custom
        )
    }

    public static func attachSource(component: String, sourceURL: URL? = nil) -> CommandSpec {
        var arguments = ["bin", "code", component]
        if let sourceURL {
            arguments.append("--source=\(sourceURL.path)")
        }
        return CommandSpec(
            executableName: "pod",
            arguments: arguments,
            title: "挂载 \(component) 调试源码",
            mutatesProject: true,
            taskKind: .attachSource
        )
    }

    public static func cleanAttachedSources(component: String? = nil) -> CommandSpec {
        var arguments = ["bin", "code"]
        if let component, !component.isEmpty {
            arguments.append(contentsOf: ["--clean", component])
        } else {
            arguments.append("--all-clean")
        }
        return CommandSpec(
            executableName: "pod",
            arguments: arguments,
            title: component != nil ? "断开 \(component!) 源码调试软链" : "清理全部源码调试软链",
            mutatesProject: true,
            taskKind: .attachSource
        )
    }

    public static func listAttachedSources() -> CommandSpec {
        CommandSpec(
            executableName: "pod",
            arguments: ["bin", "code", "--list"],
            title: "查询已连接的调试源码",
            mutatesProject: false,
            taskKind: .inspect
        )
    }
}
