import SwiftUI

/// Plan selection view shown when Gemini is connected but no plan is stored,
/// or when the user taps the plan badge to change their plan.
struct GeminiPlanSetupView: View {
    let currentPlan: GeminiPlan?
    let onConfirm: (GeminiPlan) -> Void
    var onCancel: (() -> Void)?

    @State private var selectedPlan: GeminiPlan

    private var isEditing: Bool { currentPlan != nil }

    init(currentPlan: GeminiPlan?, onConfirm: @escaping (GeminiPlan) -> Void, onCancel: (() -> Void)? = nil) {
        self.currentPlan = currentPlan
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._selectedPlan = State(initialValue: currentPlan ?? .free)
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(isEditing ? "Change Gemini plan" : "Choose your Gemini plan")
                .font(.caption)
                .fontWeight(.semibold)

            Text("Tokenomics uses your plan to calculate daily limits.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Picker("Plan", selection: $selectedPlan) {
                ForEach(GeminiPlan.allCases, id: \.self) { plan in
                    Text(plan.displayLabel).tag(plan)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)

            Text(selectedPlan.limitSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .animation(.none, value: selectedPlan)

            Button(isEditing ? "Update" : "Start Tracking") {
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
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}

#Preview("First Time") {
    GeminiPlanSetupView(currentPlan: nil, onConfirm: { _ in })
}

#Preview("Editing") {
    GeminiPlanSetupView(currentPlan: .free, onConfirm: { _ in }, onCancel: {})
}
