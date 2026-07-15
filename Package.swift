// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodeAgent",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodeAgent", targets: ["CodeAgent"])
    ],
    targets: [
        .executableTarget(
            name: "CodeAgent",
            dependencies: [],
            path: "Sources/CodeAgent"
        ),
        .testTarget(
            name: "CodeAgentTests",
            dependencies: ["CodeAgent"],
            path: "Tests/CodeAgentTests"
        )
    ]
)