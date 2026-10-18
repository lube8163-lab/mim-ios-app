// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "MimRecipeContract",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MimRecipeContract", targets: ["MimRecipeContract"])],
    targets: [
        .target(name: "MimLocalization", path: "SemanticCompression-v2/Core/User",
            exclude: ["AuthManager.swift", "AuthService.swift", "AuthTokenStore.swift", "BlockManager.swift", "BlockService.swift", "EmailAuthService.swift", "KeychainUserID.swift", "MimCopy.swift", "MimStyle.swift", "PushEnvironment.swift", "PushNotificationManager.swift", "PushNotificationService.swift", "ServerDate.swift", "UserManager.swift", "UserService.swift"],
            sources: ["AppPreferences.swift", "Localization.swift"]),
        .testTarget(name: "MimLocalizationTests", dependencies: ["MimLocalization"], path: "Tests/Localization", exclude: ["test_catalog_validation.py"]),
        .target(name: "MimRecipeContract", path: "SemanticCompression-v2/Core/Recipe",
            resources: [.copy("ContentSafetyPolicy.json")]),
        .testTarget(name: "MimRecipeContractTests", dependencies: ["MimRecipeContract"], path: "Tests/RecipeContract")
    ]
)
