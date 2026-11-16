// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tabSS",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TabssCore"),
        .executableTarget(name: "tabSS", dependencies: ["TabssCore"]),
        .testTarget(name: "TabssCoreTests", dependencies: ["TabssCore"]),
    ]
)
