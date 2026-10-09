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
