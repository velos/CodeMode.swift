// swift-tools-version: 6.1
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "CodeModeAuthoring",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .library(
            name: "CodeModeAuthoring",
            targets: ["CodeModeAuthoring"]
        ),
    ],
    dependencies: [
        .package(name: "codemode-ios", path: "../.."),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "601.0.1"),
    ],
    targets: [
        .target(
            name: "CodeModeAuthoring",
            dependencies: [
                .product(name: "CodeMode", package: "codemode-ios"),
                "CodeModeMacros",
            ]
        ),
        .macro(
            name: "CodeModeMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "CodeModeAuthoringTests",
            dependencies: [
                "CodeModeAuthoring",
                "CodeModeMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
