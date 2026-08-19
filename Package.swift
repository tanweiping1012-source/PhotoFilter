// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoCurator",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PhotoCurator", targets: ["PhotoCurator"]),
    ],
    targets: [
        .executableTarget(name: "PhotoCurator"),
        .testTarget(name: "PhotoCuratorTests", dependencies: ["PhotoCurator"]),
    ]
)
