import Foundation

public struct DependentItem: Identifiable, Equatable, Sendable {
    public enum ItemKind: String, Codable, Sendable {
        case component
        case hostApp
    }

    public let name: String
    public let kind: ItemKind
    public let locationURL: URL
    public let currentRequirement: String?

    public var id: String { "\(kind.rawValue):\(name):\(locationURL.path)" }

    public init(name: String, kind: ItemKind, locationURL: URL, currentRequirement: String? = nil) {
        self.name = name
        self.kind = kind
        self.locationURL = locationURL
        self.currentRequirement = currentRequirement
    }
}

public struct ReverseImpactReport: Equatable, Sendable {
    public let targetComponent: String
    public let dependentComponents: [DependentItem]
    public let dependentApps: [DependentItem]

    public var totalCount: Int {
        dependentComponents.count + dependentApps.count
    }

    public init(
        targetComponent: String,
        dependentComponents: [DependentItem],
        dependentApps: [DependentItem]
    ) {
        self.targetComponent = targetComponent
        self.dependentComponents = dependentComponents
        self.dependentApps = dependentApps
    }
}

public enum DependencyGraphAnalyzer {
    public static func analyzeReverseImpact(
        for targetComponent: String,
        in snapshot: ProjectSnapshot,
        podspecs: [ComponentPodspecInfo]
    ) -> ReverseImpactReport {
        let trimmedTarget = targetComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        var depComponents: [DependentItem] = []
        var depApps: [DependentItem] = []

        // 1. Scan upper-layer components whose .podspec has s.dependency targetComponent
        for spec in podspecs {
            if spec.name == trimmedTarget { continue }
            if let dep = spec.dependencies.first(where: {
                let root = $0.name.split(separator: "/").first.map(String.init) ?? $0.name
                return root == trimmedTarget
            }) {
                depComponents.append(DependentItem(
                    name: spec.name,
                    kind: .component,
                    locationURL: spec.podspecURL,
                    currentRequirement: dep.versionRequirement
                ))
            }
        }

        // 2. Scan Host Apps whose config table or Podfile has targetComponent
        for appDir in snapshot.appDirectories {
            let appName = appDir.lastPathComponent
            if let table = try? ComponentConfigTable.read(from: appDir) {
                if let entry = table.components.first(where: { $0.name == trimmedTarget && $0.enabled }) {
                    depApps.append(DependentItem(
                        name: appName,
                        kind: .hostApp,
                        locationURL: appDir,
                        currentRequirement: entry.version
                    ))
                    continue
                }
            }

            let podfileDeps = PodfileComponentInspector.inspectPodfileDeclarationsOnly(from: appDir)
            if let entry = podfileDeps.first(where: { $0.name == trimmedTarget }) {
                depApps.append(DependentItem(
                    name: appName,
                    kind: .hostApp,
                    locationURL: appDir,
                    currentRequirement: entry.declaredVersion
                ))
            }
        }

        return ReverseImpactReport(
            targetComponent: trimmedTarget,
            dependentComponents: depComponents.sorted { $0.name < $1.name },
            dependentApps: depApps.sorted { $0.name < $1.name }
        )
    }

    @discardableResult
    public static func cascadeSyncVersion(
        targetComponent: String,
        newVersion: String,
        in snapshot: ProjectSnapshot,
        podspecs: [ComponentPodspecInfo]
    ) throws -> [String] {
        let report = analyzeReverseImpact(for: targetComponent, in: snapshot, podspecs: podspecs)
        var updatedNames: [String] = []

        // 1. Update podspecs
        for item in report.dependentComponents {
            try PodspecInspector.upsertDependency(
                in: item.locationURL,
                name: targetComponent,
                versionRequirement: newVersion
            )
            updatedNames.append(item.name)
        }

        // 2. Update Host App config tables
        for item in report.dependentApps {
            let success = try ComponentConfigTable.updateComponentVersion(
                in: item.locationURL,
                workspacePodspecs: podspecs,
                component: targetComponent,
                to: newVersion
            )
            if success {
                updatedNames.append(item.name)
            }
        }

        return updatedNames
    }
}
