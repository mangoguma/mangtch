import SwiftUI

enum AnimationTokens {
    // MARK: - Panel Transitions (PRD Section 4.4)

    /// Hover: wings expand from notch
    static let expandHover = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Click: center panel drops down
    static let expandClick = Animation.spring(response: 0.35, dampingFraction: 0.8)

    /// Collapse: panel retracts
    static let collapse = Animation.spring(response: 0.25, dampingFraction: 0.9)

    // MARK: - Content Transitions

    /// Content appearing
    static let fadeIn = Animation.easeInOut(duration: 0.2)

    /// Content disappearing
    static let fadeOut = Animation.easeInOut(duration: 0.15)

    // MARK: - HUD

    /// HUD slider appears
    static let hudAppear = Animation.spring(response: 0.2, dampingFraction: 0.8)

    /// HUD slider dismisses
    static let hudDismiss = Animation.easeOut(duration: 0.3)

    // MARK: - Theme

    /// Color transition between themes
    static let colorTransition = Animation.easeInOut(duration: 0.5)

    // MARK: - Timing Constants

    /// Debounce before triggering hover state
    static let hoverDebounce: TimeInterval = 0.05

    /// Delay before collapsing after mouse exit
    static let collapseDelay: TimeInterval = 0.3

    /// HUD auto-dismiss duration
    static let hudAutoDismiss: TimeInterval = 2.0

    /// Track change notification display duration
    static let trackChangeNotificationDuration: TimeInterval = 1.5

    /// File shelf item expiration check interval
    static let expirationCheckInterval: TimeInterval = 300 // 5 minutes
}
