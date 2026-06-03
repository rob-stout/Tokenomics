import SwiftUI

/// Plan selection for the consumer Gemini (gemini.google.com app) pool, shown
/// when the user taps the Gemini (app) plan badge.
///
/// Unlike `GeminiPlanSetupView` (CLI), the chosen tier is label-only — the app
/// pool's usage % comes straight from the web session, so the plan doesn't drive
/// any limit math. We surface it because the extension can't read the tier.
struct GeminiConsumerPlanSetupView: View {
    let currentPlan: GeminiConsumerPlan?
    let onConfirm: (GeminiConsumerPlan) -> Void
    var onCancel: (() -> Void)?

    @State private var selectedPlan: GeminiConsumerPlan

    private var isEditing: Bool { currentPlan != nil }

    init(currentPlan: GeminiConsumerPlan?, onConfirm: @escaping (GeminiConsumerPlan) -> Void, onCancel: (() -> Void)? = nil) {
        self.currentPlan = currentPlan
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._selectedPlan = State(initialValue: currentPlan ?? .free)
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .scaledFont(.title2)
                .foregroundStyle(.secondary)

            Text(isEditing ? "Change Gemini plan" : "Choose your Gemini plan")
                .scaledFont(.caption)
                .fontWeight(.semibold)

            Text("Names your Gemini app plan. Usage comes straight from the web — this only labels the badge.")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Picker("Plan", selection: $selectedPlan) {
                ForEach(GeminiConsumerPlan.allCases, id: \.self) { plan in
                    Text(plan.displayLabel).tag(plan)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)

            Text(selectedPlan.blurb)
                .scaledFont(.caption2)
                .foregroundStyle(.secondary)
                .animation(.none, value: selectedPlan)

            Button(isEditing ? "Update" : "Save") {
                onConfirm(selectedPlan)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 4)

            if isEditing, let onCancel {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}

#Preview("Editing") {
    GeminiConsumerPlanSetupView(currentPlan: .pro, onConfirm: { _ in }, onCancel: {})
}
