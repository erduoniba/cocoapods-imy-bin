import Foundation

public struct ProjectInspector {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(_ rootURL: URL) throws -> ProjectSnapshot {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw InspectionError.notDirectory(rootURL.path)
        }

        let excludedNames: Set<String> = [
            ".git", ".build", "Pods", "DerivedData",
            "cocoapods-imy-bin-fork", "binary-server", ".imy-infra", ".imy-pods", "node_modules",
        ]
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .nameKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: options
        ) { _, _ in true }

        var podspecMap: [String: URL] = [:]
        var appDirMap: [String: URL] = [:]

        if exists("Podfile", in: rootURL) {
            let std = rootURL.standardizedFileURL
            appDirMap[std.path] = std
        }

        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true, excludedNames.contains(url.lastPathComponent) {
                enumerator?.skipDescendants()
                continue
            }
            if values?.isRegularFile == true {
                if url.pathExtension == "podspec" {
                    let std = url.standardizedFileURL
                    podspecMap[std.path] = std
                } else if url.lastPathComponent == "Podfile" {
                    let dir = url.deletingLastPathComponent().standardizedFileURL
                    appDirMap[dir.path] = dir
                }
            }
        }

        // Also discover podspecs referenced via :path in discovered Podfiles (e.g., when opening HDImyBinApp directly)
        for appDir in appDirMap.values {
            let deps = PodfileComponentInspector.inspect(from: appDir)
            for dep in deps {
                guard let localPath = dep.localPath, !localPath.isEmpty else { continue }
                let compDir = appDir.appendingPathComponent(localPath).standardizedFileURL
                if let extraSpecs = try? topLevelPodspecs(in: compDir) {
                    for spec in extraSpecs {
                        podspecMap[spec.path] = spec
                    }
                }
            }
        }

        // If opening a component directory directly, also discover sibling Host App directories that depend on it
        let componentNames = Set(podspecMap.values.map { $0.deletingPathExtension().lastPathComponent })
        if !componentNames.isEmpty {
            let parentURL = rootURL.standardizedFileURL.deletingLastPathComponent()
            if let siblings = try? fileManager.contentsOfDirectory(
                at: parentURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for sibling in siblings {
                    let stdSibling = sibling.standardizedFileURL
                    guard !excludedNames.contains(stdSibling.lastPathComponent),
                          exists("Podfile", in: stdSibling) else { continue }
                    let siblingDeps = PodfileComponentInspector.inspect(from: stdSibling)
                    if siblingDeps.contains(where: { componentNames.contains($0.name) }) {
                        appDirMap[stdSibling.path] = stdSibling
                    }
                }
            }
        }

        let stdRootPath = rootURL.standardizedFileURL.path
        let appDirectories = appDirMap.values.sorted { lhs, rhs in
            let lhsIsRoot = lhs.path == stdRootPath
            let rhsIsRoot = rhs.path == stdRootPath
            if lhsIsRoot != rhsIsRoot { return lhsIsRoot }
            let lhsIsExample = lhs.lastPathComponent.lowercased() == "example"
            let rhsIsExample = rhs.lastPathComponent.lowercased() == "example"
            if lhsIsExample != rhsIsExample { return !lhsIsExample }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }

        let podspecs = podspecMap.values.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        let hasRootPodfile = exists("Podfile", in: rootURL)
        let hasAnyPodfile = hasRootPodfile || !appDirectories.isEmpty
        let hasAnyLockfile = exists("Podfile.lock", in: rootURL)
            || appDirectories.contains(where: { exists("Podfile.lock", in: $0) })

        return ProjectSnapshot(
            rootURL: rootURL,
            podspecURLs: podspecs,
            hasPodfile: hasAnyPodfile,
            hasLockfile: hasAnyLockfile,
            hasArchiveConfiguration: exists("BinArchive.json", in: rootURL),
            appDirectories: appDirectories
        )
    }

    private func topLevelPodspecs(in directoryURL: URL) throws -> [URL] {
        let items = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return items
            .filter { $0.pathExtension == "podspec" }
            .map(\.standardizedFileURL)
    }

    private func exists(_ name: String, in rootURL: URL) -> Bool {
        fileManager.fileExists(atPath: rootURL.appendingPathComponent(name).path)
    }

    public enum InspectionError: LocalizedError, Equatable {
        case notDirectory(String)

        public var errorDescription: String? {
            switch self {
            case .notDirectory(let path): "不是有效目录：\(path)"
            }
        }
    }
}
