// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MimCoreAIRuntime",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [.library(name: "MimCoreAIVision", targets: ["MimCoreAIVision"])],
    dependencies: [
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.0"),
        .package(url: "https://github.com/mlc-ai/xgrammar", exact: "0.2.2")
    ],
    targets: [
        .target(name: "CoreAIShared", swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]),
        .target(name: "CoreAILanguageModels", dependencies: ["CoreAIShared", "CXGrammar",
            .product(name: "Transformers", package: "swift-transformers")],
            swiftSettings: [.define("CXGRAMMAR_IMPORT"), .enableUpcomingFeature("MemberImportVisibility"),
                            .enableExperimentalFeature("Lifetimes")],
            linkerSettings: [.linkedLibrary("c++")]),
        .target(name: "CXGrammar", dependencies: [.product(name: "XGrammar", package: "xgrammar")],
            publicHeadersPath: "include"),
        .target(name: "MimCoreAIVision", dependencies: ["CoreAILanguageModels",
            .product(name: "Transformers", package: "swift-transformers")])
    ],
    cxxLanguageStandard: .cxx17
)
