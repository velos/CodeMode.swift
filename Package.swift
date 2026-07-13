// swift-tools-version: 6.1
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "CodeMode",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .library(
            name: "CodeMode",
            targets: ["CodeMode"]
        ),
        .library(
            name: "CodeModeAuthoring",
            targets: ["CodeModeAuthoring"]
        ),
        .library(
            name: "CodeModeEvaluation",
            targets: ["CodeModeEvaluation"]
        ),
    ],
    dependencies: [
        // Used by the CodeModeMacros compiler plugin only; consumers get the
        // prebuilt swift-syntax libraries on current toolchains (measured cost
        // in PLAN-registration-macros.md). Keep the range wide so consumers can
        // co-resolve with other swift-syntax users (mlx-swift-lm needs >= 602);
        // the macro diagnostic tests assume the >= 602 position behavior.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"604.0.0"),
    ],
    targets: [
        .target(
            name: "CCodeModeJSC",
            linkerSettings: [
                .linkedFramework("JavaScriptCore")
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
        .target(
            name: "CodeMode",
            dependencies: ["CCodeModeJSC", "CodeModeMacros"]
        ),
        .target(
            name: "CodeModeAuthoring",
            dependencies: ["CodeMode", "CodeModeMacros"]
        ),
        .target(
            name: "CodeModeEvaluation",
            dependencies: ["CodeMode"]
        ),
        .testTarget(
            name: "CodeModeTests",
            dependencies: ["CodeMode"]
        ),
        .testTarget(
            name: "CodeModeAuthoringTests",
            dependencies: [
                "CodeModeAuthoring",
                "CodeModeMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "CodeModeEvalTests",
            dependencies: ["CodeModeEvaluation"]
        ),
    ]
)
