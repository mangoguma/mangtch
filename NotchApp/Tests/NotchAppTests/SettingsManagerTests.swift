import XCTest
@testable import NotchApp

@MainActor
final class SettingsManagerTests: XCTestCase {
    func testDefaultValues() {
        let settings = SettingsManager.shared

        // Verify defaults are registered
        XCTAssertTrue(settings.animationsEnabled)
        XCTAssertTrue(settings.enableMusicPlayer)
        XCTAssertTrue(settings.enableFileShelf)
        XCTAssertTrue(settings.enableHUD)
        XCTAssertEqual(settings.fileShelfMaxItems, 3)
        XCTAssertEqual(settings.fileShelfExpirationHours, 24)
        XCTAssertEqual(settings.hudAutoHideDelay, 2.0, accuracy: 0.01)
        XCTAssertTrue(settings.showInMenuBar)
    }

    func testSettingPersistence() {
        let settings = SettingsManager.shared

        // Change a setting
        let original = settings.fileShelfMaxItems
        settings.fileShelfMaxItems = 10

        // Read it back
        XCTAssertEqual(settings.fileShelfMaxItems, 10)

        // Restore
        settings.fileShelfMaxItems = original
    }

    func testResetToDefaults() {
        let settings = SettingsManager.shared

        // Modify settings
        settings.animationsEnabled = false
        settings.fileShelfMaxItems = 99

        // Reset
        settings.resetToDefaults()

        // Verify defaults restored
        XCTAssertTrue(settings.animationsEnabled)
        XCTAssertEqual(settings.fileShelfMaxItems, 3)
    }

    func testHoverSensitivityRange() {
        let settings = SettingsManager.shared

        settings.hoverSensitivity = 0.0
        XCTAssertEqual(settings.hoverSensitivity, 0.0, accuracy: 0.01)

        settings.hoverSensitivity = 1.0
        XCTAssertEqual(settings.hoverSensitivity, 1.0, accuracy: 0.01)

        // Restore
        settings.hoverSensitivity = 0.5
    }
}
