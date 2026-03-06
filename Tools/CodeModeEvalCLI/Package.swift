// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodeModeEvalCLI",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "codemode-eval", targets: ["CodeModeEvalCLI"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "CodeModeEvalCLI",
            dependencies: [
                .product(name: "CodeMode", package: "codemode-ios"),
            ]
        ),
    ]
)
