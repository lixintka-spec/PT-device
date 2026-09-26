import SwiftUI
import RevenueCat

/// Monetization lives in RevenueCat: offerings, purchases, entitlement checks, restore,
/// and the Customer Center. Range sells "Range Clinic" to physical-therapy practices.
@MainActor
@Observable
final class ProStore {
    private(set) var isConfigured = false
    private(set) var isClinicUnlocked = false
    private(set) var offering: Offering?
    private(set) var isWorking = false
    var lastError: String?

    /// Demo-mode unlock when no RevenueCat key is present (never ships).
    private var demoUnlocked = false

    var isDemoMode: Bool { !isConfigured }

    func configure() {
        let key = Secrets.revenueCatAPIKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !isConfigured else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: key)
        isConfigured = true
        Task { await refresh() }
        Task {
            for await info in Purchases.shared.customerInfoStream {
                apply(info)
            }
        }
    }

    func refresh() async {
        guard isConfigured else { return }
        do {
            apply(try await Purchases.shared.customerInfo())
            offering = try await Purchases.shared.offerings().current
        } catch {
            lastError = error.localizedDescription
        }
    }

    func apply(_ info: CustomerInfo) {
        isClinicUnlocked = info.entitlements[Secrets.clinicEntitlement]?.isActive == true
    }

    func purchase(_ package: Package) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled { apply(result.customerInfo) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        guard isConfigured else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            apply(try await Purchases.shared.restorePurchases())
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Demo mode only: simulates a successful subscription so the flow can be shown on stage.
    func demoUnlock() async {
        isWorking = true
        try? await Task.sleep(for: .milliseconds(900))
        demoUnlocked = true
        isClinicUnlocked = true
        isWorking = false
    }

    func demoLock() {
        demoUnlocked = false
        if !isConfigured { isClinicUnlocked = false }
    }
}
