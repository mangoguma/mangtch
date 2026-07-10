//
//  drop.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import Foundation
import SwiftUI


public class BoringAnimations {
    @Published var notchStyle: Style = .notch
    
    init() {
        self.notchStyle = .notch
    }
    
    var animation: Animation {
        if #available(macOS 14.0, *), notchStyle == .notch {
            Animation.spring(.bouncy(duration: 0.4))
        } else {
            Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)
        }
    }
    
    // TODO: Move all animations to this file

}

extension Animation {
    /// Panel expand morph. Ease-out spring: full velocity at touch-down,
    /// settle at the end — easeInOut's slow start read as input lag.
    /// Damping stays ≥0.9 because the NSPanel envelope has only a small
    /// width slack (see BoringNotchWindow.resizeWindow); a bouncier spring
    /// would overshoot past the window edge and clip flat.
    static let openMorph = Animation.spring(response: 0.42, dampingFraction: 0.92)

    /// Panel collapse morph. Snappier than open — the system is getting
    /// out of the user's way, not presenting content. Undershoot on close
    /// can't clip (the envelope never shrinks), so damping can sit lower.
    static let closeMorph = Animation.spring(response: 0.30, dampingFraction: 0.9)
}
