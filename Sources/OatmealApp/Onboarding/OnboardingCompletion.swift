import Foundation

/// First-run completion flag for the onboarding window.
///
/// Stored in `UserDefaults` rather than in `AppPersistenceSnapshot` because:
/// 1. It is a single boolean with no lifecycle beyond "have we seen the
///    welcome window?"
/// 2. It never needs to roundtrip through snapshot coding.
/// 3. Using a dedicated defaults key keeps the primary persistence surface
///    free of first-run ephemera.
enum OnboardingCompletion {
    static let defaultsKey = "oatmeal.onboarding.completed.v1"

    @MainActor
    static var isComplete: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    @MainActor
    static func markComplete() {
        isComplete = true
    }

    @MainActor
    static func reset() {
        isComplete = false
    }
}
