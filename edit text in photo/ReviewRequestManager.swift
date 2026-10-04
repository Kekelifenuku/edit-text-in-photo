import Foundation

/// Persists review-request eligibility for the app and keeps the cadence rules out of view code.
@MainActor
final class ReviewRequestManager {
    struct PresentationContext {
        var appIsActive: Bool
        var onboardingIsPresented: Bool
        var paywallIsPresented: Bool
        var purchaseFlowIsPresented: Bool
        var errorIsPresented: Bool
        var anotherModalIsPresented: Bool

        static let unobstructed = PresentationContext(
            appIsActive: true,
            onboardingIsPresented: false,
            paywallIsPresented: false,
            purchaseFlowIsPresented: false,
            errorIsPresented: false,
            anotherModalIsPresented: false
        )
    }

    static let shared = ReviewRequestManager()
    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private enum Key {
        static let successfulActions = "review.successfulActionsSinceRequest"
        static let lastRequestDate = "review.lastRequestDate"
        static let requestedVersion = "review.requestedVersion"
    }

    private let defaults: UserDefaults
    private let requiredSuccessfulActions = 3
    private let minimumRequestInterval: TimeInterval = 30 * 24 * 60 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Count only completed product actions, never attempts or actions that returned an error.
    @discardableResult
    func recordSuccessfulAction() -> Int {
        let nextCount = min(requiredSuccessfulActions, defaults.integer(forKey: Key.successfulActions) + 1)
        defaults.set(nextCount, forKey: Key.successfulActions)
        return nextCount
    }

    /// Records a user-requested rating without applying the automatic prompt's eligibility gates.
    /// The automatic system will then wait 30 days and avoid asking again in the same version.
    func recordExplicitReviewRequest(at date: Date = .now, appVersion: String) {
        saveRequest(at: date, appVersion: appVersion)
    }

    /// Atomically claims a review request if every app and cadence condition is satisfied.
    /// State is saved before invoking StoreKit so a no-op system request cannot cause repeated asks.
    @discardableResult
    func claimReviewRequestIfEligible(
        at date: Date = .now,
        appVersion: String,
        presentation: PresentationContext
    ) -> Bool {
        guard presentation.appIsActive,
              !presentation.onboardingIsPresented,
              !presentation.paywallIsPresented,
              !presentation.purchaseFlowIsPresented,
              !presentation.errorIsPresented,
              !presentation.anotherModalIsPresented,
              defaults.integer(forKey: Key.successfulActions) >= requiredSuccessfulActions,
              defaults.string(forKey: Key.requestedVersion) != appVersion else {
            return false
        }

        if let lastRequestDate = defaults.object(forKey: Key.lastRequestDate) as? Date,
           date.timeIntervalSince(lastRequestDate) < minimumRequestInterval {
            return false
        }

        saveRequest(at: date, appVersion: appVersion)
        return true
    }

    private func saveRequest(at date: Date, appVersion: String) {
        defaults.set(date, forKey: Key.lastRequestDate)
        defaults.set(appVersion, forKey: Key.requestedVersion)
        defaults.set(0, forKey: Key.successfulActions)
    }
}
