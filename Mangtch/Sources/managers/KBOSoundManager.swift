import AppKit
import AVFoundation

/// Plays system sounds for KBO play events. Independent of the TTS
/// ticker — both can be enabled simultaneously.
@MainActor
final class KBOSoundManager {
    static let shared = KBOSoundManager()
    private var player: AVAudioPlayer?
    private init() {}

    /// Map play events to system sound names.
    enum PlaySound: String {
        case hit = "Ping"           // 안타
        case homeRun = "Hero"       // 홈런
        case run = "Glass"          // 홈인/득점
        case strikeout = "Basso"    // 삼진
        case flyOut = "Bottle"      // 플라이/땅볼 아웃
        case walk = "Blow"          // 볼넷
        case steal = "Funk"         // 도루
        case inningChange = "Submarine"  // 공수교대
    }

    func play(_ sound: PlaySound) {
        let path = "/System/Library/Sounds/\(sound.rawValue).aiff"
        let url = URL(fileURLWithPath: path)
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = 1.5  // boost above system default
        p.prepareToPlay()
        player = p  // retain
        p.play()
    }

    /// Determine the appropriate sound for a play based on its text
    /// and importance. Returns nil for plays that shouldn't trigger sound.
    func soundForPlay(_ text: String, type: Int, importance: KBOLinescore.Play.Importance) -> PlaySound? {
        // type 24: 홈인 (득점)
        if type == 24 { return .run }

        // type 14: 주루 (도루/진루)
        if type == 14 {
            if text.contains("도루") { return .steal }
            return nil  // 일반 진루는 소리 없음
        }

        // type 13: 타석 결과
        if type == 13 {
            if text.contains("홈런") { return .homeRun }
            if text.contains("삼진") { return .strikeout }
            if text.contains("볼넷") || text.contains("사구") { return .walk }
            if text.contains("안타") || text.contains("루타") { return .hit }
            // 나머지 아웃 (플라이, 땅볼 등)
            if text.contains("아웃") { return .flyOut }
        }

        // type 23: 안타 (별도 라인)
        if type == 23 { return .hit }

        return nil
    }
}
