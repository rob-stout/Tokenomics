import XCTest
@testable import Tokenomics

// MARK: - SettingsService Tests
//
// SettingsService uses UserDefaults.standard. Tests must clean up after themselves
// to avoid cross-test contamination. Each test uses a unique key suffix or tearDown.

final class SettingsServiceTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        // Reset keys touched by these tests
        UserDefaults.standard.removeObject(forKey: "pinnedProviders")
        UserDefaults.standard.removeObject(forKey: "providerOrder")
        UserDefaults.standard.removeObject(forKey: "hiddenProviders")
        UserDefaults.standard.removeObject(forKey: "alertWindow")
        for provider in ProviderId.allCases {
            UserDefaults.standard.removeObject(forKey: "notificationConfig_\(provider.rawValue)")
        }
    }

    // MARK: - Smart Mode

    /// Empty pinned set → smart mode is active
    func testSmartMode_emptyPinnedSet_isActive() {
        SettingsService.pinnedProviders = []
        XCTAssertTrue(SettingsService.isSmartMode)
    }

    /// Any pinned provider → smart mode off
    func testSmartMode_anyPinnedProvider_isNotActive() {
        SettingsService.pinnedProviders = [.claude]
        XCTAssertFalse(SettingsService.isSmartMode)
    }

    /// Default state (no key written) → empty set → smart mode active
    func testSmartMode_defaultState_isActive() {
        UserDefaults.standard.removeObject(forKey: "pinnedProviders")
        XCTAssertTrue(SettingsService.isSmartMode)
    }

    // MARK: - Pinned Providers Persistence

    func testPinnedProviders_roundTrip() {
        let pinned: Set<ProviderId> = [.claude, .codex, .gemini]
        SettingsService.pinnedProviders = pinned
        XCTAssertEqual(SettingsService.pinnedProviders, pinned)
    }

    func testTogglePin_addsProvider() {
        SettingsService.pinnedProviders = []
        SettingsService.togglePin(for: .claude)
        XCTAssertTrue(SettingsService.pinnedProviders.contains(.claude))
    }

    func testTogglePin_removesProvider() {
        SettingsService.pinnedProviders = [.claude]
        SettingsService.togglePin(for: .claude)
        XCTAssertFalse(SettingsService.pinnedProviders.contains(.claude))
    }

    // MARK: - Provider Order

    func testProviderOrder_defaultIsEmpty() {
        UserDefaults.standard.removeObject(forKey: "providerOrder")
        XCTAssertTrue(SettingsService.providerOrder.isEmpty)
    }

    func testProviderOrder_roundTrip() {
        let order: [ProviderId] = [.gemini, .claude, .codex]
        SettingsService.providerOrder = order
        XCTAssertEqual(SettingsService.providerOrder, order)
    }

    // MARK: - Notification Config

    func testNotificationConfig_defaultValues() {
        let config = SettingsService.notificationConfig(for: .claude)
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.threshold, 80)
    }

    func testNotificationConfig_roundTrip() {
        var config = SettingsService.NotificationConfig()
        config.isEnabled = false
        config.threshold = 90
        SettingsService.setNotificationConfig(config, for: .claude)

        let loaded = SettingsService.notificationConfig(for: .claude)
        XCTAssertFalse(loaded.isEnabled)
        XCTAssertEqual(loaded.threshold, 90)
    }

    // MARK: - Alert Window

    func testAlertWindow_defaultIsShort() {
        UserDefaults.standard.removeObject(forKey: "alertWindow")
        XCTAssertEqual(SettingsService.alertWindow, .short)
    }

    func testAlertWindow_roundTrip() {
        SettingsService.alertWindow = .both
        XCTAssertEqual(SettingsService.alertWindow, .both)
    }

    // MARK: - Hidden Providers

    func testHiddenProviders_roundTrip() {
        let hidden: Set<ProviderId> = [.cursor, .copilot]
        SettingsService.hiddenProviders = hidden
        XCTAssertEqual(SettingsService.hiddenProviders, hidden)
    }
}
