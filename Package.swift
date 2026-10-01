// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Safespace",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Safespace", targets: ["Safespace"]),
    ],
    targets: [
        .target(name: "SafespaceCore"),
        .executableTarget(name: "Safespace", dependencies: ["SafespaceCore"]),
        .testTarget(name: "SafespaceCoreTests", dependencies: ["SafespaceCore"]),
    ]
)
