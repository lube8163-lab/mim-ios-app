import Foundation

nonisolated enum PushEnvironment: String {
    case sandbox
    case production

    /// Release builds installed by Xcode also have a development APNs entitlement.
    /// App Store builds omit this profile and use production APNs.
    static var current: PushEnvironment {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let profile = try? Data(contentsOf: url) else { return .production }
        return fromProvisioningProfile(profile)
    }

    static func fromProvisioningProfile(_ data: Data) -> PushEnvironment {
        guard let start = data.range(of: Data("<plist".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil
              ) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              entitlements["aps-environment"] as? String == "development" else { return .production }
        return .sandbox
    }
}
