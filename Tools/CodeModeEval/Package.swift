// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CodeModeEvalTool",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .executable(
            name: "codemode-eval",
            targets: ["CodeModeEvalCLI"]
        ),
    ],
    dependencies: [
        .package(name: "codemode-ios", path: "../.."),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "CodeModeEvalCLI",
            dependencies: [
                .product(name: "CodeMode", package: "codemode-ios"),
                .product(name: "CodeModeEvaluation", package: "codemode-ios"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            exclude: ["LLM.swift"]
        ),
    ]
)
