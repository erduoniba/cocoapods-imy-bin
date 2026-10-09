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

        let excludedNames: Set<String> = [".git", ".build", "Pods", "DerivedData"]
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .nameKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: options
        ) { _, _ in true }

        var podspecs: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true, excludedNames.contains(url.lastPathComponent) {
                enumerator?.skipDescendants()
                continue
            }
            if values?.isRegularFile == true, url.pathExtension == "podspec" {
                podspecs.append(url)
            }
        }

        podspecs.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return ProjectSnapshot(
            rootURL: rootURL,
            podspecURLs: podspecs,
            hasPodfile: exists("Podfile", in: rootURL),
            hasLockfile: exists("Podfile.lock", in: rootURL),
            hasArchiveConfiguration: exists("BinArchive.json", in: rootURL)
        )
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
