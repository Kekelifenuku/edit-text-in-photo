import Observation
import RevenueCat
import RevenueCatUI
import SwiftUI

@MainActor
@Observable
final class RevenueCatAccess {
    static let shared = RevenueCatAccess()
    static let proEntitlementID = "pro"

    // RevenueCat iOS public SDK keys are safe to ship in the app binary.
    private static let apiKey = "appl_fJEurATwcWMKvTcuCcBxzDRSoXy"

    private(set) var isPro = false
    private(set) var isConfigured = false
    var showProPaywall = false
    var configurationMessage: String?

    private var isChecking = false
    private var pendingChecks: [(Bool?) -> Void] = []

    private init() {}

    func configure() {
        guard !isConfigured else {
            refreshEntitlement()
            return
        }

        Purchases.configure(withAPIKey: Self.apiKey)
        isConfigured = true
        refreshEntitlement()
    }

    func requestProAccess() {
        guard isConfigured else {
            showProPaywall = true
            return
        }

        refreshEntitlement { [weak self] unlocked in
            guard let self, let unlocked else { return }
            if !unlocked {
                self.showProPaywall = true
            }
        }
    }

    func refreshEntitlement(completion: ((Bool?) -> Void)? = nil) {
        guard isConfigured else {
            completion?(nil)
            return
        }

        if let completion {
            pendingChecks.append(completion)
        }
        guard !isChecking else { return }
        isChecking = true

        Purchases.shared.getCustomerInfo { [weak self] customerInfo, error in
            Task { @MainActor in
                guard let self else { return }
                self.isChecking = false

                let unlocked: Bool?
                if let customerInfo, error == nil {
                    let hasPro = customerInfo.entitlements.active[
                        Self.proEntitlementID
                    ]?.isActive == true
                    self.isPro = hasPro
                    unlocked = hasPro
                } else {
                    // Keep the last known entitlement during transient store or network errors.
                    // A failed lookup must not revoke access or send an existing subscriber to
                    // the purchase paywall.
                    unlocked = nil
                }

                let checks = self.pendingChecks
                self.pendingChecks.removeAll()
                checks.forEach { $0(unlocked) }
            }
        }
    }

    func handlePaywallCompletion(_ customerInfo: CustomerInfo) {
        let unlocked = customerInfo.entitlements.active[
            Self.proEntitlementID
        ]?.isActive == true
        isPro = unlocked
        if unlocked {
            showProPaywall = false
        }
    }
}

struct RevenueCatProPaywall: View {
    @Environment(RevenueCatAccess.self) private var access

    var body: some View {
        Group {
            if access.isConfigured {
                PaywallView()
                    .onPurchaseCompleted { customerInfo in
                        access.handlePaywallCompletion(customerInfo)
                    }
                    .onRestoreCompleted { customerInfo in
                        access.handlePaywallCompletion(customerInfo)
                    }
            } else {
                ContentUnavailableView(
                    "Retouch Pro is locked",
                    systemImage: "lock.circle",
                    description: Text(access.configurationMessage ?? "RevenueCat is not configured.")
                )
            }
        }
        .onAppear { access.refreshEntitlement() }
        .onDisappear { access.refreshEntitlement() }
    }
}
