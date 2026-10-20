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

    public static func publish(
        podspecURL: URL,
        environment: BinEnvironment,
        configuration: BuildConfiguration,
        codeDependencies: Bool = false,
        keepIntermediates: Bool = false,
        dryRun: Bool = false
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
        if dryRun {
            arguments.append("--dry-run")
        }
        return CommandSpec(
            executableName: "pod",
            arguments: arguments,
            title: dryRun ? "发布预检（dry-run）" : "发布组件",
            mutatesProject: false,
            taskKind: .publish
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
            title: "连接调试源码",
            mutatesProject: true,
            taskKind: .attachSource
        )
    }
}
