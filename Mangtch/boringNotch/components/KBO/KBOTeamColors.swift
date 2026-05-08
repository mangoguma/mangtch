import SwiftUI

/// Primary team colours for the 10 KBO clubs. Used to tint the pitcher /
/// batter chips in the live state so users can pattern-match the side at
/// bat without re-reading the team names. Codes match Naver's two-letter
/// `homeTeamCode` / `awayTeamCode` (HT = KIA, OB = 두산, SK = SSG, etc.).
enum KBOTeamColors {
    static func primary(for code: String) -> Color {
        switch code {
        case "HH": return Color(red: 252/255, green: 78/255, blue: 0/255)    // 한화 — 주황
        case "HT": return Color(red: 234/255, green: 0/255, blue: 41/255)    // KIA — 빨강
        case "KT": return Color(red: 0/255, green: 0/255, blue: 0/255)       // KT — 검정
        case "LG": return Color(red: 195/255, green: 4/255, blue: 82/255)    // LG — 빨강
        case "LT": return Color(red: 0/255, green: 41/255, blue: 85/255)     // 롯데 — 남색
        case "NC": return Color(red: 49/255, green: 91/255, blue: 168/255)   // NC — 청색
        case "OB": return Color(red: 19/255, green: 18/255, blue: 48/255)    // 두산 — 남색
        case "SK": return Color(red: 206/255, green: 14/255, blue: 45/255)   // SSG — 빨강
        case "SS": return Color(red: 7/255, green: 76/255, blue: 161/255)    // 삼성 — 파랑
        case "WO": return Color(red: 91/255, green: 14/255, blue: 45/255)    // 키움 — 보르도
        default: return .secondary
        }
    }
}
