import Foundation

public struct ModuleScaffoldOptions: Equatable, Sendable {
    public var name: String
    public var isStaticFramework: Bool
    public var deploymentTarget: String
    public var author: String
    public var summary: String

    public init(
        name: String,
        isStaticFramework: Bool = true,
        deploymentTarget: String = "15.0",
        author: String = NSFullUserName(),
        summary: String = "A modular CocoaPods component built for XCFramework distribution."
    ) {
        self.name = name
        self.isStaticFramework = isStaticFramework
        self.deploymentTarget = deploymentTarget
        self.author = author
        self.summary = summary
    }
}

public enum ModuleScaffoldGenerator {
    @discardableResult
    public static func generate(
        options: ModuleScaffoldOptions,
        at destinationParentURL: URL
    ) throws -> URL {
        let name = options.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.range(of: #"^[A-Za-z][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            throw ScaffoldError.invalidModuleName(options.name)
        }

        let fm = FileManager.default
        let componentDir = destinationParentURL.appendingPathComponent(name, isDirectory: true)
        if fm.fileExists(atPath: componentDir.path) {
            throw ScaffoldError.directoryAlreadyExists(componentDir.path)
        }

        try fm.createDirectory(at: componentDir, withIntermediateDirectories: true)

        // 1. Classes/<Name>.swift
        let classesDir = componentDir.appendingPathComponent("Classes", isDirectory: true)
        try fm.createDirectory(at: classesDir, withIntermediateDirectories: true)
        let sourceFile = classesDir.appendingPathComponent("\(name).swift")
        let sourceContent = """
        import Foundation

        public struct \(name) {
            public static let version = "0.1.0"

            public init() {}

            public func hello() -> String {
                "Hello from \\(\(name).self)!"
            }
        }
        """
        try (sourceContent + "\n").write(to: sourceFile, atomically: true, encoding: .utf8)

        // 2. <Name>.podspec
        let podspecFile = componentDir.appendingPathComponent("\(name).podspec")
        let podspecContent = """
        Pod::Spec.new do |s|
          s.name             = '\(name)'
          s.version          = '0.1.0'
          s.summary          = '\(options.summary)'
          s.homepage         = 'https://github.com/example/\(name)'
          s.license          = { :type => 'MIT', :file => 'LICENSE' }
          s.author           = { '\(options.author)' => 'dev@example.com' }
          s.source           = { :git => 'https://github.com/example/\(name).git', :tag => s.version.to_s }

          s.ios.deployment_target = '\(options.deploymentTarget)'
          s.static_framework = \(options.isStaticFramework ? "true" : "false")
          s.swift_version = '5.0'

          s.source_files = 'Classes/**/*'
          s.pod_target_xcconfig = {
            'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES'
          }
        end
        """
        try (podspecContent + "\n").write(to: podspecFile, atomically: true, encoding: .utf8)

        // 3. LICENSE
        let licenseFile = componentDir.appendingPathComponent("LICENSE")
        let licenseContent = "MIT License\n\nCopyright (c) \(Calendar.current.component(.year, from: Date())) \(options.author)\n"
        try licenseContent.write(to: licenseFile, atomically: true, encoding: .utf8)

        // 4. Example/Podfile
        let exampleDir = componentDir.appendingPathComponent("Example", isDirectory: true)
        try fm.createDirectory(at: exampleDir, withIntermediateDirectories: true)
        let podfile = exampleDir.appendingPathComponent("Podfile")
        let podfileContent = """
        use_frameworks!

        platform :ios, '\(options.deploymentTarget)'

        plugin 'cocoapods-imy-bin'
        set_configuration_env 'dev'
        use_binaries!

        target '\(name)_Example' do
          pod '\(name)', :path => '../'
          imy_bin_config_dependencies

          target '\(name)_Tests' do
            inherit! :search_paths
          end
        end
        """
        try (podfileContent + "\n").write(to: podfile, atomically: true, encoding: .utf8)

        // 5. Initialize git
        let gitProcess = Process()
        gitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        gitProcess.arguments = ["-C", componentDir.path, "init"]
        gitProcess.standardOutput = Pipe()
        gitProcess.standardError = Pipe()
        try? gitProcess.run()
        gitProcess.waitUntilExit()

        return componentDir
    }

    public enum ScaffoldError: LocalizedError {
        case invalidModuleName(String)
        case directoryAlreadyExists(String)

        public var errorDescription: String? {
            switch self {
            case .invalidModuleName(let name):
                "组件名称不合法：\(name)（必须以英文字母开头，只包含字母、数字和下划线）"
            case .directoryAlreadyExists(let path):
                "目标组件目录已存在：\(path)"
            }
        }
    }
}
