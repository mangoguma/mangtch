import AppKit
import AVFoundation

/// Plays system sounds for KBO play events. Independent of the TTS
/// ticker — both can be enabled simultaneously.
@MainActor
final class KBOSoundManager {
    static let shared = KBOSoundManager()
    private var player: AVAudioPlayer?
    private init() {}

    enum PlaySound: String {
        case hit = "Ping"
        case homeRun = "Hero"
        case run = "Glass"
        case strikeout = "Basso"
        case flyOut = "Bottle"
        case walk = "Blow"
        case steal = "Funk"
        case inningChange = "Submarine"
    }

    func play(_ sound: PlaySound) {
        let path = "/System/Library/Sounds/\(sound.rawValue).aiff"
        let url = URL(fileURLWithPath: path)
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = 1.5
        p.prepareToPlay()
        player = p
        p.play()
    }

    func soundForPlay(_ text: String, type: Int, importance: KBOLinescore.Play.Importance) -> PlaySound? {
        if type == 24 { return .run }
        if type == 14 {
            if text.contains("도루") { return .steal }
            return nil
        }
        if type == 13 {
            if text.contains("홈런") { return .homeRun }
            if text.contains("삼진") { return .strikeout }
            if text.contains("볼넷") || text.contains("사구") { return .walk }
            if text.contains("안타") || text.contains("루타") { return .hit }
            if text.contains("아웃") { return .flyOut }
        }
        if type == 23 { return .hit }
        return nil
    }
}
