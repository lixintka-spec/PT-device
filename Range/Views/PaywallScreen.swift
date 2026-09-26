import SwiftUI
import RevenueCat
import RevenueCatUI

/// RevenueCat paywall when a key is configured (remote-configurable, A/B-testable);
/// a native demo paywall with the same plans otherwise.
struct PaywallScreen: View {
    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if store.isConfigured, let offering = store.offering {
                PaywallView(offering: offering, displayCloseButton: true)
                    .onPurchaseCompleted { info in
                        store.apply(info)
                        dismiss()
                    }
                    .onRestoreCompleted { info in
                        store.apply(info)
                        if store.isClinicUnlocked { dismiss() }
                    }
            } else if store.isConfigured {
                PaywallView(displayCloseButton: true)
                    .onPurchaseCompleted { info in
                        store.apply(info)
                        dismiss()
                    }
            } else {
                DemoPaywall()
            }
        }
        .task { await store.refresh() }
    }
}

private struct DemoPaywall: View {
    @Environment(ProStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var annual = true

    var body: some View {
        NavigationStack {
            ZStack {
                RangeTheme.backdrop
                ScrollView {
                    VStack(spacing: 22) {
                        LimbFigure(flexion: 97, joint: .knee, arcs: [(68, RangeTheme.lilac.opacity(0.5)), (84, RangeTheme.sky.opacity(0.6)), (97, RangeTheme.amber)])
                            .frame(height: 170)
                        Text("Range Clinic").font(.largeTitle.bold())
                        Text("Remote range-of-motion monitoring for your whole caseload.")
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(RangeTheme.secondaryText)
                        VStack(spacing: 12) {
                            PlanCard(title: "Annual", price: "$468 / year", detail: "$39 per clinician per month · 14-day free trial", selected: annual)
                                .onTapGesture { annual = true }
                            PlanCard(title: "Monthly", price: "$49 / month", detail: "Per clinician · cancel anytime", selected: !annual)
                                .onTapGesture { annual = false }
                        }
                        Button {
                            Task {
                                await store.demoUnlock()
                                dismiss()
                            }
                        } label: {
                            Group {
                                if store.isWorking { ProgressView().tint(.black) } else { Text("Start 14-day free trial").font(.headline) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(RangeTheme.mint)
                        .foregroundStyle(.black)
                        Text("Demo mode — purchases are simulated. Add a RevenueCat API key in Secrets.swift to load live offerings and RevenueCat Paywalls.")
                            .font(.caption)
                            .foregroundStyle(RangeTheme.tertiaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 520)
                    .padding(28)
                    .frame(maxWidth: .infinity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                }
            }
        }
    }
}

private struct PlanCard: View {
    var title: String
    var price: String
    var detail: String
    var selected: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(RangeTheme.secondaryText)
            }
            Spacer()
            Text(price).font(.headline)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? RangeTheme.mint : RangeTheme.tertiaryText)
        }
        .padding(18)
        .background(selected ? RangeTheme.mint.opacity(0.10) : RangeTheme.panel, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? RangeTheme.mint : RangeTheme.panelStroke, lineWidth: selected ? 2 : 1))
    }
}
