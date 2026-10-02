// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Isle",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "IsleCore"),
        .executableTarget(name: "Isle", dependencies: ["IsleCore"]),
        .testTarget(name: "IsleCoreTests", dependencies: ["IsleCore"]),
    ],
    swiftLanguageModes: [.v5]
)
