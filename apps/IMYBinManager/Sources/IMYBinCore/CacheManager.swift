import Foundation

public struct CacheCleanupReport: Equatable, Sendable {
    public let componentName: String
    public let removedPaths: [String]
    public let errors: [String]

    public init(componentName: String, removedPaths: [String], errors: [String] = []) {
        self.componentName = componentName
        self.removedPaths = removedPaths
        self.errors = errors
    }
}

public enum CacheManager {
    public static var cocoapodsCacheDirectoryURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CocoaPods", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/CocoaPods")
    }

    public static var derivedDataDirectoryURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
    }

    public static var tmpReleaseDirectoryURL: URL {
        URL(fileURLWithPath: "/private/var/tmp/imy_release", isDirectory: true)
    }

    @discardableResult
    public static func cleanComponentCache(
        componentName: String,
        projectDirectoryURL: URL? = nil
    ) -> CacheCleanupReport {
        let fm = FileManager.default
        var removed: [String] = []
        var errors: [String] = []

        let candidates: [URL] = [
            cocoapodsCacheDirectoryURL.appendingPathComponent("Pods/Release/\(componentName)"),
            cocoapodsCacheDirectoryURL.appendingPathComponent("Pods/Specs/Release/\(componentName)"),
            tmpReleaseDirectoryURL.appendingPathComponent("\(componentName)-build-temp"),
            tmpReleaseDirectoryURL.appendingPathComponent(componentName),
        ] + (projectDirectoryURL.map { [
            $0.appendingPathComponent("Pods/\(componentName)"),
            $0.appendingPathComponent("Pods/Headers/Public/\(componentName)"),
            $0.appendingPathComponent("Pods/Headers/Private/\(componentName)"),
        ] } ?? [])

        for target in candidates {
            if fm.fileExists(atPath: target.path) {
                do {
                    try fm.removeItem(at: target)
                    removed.append(target.path)
                } catch {
                    errors.append("\(target.path): \(error.localizedDescription)")
                }
            }
        }

        return CacheCleanupReport(componentName: componentName, removedPaths: removed, errors: errors)
    }

    public static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    public static func cleanDirectoryContents(at url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let items = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        for item in items {
            try fm.removeItem(at: item)
        }
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
