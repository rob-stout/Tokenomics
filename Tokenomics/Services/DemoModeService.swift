import Foundation

/// Namespace for the demo-mode UserDefaults key.
///
/// The actual toggle lives on `UsageViewModel.demoModeEnabled`, but we isolate
/// the key constant here so the test target and DebugMenuView can reference it
/// without importing the full view model.
enum DemoModeService {
    /// UserDefaults key backing `UsageViewModel.demoModeEnabled`.
    static let userDefaultsKey = "tokenomics.demoMode"
}
