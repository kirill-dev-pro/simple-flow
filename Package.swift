// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimpleFlow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SimpleFlow", targets: ["SimpleFlow"])],
    targets: [
        .executableTarget(name: "SimpleFlow", path: "Sources/SimpleFlow"),
        .testTarget(
            name: "SimpleFlowTests",
            dependencies: ["SimpleFlow"],
            path: "Tests/SimpleFlowTests"
        )
    ]
)
