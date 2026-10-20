import CryptoKit
import Foundation

public struct ArtifactReport: Equatable, Sendable {
    public let componentName: String
    public let version: String?
    public let fileURL: URL
    public let fileSize: Int64
    public let formattedSize: String
    public let sha256: String
    public let createdAt: Date

    public init(
        componentName: String,
        version: String?,
        fileURL: URL,
        fileSize: Int64,
        formattedSize: String,
        sha256: String,
        createdAt: Date
    ) {
        self.componentName = componentName
        self.version = version
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.formattedSize = formattedSize
        self.sha256 = sha256
        self.createdAt = createdAt
    }
}

public enum ArtifactInspector {
    public static func inspectLatestArtifact(
        for componentName: String,
        searchDirectories: [URL] = [
            URL(fileURLWithPath: "/private/var/tmp/imy_release"),
            URL(fileURLWithPath: "/private/var/tmp/imy_release/LocalPage"),
        ]
    ) -> ArtifactReport? {
        let fm = FileManager.default
        var matches: [(url: URL, date: Date)] = []

        for dir in searchDirectories {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
                continue
            }
            for file in contents {
                let name = file.lastPathComponent
                if name.hasPrefix(componentName), name.hasSuffix(".xcframework.zip") || name.hasSuffix(".framework.zip") {
                    let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    matches.append((file, date))
                }
            }
        }

        guard let latest = matches.sorted(by: { $0.date > $1.date }).first else {
            return nil
        }

        return report(for: latest.url, componentName: componentName)
    }

    public static func report(for fileURL: URL, componentName: String) -> ArtifactReport? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        let date = (attrs[.modificationDate] as? Date) ?? Date()

        let sha256: String
        if let data = try? Data(contentsOf: fileURL) {
            let digest = SHA256.hash(data: data)
            sha256 = digest.map { String(format: "%02x", $0) }.joined()
        } else {
            sha256 = "N/A"
        }

        let baseName = fileURL.deletingPathExtension().deletingPathExtension().lastPathComponent
        let versionCandidate = baseName.hasPrefix("\(componentName)-")
            ? String(baseName.dropFirst("\(componentName)-".count))
            : nil

        return ArtifactReport(
            componentName: componentName,
            version: versionCandidate,
            fileURL: fileURL,
            fileSize: size,
            formattedSize: CacheManager.formatBytes(size),
            sha256: sha256,
            createdAt: date
        )
    }
}
