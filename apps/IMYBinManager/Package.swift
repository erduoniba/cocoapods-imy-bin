// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "IMYBinManager",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "IMYBinManager", targets: ["IMYBinManager"]),
    ],
    targets: [
        .target(name: "IMYBinCore"),
        .executableTarget(
            name: "IMYBinManager",
            dependencies: ["IMYBinCore"]
        ),
        .testTarget(
            name: "IMYBinCoreTests",
            dependencies: ["IMYBinCore"]
        ),
    ]
)
