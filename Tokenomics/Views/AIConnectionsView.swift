import SwiftUI

/// Settings sub-screen showing all providers with reorder + show/hide
struct AIConnectionsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var geminiPlan: GeminiPlan = SettingsService.geminiPlan ?? .free
    @State private var showingPATEntry = false
    @State private var patText = ""
    @State private var draggedRow: ProviderId?
    @State private var liftedRow: ProviderId?
    @State private var dropTargetIndex: Int?
    @State private var rowFrames: [ProviderId: CGRect] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: { viewModel.showAIConnections = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Settings")
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                    .padding(.trailing, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Text("Providers")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()

                // Invisible balance for centering
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Settings")
                }
                .font(.caption)
                .hidden()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            VStack(spacing: 0) {
                let ordered = viewModel.orderedProviders

                ForEach(Array(ordered.enumerated()), id: \.element) { index, provider in
                    connectionRow(for: provider, isLast: index == ordered.count - 1)
                }

                // Hint text
                VStack(spacing: 0) {
                    Spacer().frame(height: 16)
                    Text("Cmd+drag to reorder. Tap the eye to show or hide. Hidden providers still update in the background.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .coordinateSpace(name: "providerList")
            .onPreferenceChange(RowFramePreference.self) { rowFrames = $0 }
            .animation(.easeInOut(duration: 0.2), value: viewModel.orderedProviders)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func connectionRow(for provider: ProviderId, isLast: Bool = false) -> some View {
        let state = viewModel.providerStates[provider]
        let connection = state?.connection ?? .notInstalled
        let isConnected = connection.isConnected
        let isPinned = viewModel.isPinned(provider)
        let isHidden = viewModel.isHidden(provider)

        HStack(spacing: 8) {

            // Provider icon — acts as pin toggle for connected providers
            Button(action: {
                if isConnected {
                    viewModel.togglePin(for: provider)
                }
            }) {
                Text(provider.shortLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                    .background(iconBackground(connected: isConnected, pinned: isPinned))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(iconForeground(connected: isConnected, pinned: isPinned))
                    .opacity(isHidden ? 0.4 : (connection == .notInstalled ? 0.3 : 1))
            }
            .buttonStyle(.plain)
            .disabled(!isConnected)

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isHidden ? .secondary : (connection == .notInstalled ? .secondary : .primary))

                Text(connection.statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor(connection))

                if provider == .gemini && isConnected {
                    HStack(spacing: 2) {
                        ForEach(GeminiPlan.allCases, id: \.self) { plan in
                            let isActive = geminiPlan == plan
                            Button(action: {
                                geminiPlan = plan
                                SettingsService.geminiPlan = plan
                                viewModel.refresh()
                            }) {
                                Text(plan.displayLabel)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                    .background(isActive ? Color.white.opacity(0.1) : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    .foregroundStyle(isActive ? .primary : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .padding(.top, 4)
                }
            }

            Spacer()

            // Visibility toggle for connected providers
            if isConnected {
                Button(action: { viewModel.toggleVisibility(for: provider) }) {
                    Image(systemName: isHidden ? "eye.slash" : "eye")
                        .font(.caption)
                        .foregroundStyle(isHidden ? .tertiary : .secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isHidden ? "Show in tabs" : "Hide from tabs")
            }

            // Action buttons for non-connected states
            actionButton(for: provider, connection: connection)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 0.5)
            }
        }
        .opacity(isHidden ? 0.7 : 1)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: RowFramePreference.self,
                    value: [provider: geo.frame(in: .named("providerList"))]
                )
            }
        )
        .padding(.vertical, liftedRow == provider ? 2 : 0)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(liftedRow == provider ? Color.white.opacity(0.06) : .clear)
                .animation(.easeInOut(duration: 0.15), value: liftedRow)
        )
        .shadow(
            color: .black.opacity(liftedRow == provider ? 0.25 : 0),
            radius: liftedRow == provider ? 6 : 0,
            x: 0,
            y: liftedRow == provider ? 2 : 0
        )
        .zIndex(liftedRow == provider ? 1 : 0)
        .gesture(
            // Cmd+drag to reorder — uses .gesture (not overlay) so buttons remain tappable
            DragGesture(minimumDistance: 5, coordinateSpace: .named("providerList"))
                .modifiers(.command)
                .onChanged { value in
                    if draggedRow == nil {
                        draggedRow = provider
                        withAnimation(.easeInOut(duration: 0.15)) {
                            liftedRow = provider
                        }
                    }

                    let currentY = value.location.y
                    let ordered = viewModel.orderedProviders

                    guard let dragged = draggedRow,
                          let sourceIndex = ordered.firstIndex(of: dragged) else { return }

                    var targetIndex: Int?
                    for (idx, id) in ordered.enumerated() {
                        guard idx != sourceIndex,
                              let frame = rowFrames[id] else { continue }
                        if idx > sourceIndex && currentY > frame.midY {
                            targetIndex = idx
                        } else if idx < sourceIndex && currentY < frame.midY {
                            targetIndex = targetIndex ?? idx
                        }
                    }

                    guard let target = targetIndex, target != sourceIndex else { return }

                    viewModel.moveProvider(dragged, toIndex: target)
                }
                .onEnded { _ in
                    draggedRow = nil
                    withAnimation(.easeInOut(duration: 0.15)) {
                        liftedRow = nil
                        dropTargetIndex = nil
                    }
                }
        )
        .sheet(isPresented: $showingPATEntry) {
            patEntrySheet
        }
    }

    @ViewBuilder
    private func actionButton(for provider: ProviderId, connection: ProviderConnectionState) -> some View {
        switch connection {
        case .notInstalled:
            if provider.usesPATAuth {
                smallActionButton("Connect") { showingPATEntry = true }
                    .help("Enter a GitHub Personal Access Token")
            } else {
                smallActionButton("Install") { provider.openInstallInTerminal() }
                    .help("Opens Terminal to install \(provider.displayName)")
            }
        case .installedNoAuth:
            if provider.usesPATAuth {
                smallActionButton("Connect") { showingPATEntry = true }
                    .help("Enter a GitHub Personal Access Token")
            } else {
                smallActionButton("Sign In") { provider.openLoginInTerminal() }
                    .help("Opens Terminal to sign in")
            }
        case .authExpired:
            if provider.usesPATAuth {
                smallActionButton("Reconnect") { showingPATEntry = true }
                    .help("Enter a new GitHub Personal Access Token")
            } else {
                smallActionButton("Fix") { provider.openLoginInTerminal() }
                    .help("Opens Terminal to reconnect")
            }
        default:
            if provider == .copilot && connection.isConnected {
                smallActionButton("Disconnect") {
                    CopilotKeychainService.deletePAT()
                    viewModel.redetectProviders()
                }
            } else {
                EmptyView()
            }
        }
    }

    private func smallActionButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drop Indicator

    @ViewBuilder
    private func dropIndicator(visible: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(height: visible ? 2 : 0)
            .padding(.horizontal, 4)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: visible)
    }

    // MARK: - Icon Styling

    private func iconBackground(connected: Bool, pinned: Bool) -> Color {
        if connected && pinned {
            return Color(nsColor: .quaternaryLabelColor)
        }
        return .clear
    }

    private func iconForeground(connected: Bool, pinned: Bool) -> Color {
        if connected && pinned {
            return .primary
        }
        return .secondary
    }

    private func statusColor(_ connection: ProviderConnectionState) -> Color {
        switch connection {
        case .connected: return .green
        case .authExpired: return .orange
        default: return .secondary
        }
    }

    // MARK: - PAT Entry Sheet

    private var patEntrySheet: some View {
        VStack(spacing: 16) {
            Text("Connect GitHub Copilot")
                .font(.headline)

            Text("Enter a fine-grained Personal Access Token with **Plan (read)** permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("ghp_...", text: $patText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            HStack {
                Button("Create Token") {
                    if let url = URL(string: "https://github.com/settings/personal-access-tokens/new") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    patText = ""
                    showingPATEntry = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Connect") {
                    let trimmed = patText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    CopilotKeychainService.savePAT(trimmed)
                    patText = ""
                    showingPATEntry = false
                    viewModel.redetectProviders()
                    viewModel.refresh()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(patText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - Preference Key for Row Geometry

private struct RowFramePreference: PreferenceKey {
    static var defaultValue: [ProviderId: CGRect] = [:]
    static func reduce(value: inout [ProviderId: CGRect], nextValue: () -> [ProviderId: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
