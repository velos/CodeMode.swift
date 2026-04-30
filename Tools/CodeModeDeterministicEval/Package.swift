// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CodeModeDeterministicEvalTool",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "codemode-deterministic-eval",
            targets: ["CodeModeDeterministicEvalCLI"]
        ),
    ],
    dependencies: [
        .package(name: "codemode-ios", path: "../.."),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "CodeModeDeterministicEvalCLI",
            dependencies: [
                .product(name: "CodeModeEvaluation", package: "codemode-ios"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
