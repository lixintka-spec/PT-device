import Foundation

enum Secrets {
    /// Paste your RevenueCat public SDK key here (Project settings → API keys).
    /// A RevenueCat Test Store key (starts with "test_") works in the Simulator without App Store Connect.
    /// Leave empty to run the paywall in clearly-labeled demo mode.
    static let revenueCatAPIKey = ""

    /// Entitlement that unlocks Range Clinic (the therapist dashboard).
    static let clinicEntitlement = "clinic"
}
