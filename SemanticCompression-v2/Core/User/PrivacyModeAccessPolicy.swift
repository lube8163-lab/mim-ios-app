import Foundation

// Internal feature-gating hook for future paid plans.
// Keep UI behavior unchanged unless plan rules are updated.
enum PrivacyModeAccessPolicy {
    static func canUse(mode: PrivacyMode) -> Bool {
        !futureRestrictedModes.contains(mode)
    }

    // Reserved for future monetization rollout (e.g., [.l3]).
    private static let futureRestrictedModes: Set<PrivacyMode> = []
}
