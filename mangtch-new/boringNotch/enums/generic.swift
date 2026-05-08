//
//  generic.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Foundation
import Defaults

public enum Style {
    case notch
    case floating
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    /// No cursor on or near the notch — wings sit at compact width with no
    /// hover affordances visible.
    case closed
    /// Cursor entered the wing/notch hover zone but hasn't dwelled on the
    /// notch body long enough to commit to expand. Wings stay at compact
    /// width; widgets reveal hover-only controls (transport, KBO toggles).
    /// Panel does **not** open from this state — only `case .open` does.
    case hovering
    /// Panel is fully expanded — full canvas width, expanded widget body
    /// rendered. Reached only via dwell on the notch body itself, never
    /// from dwell on a wing (the user is reaching for a wing control).
    case open
}

public enum NotchViews {
    case home
    case shelf
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum MirrorShapeEnum: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
}
