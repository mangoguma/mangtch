# mangtch-new — 단계 7–10 로드맵

> **역할**: 이 문서는 **착수자(FE)**용 로드맵입니다. 작성자(Claude)는 **검토만** 합니다.
> **선행**: 단계 1–6 완료. base 커밋 = `89b188a`.
> **선행 문서**: `HANDOFF.md`, `PLAN-content-driven-sizing.md` (5 회고), `PLAN-cleanup-and-widget-mgmt.md` (6 회고)
> **브랜치**: 단계마다 `mangtch-new-wip` 에서 분기.

---

## 0. 단계 1–6 회고 (1분)

```
1: LayoutTokens (chrome 매직 넘버 단일화)
2: PanelLayoutMetrics (위젯 contract 단일화)
3: LyricsPanel 유연화
4: TimerLayoutTokens / KBOLayoutTokens (위젯 도메인 토큰)
5: 콘텐츠 주도 sizing + NSPanel resize + stable-mount wing
6: 부채 정리 + 위젯 관리 UI
```

지금까지의 축은 **chrome 을 위젯-agnostic 하게**. 단계 7–10 은 **남은 토큰 시스템 + UX 마감 + 플러그인 토대**.

---

## 1. 로드맵 한눈에

| 단계 | 주제 | 핵심 산출 | 의존 | 예상 시간 |
|---|---|---|---|---|
| **7** | 시각 토큰 시스템 (컬러 + 폰트/Dynamic Type) | `ThemeTokens`, `TypographyTokens`, light/dark + 시스템 accent 동기화 | — | 8-10h |
| **8** | Width contract 마감 | NSAnimation ↔ SwiftUI sync, Music 닫힘 시 가변 폭 복구 | 7 | 6-8h |
| **9** | 멀티 슬롯 wing + KBO 스크롤 안전망 | 좌/우 wing 독립 active widget, `ViewThatFits` 재시도 또는 ScrollView 정공법 | 5–8 | 6-8h |
| **10** | 외부 위젯 토대 | 플러그인 bundle 로드, sandbox 정책 | 9 | 12-16h+ |

각 단계 sub-PR 분할은 §3–§6 참조.

---

## 2. 우선순위 결정 가이드

작성자 추천 진행 순서: **7 → 8 → 9 → 10**.

이유:
- **7 먼저** — 컬러/폰트 토큰 없이 8/9 진행하면 새 view 들도 같은 매직 색/폰트로 채워짐. 7 후에 새 view 작성하면 처음부터 토큰 사용
- **8** 은 단계 5 의 의도적 보류 마감 (사용자 결정으로 fixed 640 절충 → 다시 동적으로). 사용자 영향은 작지만 contract 일관성 회복
- **9** 는 새 사용자 기능 (좌/우 동시) 이라 **사용자 결정 게이트** 가 있음. 8 의 width 동적이 들어가야 좌/우 폭 분리도 의미 있음
- **10** 은 가장 큼. 9 의 multi-slot 이 plugin 의 동시 마운트 의미를 결정

진행 중 우선순위 재배치 가능. Tier 표시:

- 🔴 시급 (사용자 가시 깨짐 or 회고용 부채): 없음. 단계 6 까지 완료
- 🟡 권장 (확장성 / 일관성): 7, 8
- 🟢 선택 (기능 추가): 9, 10

---

## 3. 단계 7 — 시각 토큰 시스템

### 3.1 동기

코드 base 의 hard-coded 색/폰트:
```bash
grep "Color(white:\|Color.white\|Color.black\|.fill(Color\|.foregroundStyle(.primary\|.secondary)" → ~47건
grep "font(.system(size:" → ~70건
```

이미 단계 1–4 의 `LayoutTokens` / `*LayoutTokens` 패턴이 있으니, 컬러/폰트도 **동일 패턴** (전역 chrome + 위젯 도메인) 으로 일관시킴.

### 3.2 In scope

- `ThemeTokens.swift` — 전역 컬러 (background, panel surface, divider, accent, text primary/secondary)
- `TypographyTokens.swift` — 폰트 사이즈/weight 의미 기반 (title, body, caption, monoDigit)
- 위젯별 컬러 토큰 (필요 시): `MusicThemeTokens`, `KBOThemeTokens`, `TimerThemeTokens`
- macOS 시스템 다크/라이트 동기화 (`@Environment(\.colorScheme)`)
- `Defaults[.accentColorOverride]` 설정 (Settings 에 토글)

### 3.3 Out of scope

- 사용자 정의 테마 (light pink, neon 등) — 단계 11+
- 위젯 개별 색 override — 단계 11+
- 시각 회귀 (지금 색감이 그대로 유지)

### 3.4 단계 분할

| Sub | 내용 | 위험 |
|---|---|---|
| **7a** | `ThemeTokens` 신설 + chrome (ContentView, WidgetSwitcherBar, WingShape, ExpandedPanelShape) 의 색 치환 | 낮음 |
| **7b** | `TypographyTokens` 신설 + 70 곳 `font(.system(size: N))` 의미 기반 치환 (title/body/caption/digit/large) | 낮음 |
| **7c** | Music/KBO/Timer 위젯 내부 색 토큰 치환 (`MusicThemeTokens` 등 도메인 분리) | 낮음 |
| **7d** | Dynamic Type 대응 — `TypographyTokens` 가 `Font` 가 아닌 `Font.system(.body)` 시맨틱 + scaling 옵션 | 중. 시각 회귀 가능 |
| **7e** | Settings → Appearance 섹션 (system / always light / always dark + accent override) | 낮음 |

각 sub 후 빌드 + 시각 비교 (특히 7d).

### 3.5 `ThemeTokens` 골격

```swift
import SwiftUI

/// Global panel chrome colors. Domain-specific colors (KBO live red,
/// Timer state colors) live in widget-scoped *ThemeTokens.
enum ThemeTokens {
    // MARK: Panel surface
    /// Expanded panel background. Currently Color(white: 0.14).
    static let panelBackground = Color(white: 0.14)
    /// Wing fill (notch bar + wing chrome). Currently Color.black.
    static let wingFill = Color.black
    /// Subtle divider (Lyrics box, slot toolbars).
    static let surfaceLow = Color.white.opacity(0.04)
    /// Slightly elevated chrome (Timer mode pill, ± buttons).
    static let surfaceMedium = Color(white: 0.22)
    /// Track / progress background.
    static let trackBackground = Color(white: 0.28)

    // MARK: Text
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.55)

    // MARK: Accent
    /// System accent — respects user's macOS preference.
    static let accent = Color.accentColor
    /// Brightened accent for highlight contrast (lyric active line).
    /// Mirrors `Color.ensureMinimumBrightness(factor: 0.6)` semantic.
    static let accentBright = Color.accentColor.opacity(0.85)
}
```

### 3.6 `TypographyTokens` 골격

```swift
import SwiftUI

/// Semantic typography. Sizes map to design intent, not pixel values —
/// scales with macOS system font size if Dynamic Type lands later.
enum TypographyTokens {
    /// Compact wing title (track name, KBO team name).
    static let compactTitle = Font.system(size: 11, weight: .semibold)
    /// Compact wing subtitle (artist, KBO score).
    static let compactSubtitle = Font.system(size: 10, weight: .regular)
    /// Compact wing icon glyph weight.
    static let compactGlyph = Font.system(size: 11, weight: .semibold)

    /// Expanded panel section header (KBO header).
    static let expandedHeader = Font.system(size: 12, weight: .semibold)
    /// Expanded body (game row team name, mode picker).
    static let expandedBody = Font.system(size: 11, weight: .medium)
    /// Expanded caption (KBO inning labels, slider time).
    static let expandedCaption = Font.system(size: 10, weight: .regular)

    /// Numeric display (Timer countdown). Monospaced rounded.
    static let timerDisplay = Font.system(size: 22, weight: .bold, design: .rounded)
    static let timerCompactDisplay = Font.system(size: 12, weight: .semibold, design: .rounded)

    /// KBO inning cell (small monospaced number).
    static let inningCell = Font.system(size: 11, weight: .semibold).monospacedDigit()
}
```

### 3.7 Dynamic Type 전략 (7d)

옵션 A — **시스템 시맨틱 폰트 사용**:
```swift
static let expandedBody = Font.body                   // system-driven
static let compactTitle = Font.subheadline.weight(.semibold)
```
장점: 자동 scaling. 단점: macOS notch 패널은 작은 컴팩트 영역이라 .body 가 너무 클 수 있음.

옵션 B — **scale factor only**:
```swift
@Environment(\.dynamicTypeSize) var size
static func compactTitle(scaledFor size: DynamicTypeSize) -> Font {
    let base: CGFloat = 11
    let scale = size.scaleFactor   // 자체 매핑
    return .system(size: base * scale, weight: .semibold)
}
```
장점: 픽셀 통제. 단점: 토큰 사용처마다 environment 주입.

**작성자 추천**: 옵션 A 의 시맨틱 폰트 + 위젯 영역에 `dynamicTypeSize(.medium)` 클램프 (`.dynamicTypeSize(...DynamicTypeSize.large)` 모디파이어). Notch 패널은 작은 surface 라 사용자 시스템 설정이 xLarge 여도 pixel 디자인 유지 필요.

### 3.8 검증 (각 sub)

```bash
xcodebuild ... build 2>&1 | tail -5    # SUCCEEDED
```

수동:
- 7a/c 후: 컬러 시각 회귀 0 (스크린샷 비교)
- 7b 후: 폰트 사이즈 동일 (옵션 A 면 텍스트가 시스템 폰트로 살짝 변할 수 있음 — 사용자 검수)
- 7d 후: 시스템 Dynamic Type 변경 → 컴팩트 wing 깨지는지 확인. 클램프가 작동해야 함
- 7e 후: Settings → Appearance 토글 즉시 반영

### 3.9 자가검증 grep (7c 후)

```bash
grep -rn "Color(white:\|Color.white\|Color.black\|Color.gray\|Color.secondary" \
  mangtch-new/boringNotch --include="*.swift" \
  | grep -v "ThemeTokens.swift" \
  | grep -v "MusicThemeTokens.swift\|KBOThemeTokens.swift\|TimerThemeTokens.swift"
# 결과: 가능한 작게. boring.notch 자산 (NotchHomeView) 은 제외 OK.
```

```bash
grep -rn "font(.system(size:" mangtch-new/boringNotch --include="*.swift" \
  | grep -v "TypographyTokens.swift"
# 결과: 0 (Dynamic Type 후), 또는 기존 70 → 10 미만 (의도적 잔여)
```

### 3.10 함정

1. **boring.notch 자산 (`NotchHomeView`, `MusicPlayerView`, `MusicControlsView`)** 색/폰트 변경 X. 토큰화하더라도 그 파일은 건드리지 마라. 시각 호환은 토큰 값을 원본과 일치시키는 걸로.
2. **`Color.accentColor` 가 macOS 시스템 accent 따라감** — `ThemeTokens.accent` 가 이걸 그대로 노출하면 사용자가 시스템 설정 바꾸는 즉시 반영. `Defaults[.accentColorOverride]` 도입 시 fallback 체인 명시.
3. **`Color.ensureMinimumBrightness`** — 코드 베이스에 이미 있음 (앨범아트 평균색 빛 보정). `accentBright` 의미와 분리해야 함.
4. **`@Environment(\.colorScheme)`** — light mode 일 때 `Color(white: 0.14)` 가 그대로 어두우면 안 됨. 토큰을 dynamic color (NSAppearance 기반) 로 정의하거나 `.preferredColorScheme(.dark)` 강제 (현재 `ContentView` 가 그렇게 함).

### 3.11 커밋 메시지

```
refactor(mangtch-new): introduce ThemeTokens for chrome colors (7a)
refactor(mangtch-new): introduce TypographyTokens for semantic fonts (7b)
refactor(mangtch-new): widget-scoped theme tokens (Music/KBO/Timer) (7c)
feat(mangtch-new): clamp Dynamic Type to keep notch layout (7d)
feat(mangtch-new): Appearance settings (system/light/dark + accent) (7e)
```

---

## 4. 단계 8 — Width contract 마감

### 4.1 동기

단계 5b 에서 NSAnimation (window) ↔ SwiftUI ease 동기화 실패로 wing 가장자리 wobble 발견. 절충으로 모든 위젯 `widthRange = .fixed(640)`. 부작용:
- KBO 게임 적은 날에도 panel 이 640 폭, 콘텐츠 가운데 떠보임
- Music 닫힘 시 wing 폭이 트랙 텍스트 길이와 무관 (이전 동작 회귀)

단계 8 에서 width 도 콘텐츠 주도 복구.

### 4.2 In scope

- NSAnimation / SwiftUI 두 시스템 sync 또는 한쪽으로 통일
- `WidthRange` 단계 5 이전 KBO/Music 산식 복구
- 위젯 전환 / 콘텐츠 변화 시 wing 가장자리 부드러운 폭 변화

### 4.3 단계 분할

| Sub | 내용 |
|---|---|
| **8a** | NSPanel resize 의 width 도 따라가게: `BoringNotchWindow.resizeWindow` 의 NSAnimationContext duration / curve 를 SwiftUI `.easeInOut(0.22)` 와 동일하게 명시 매칭. 또는 SwiftUI `.animation` 을 `.linear` 로 바꿔서 NSAnimation 기본과 sync |
| **8b** | KBO `widthRange` 산식 단계 5 이전으로 복구 (starter slot 폭, linescore 그리드 기반) |
| **8c** | Music `widthRange` 트랙 텍스트 기반 복구 + 닫힘 상태 wing 폭 가변 |

### 4.4 설계 결정 — 두 애니메이션 시스템 사이

문제의 본질: NSWindow `setFrame:display:animate:` 는 NSAnimation 으로 ~0.25s implicit core animation 을 돌림. SwiftUI 의 `.animation(.easeInOut(0.22), value: ...)` 는 SwiftUI 자체 timeline. 둘이 같은 시작/끝 / 같은 curve 를 못 맞추면 wing 가장자리가 SwiftUI 먼저 끝나거나, NSWindow 가 먼저 끝남 → "바깥부터 채워지는" 또는 "안쪽부터 비는" wobble.

해결 옵션:

**옵션 A — NSAnimationContext 명시 사용 + matching curve**
```swift
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.22
    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    window.animator().setFrame(newFrame, display: true)
}
```
+ SwiftUI `.animation(.easeInOut(duration: 0.22), value: ...)` 동일 duration

**옵션 B — SwiftUI 가 모든 애니메이션 담당, NSAnimation 끔**
```swift
window.setFrame(newFrame, display: true, animate: false)   // instant
```
+ SwiftUI `.frame(width: m.panelWidth)` 가 안에서 ease

window 는 즉시 jump 하고, 안의 SwiftUI content 가 ease — 시각적으로는 SwiftUI ease 만 보임. window 가 너무 작아지면 chrome 이 잘릴 위험. content frame 보다 항상 크거나 같게 유지 필요.

**옵션 C — Window 자체에 매개 layer 두지 않음, 콘텐츠 영역만 SwiftUI 가 ease**
window 는 큰 frame 으로 1회 결정 (단계 5 의 초기 폐기 안). 단, 단계 5 의 hit-zone 우려 다시 검토.

**작성자 추천**: **옵션 A**. 두 시스템 명시 sync 가 코드 의도가 가장 명확. 옵션 B 는 window jump 시 wing chrome (NSPanel border / shadow) 이 실시간 jump 해서 어색할 수 있음.

### 4.5 검증 (수동)

- 위젯 전환 (Music → KBO → Timer) 5번 반복 → wing 가장자리 부드럽게
- KBO 게임 0 → 5 → 0 변화 → 폭 ease (KBO refresh 시점에)
- Music 트랙 변화 (긴 곡 → 짧은 곡) → 폭 ease
- 한 화면 좌측 가장자리 / 우측 가장자리 클립 발생 X

성공 기준: 60fps 환경에서 시각적 점프 없음.

### 4.6 함정

1. **`@Published publishedMetrics`** 변화 시 `removeDuplicates` 가 `Equatable` 으로 비교. 폭이 변하면 새 metrics 발행 → resize. 빠르게 연속 변화 시 (KBO live 데이터 polling) 흔들림 가능. `throttle` 또는 `debounce` 검토.
2. **Music 닫힘 시 가변 폭** — `MusicPlayerWidget.widthRange` 가 닫힘 시 텍스트 길이로 동적, 펼침 시 fixed(640). 같은 위젯이 state 따라 다른 range — 가능하지만 코드 가독성 저하. 옵션:
   - state 는 chrome 책임. 위젯은 단일 range 선언 → 트랙 텍스트 폭 으로 ideal 두고 max=640. 펼침 시 chrome 이 max 로 클램프 (이미 그런 동작).
   - **즉**: Music `widthRange = WidthRange(min: 360, ideal: textBlockWidth, max: 640)`. 이러면 닫힘 = 텍스트 폭, 펼침 = 640 자동.

### 4.7 커밋

```
fix(mangtch-new): match NSAnimation curve to SwiftUI ease for width sync (8a)
feat(mangtch-new): KBO content-driven widthRange restored (8b)
feat(mangtch-new): Music widthRange tracks song title length again (8c)
```

---

## 5. 단계 9 — Priority chain 기반 wing owner + KBO 스크롤 안전망

> **9a 구현 후 모델 수정 (2026-05-08):** 최초 spec 은 "single owner, bilateral wings + WidgetSwitcherBar 삭제 (priority chain 이 panel 도 결정)" 였음. 9a 1차 빌드 직후 사용자 피드백: panel 은 위젯 전부 picker 로 보여야 함 — Timer 셋업하려고 패널 열려는데 Timer 가 아직 claim 안 했으면 접근 경로 없음. **wing axis 와 panel axis 를 분리** 하는 모델로 pivot:
> - **Wings** = priority chain (Timer running > KBO live/browsing > Music) — 자동
> - **Panel** = `WidgetSwitcherBar` 사용자 선택 — 수동
> - 두 axis 독립. Closed 시 metrics 는 wingOwnerID, Open 시 metrics 는 currentExpandedWidgetID.
>
> 자세한 회고는 §14.

### 5.1 동기

원본 Mangtch 의 KBO 라이브는 좌·우 wing 둘 다 점유 (양쪽이 한 위젯의 chrome). Dynamic Island 도 동일 — 한 activity 가 leading/trailing 둘 다 owner. NotchNook 도 좌=Music · 우=context 자동 전환 (사용자 토글 없음).

지금 mangtch-new 는 wing 슬롯이 **단일 active widget** 이 좌·우 둘 다 차지. 이건 유지. selection 도 자동화 — sw `WidgetSwitcherBar` (panel picker) 와 분리해서 wings 만 priority chain 이 결정.

KBO ScrollView fallback 은 단계 5c 에서 폐기 (`ViewThatFits` 회귀). 10경기 mock 케이스 안전망 필요 시 정공법으로 재시도.

### 5.2 모델 — single owner, bilateral wings

**좌·우 wing 동시에 한 위젯 owner**. 위젯이 자기 `leftWingView` + `rightWingView` 페어 설계.

Priority chain (state-driven, 위에서부터 평가):

```
Timer (running) > KBO (live game) > Music (playing) > 없음
```

각 위젯 wing pair:

| 위젯 | 좌 wing | 우 wing |
|---|---|---|
| Music | album art | title/artist 마퀴 |
| KBO | (live state — 팀 로고 / 점수) | linescore / 투수 |
| Timer | icon | 카운트다운 |

Wing pair 미정의 위젯 (예: Settings) 은 priority chain 진입 X (`hasWings: Bool = false`). 진입하면 좌·우 둘 다 의무 — 한쪽만 정의는 컴파일 에러.

사용자 결정 게이트 (이전 5.2 의 위치/default/충돌) — **모두 정책으로 박힘. Settings UI 없음.** WidgetSwitcherBar 삭제.

### 5.3 In scope

- `WidgetSwitcherBar` 삭제. 사용처 (NotchContentView, expanded panel chrome) 정리
- `BoringViewModel.currentExpandedWidgetID` 의 setter 가 사용자 toggle 이 아니라 priority chain 평가 결과 반영
- `NotchWidget` 프로토콜에 `wingPriority: Int` (0 = no wings) + `claimsWings(state) -> Bool` 추가
- 각 위젯에 wing pair 보장 (Music/KBO/Timer — Settings 는 wing 없음)
- `NotchWidget.preferredPosition` enum 폐기 (의미 사라짐 — bilateral 모델이라)
- KBO ScrollView 정공법 재시도 (별 sub)

### 5.4 단계 분할

| Sub | 내용 | 상태 |
|---|---|---|
| **9a** | priority chain (`wingOwnerID`) 도입 + `WidgetSwitcherBar` 는 panel-only 로 보존. `NotchWidget` 에 `wingPriority` / `claimsWings` 추가, wing pair (좌·우) non-optional 강제. KBO 는 `wingPair` 그대로, Timer 는 `TimerCompactView` → `TimerLeftWing/TimerRightWing` 분리. `PanelLayoutMetrics` 는 closed 시 wingOwner / open 시 panel-selected 위젯의 widthRange 사용 | ✅ 538e931 |
| **9b** | (불필요) — 9a 가 wing pair 의무화 + KBO/Timer 둘 다 정의 완료. 별도 sub 없음 | merged into 9a |
| **9c** | KBO ScrollView 재시도 — `ViewThatFits` 대신 `.frame(maxHeight: m.contentHeight - header)` + `.fixedSize(horizontal: false, vertical: true)` 조합. 단계 5c 회고 정독 후 | ✅ 2026-05-08 |

### 5.5 단계 5d stable-mount 와의 관계

stable-mount 는 위젯이 wing 트리를 한 번 build → opacity gate. single-owner 모델에서도 그대로:
- wing host = ZStack { 모든 wing-capable 위젯의 (leftWingView + rightWingView) }, 현재 owner 만 opacity 1
- `wingHitZoneEmissionEnabled` env 가 owner 만 true

### 5.6 검증

- Music 만 재생 → 양쪽 Music chrome
- KBO 라이브 시작 → 양쪽 KBO chrome 으로 swap (단계 5d 플리커 X)
- KBO 라이브 + Timer 시작 → 양쪽 Timer chrome (priority)
- Timer stop → 즉시 KBO 로 복귀
- KBO 라이브 종료 → Music 로 복귀
- Music 미재생 + 다른 claim 없음 → wing 없음 (notch 베어)

### 5.7 함정

1. **`preferredPosition` 폐기** — enum 자체 제거. import 깨질 수 있음, 사용처 일괄 정리
2. **Priority 충돌** — 두 위젯이 같은 priority 못 갖게 컴파일 타임 (또는 런타임 assert) 검증
3. **KBO ScrollView 정공법** — 단계 5c 의 `Color.clear` height bloat 가 진짜 root cause. ScrollView 안 자식이 height-greedy 하지 않도록 명시 + `Color.clear.frame(height: 0)` 패턴 보존
4. **panel-axis 와 wing-axis 분리** (9a 빌드 후 pivot 결정) — 사용자가 picker 로 고른 위젯과 wing owner 가 다를 수 있음. metrics 가 state 따라 다른 위젯 widthRange 를 쓰므로 closed→open 전환 시 폭이 점프할 수 있음 (KBO=400 wing → Music 패널=480 → KBO 라이브 시작 시 wing=KBO=620). NSAnimation 베지어 sync (단계 8) 가 잘 받아주는지 검증
5. **`claimsWings` boolean drift** — Timer 는 `isActive || finished` 만, KBO 는 `!isShowingToday || selectedGame.isLive`. 새 위젯 추가 시 `claimsWings` 정의 누락하면 protocol default 가 없어서 컴파일 에러 (의도) — 하지만 런타임에 항상 true 반환하면 Timer 셋업 케이스 같은 회귀 다시 등장. 9a 회고 §14 참고

### 5.8 커밋

```
refactor(mangtch-new): priority-chain wing owner decoupled from panel (9a)  ← 538e931
feat(mangtch-new): KBO ScrollView fallback for >max content (9c)
```

---

## 6. 단계 10 — 외부 위젯 (플러그인) 토대

### 6.1 동기

지금 `WidgetRegistry` 는 컴파일 타임 등록. 외부 개발자가 위젯 추가 못 함. 단계 10 은 **plugin bundle 로드** 토대.

### 6.2 결정 게이트 (큼 — 단계 9 후에 재논의)

1. **Plugin 형식** — Swift macro / dynamic library bundle / WebView 기반 / Lua-style script?
2. **Sandbox** — macOS App Sandbox 에서 외부 코드 로드 보안 정책
3. **API surface** — 위젯이 접근 가능한 시스템 API (notification, network, file system) 범위
4. **Distribution** — App Store 호환 (= 외부 코드 X) vs side-loaded build (= 가능)

위 4 모두 사용자 / 비즈니스 결정. 단계 10 착수는 아직 이르고, **로드맵 수준에서만 명시**.

### 6.3 가벼운 1차 후보 — Mangtch 내부 위젯 추가 인프라

외부 플러그인 전에, **다른 Mangtch 컨트리뷰터가 위젯 추가** 할 수 있도록 디렉토리 컨벤션 + 등록 자동화:

- `boringNotch/components/<Widget>/` 디렉토리 컨벤션
- `<Widget>Widget.swift` + `<Widget>LayoutTokens.swift` + `<Widget>ThemeTokens.swift` (단계 7 후) 골격
- `WidgetRegistry.registerDefaults` 가 컨벤션 따라 자동 등록 (Swift 매크로 또는 codegen)
- 새 위젯 `mangtch-new/` 컨트리뷰터 가이드 (`docs/ADDING_A_WIDGET.md`)

→ 이게 **단계 10a** 로 충분. 외부 플러그인 (10b+) 은 사업 / 라이선스 결정 후.

### 6.4 단계 10a 산출

- `docs/ADDING_A_WIDGET.md` — 5단계 절차 (디렉토리 만들기 → conform → 토큰 → 등록 → 테스트)
- 새 위젯 템플릿 (`templates/Widget.template.swift` 또는 GitHub gist)
- 검증: 더미 위젯 ("Hello World") 추가 → 빌드 → 동작

### 6.5 커밋

```
docs(mangtch-new): widget contributor guide (10a)
feat(mangtch-new): plugin bundle loader (10b)        # 사업 결정 후
```

---

## 7. 단계 7–10 검토 게이트 (각 PR 본문 체크리스트)

### 공통

- [ ] `xcodebuild` SUCCEEDED
- [ ] 시각 회귀 0 (단계 8/9 는 의도적 시각 변화 명시)
- [ ] 새 토큰 / 신규 파일은 pbxproj 등록 (`grep -c <token> project.pbxproj` ≥ 3)
- [ ] sub 별 자가검증 grep

### 단계 7 추가

- [ ] 7a 후 chrome 색 grep 잔재 < 5
- [ ] 7b 후 `font(.system(size:` 잔재 < 10 (도메인별 잔여만)
- [ ] 7c 후 위젯 컬러 매직 0
- [ ] 7d 후 시스템 Dynamic Type xLarge 설정에서도 컴팩트 wing 안 깨짐
- [ ] 7e 후 Settings Appearance 토글 즉시 반영

### 단계 8 추가

- [ ] 8a 후 위젯 전환 시 wing 가장자리 wobble X (60fps)
- [ ] 8b 후 KBO 게임 0 ↔ 5 변화 시 폭 ease
- [ ] 8c 후 Music 트랙 길이 변화 시 닫힘 wing 폭 변화

### 단계 9 추가

- [ ] 9a 후 좌=Music + 우=KBO 동시 마운트
- [ ] 9c 후 KBO 10경기 mock 에서 panel 안 잘리고 스크롤

### 단계 10 추가

- [ ] 10a 후 더미 "Hello World" 위젯 1개 디렉토리만 만들고 동작

---

## 8. 우선 진행 sub-set 권장

**단계 7 만이라도 단독 진행 가치 큼**. 컬러/폰트 토큰화는:
- 매직 넘버 정리의 마지막 미완 영역
- 단계 8/9 가 새 view 추가하기 전에 끝내야 부채 안 늘어남
- 사용자 가시 변화 0 (의도적 회귀 X), 안전

**단계 8 은 사용자 영향 작음** (현재 fixed 640 OK). 우선순위 낮춰도 됨.

**단계 9, 10 은 사용자 결정 게이트 큼**. 단계 7 후 별도 논의.

→ 작성자 추천 즉시 진행: **단계 7 (전체)**. 이거 끝나면 단계 8 또는 다른 사용자 우선순위로 넘어감.

---

## 9. 자가검증 종합

```bash
# 단계 7 후
grep -rn "Color(white:\|Color.white\|Color.black\|Color.gray" \
  mangtch-new/boringNotch/components --include="*.swift" \
  | grep -v "ThemeTokens\|NotchHomeView" | wc -l   # < 5
grep -rn "font(.system(size:" mangtch-new/boringNotch --include="*.swift" \
  | grep -v "TypographyTokens" | wc -l   # < 10

# 단계 8 후
grep -rn "WidthRange.fixed" mangtch-new/boringNotch --include="*.swift" \
  | grep -v "MusicPlayerWidget" | wc -l   # 0 (Music 만 fixed)

# 단계 9 후
grep -rn "currentExpandedWidgetID" mangtch-new/boringNotch --include="*.swift" \
  | wc -l   # 0 (leftActiveWidgetID/rightActiveWidgetID 로 대체)
```

---

## 10. 함정 요약 (전 단계)

1. **boring.notch 자산** (`NotchHomeView`, `MusicPlayerView`, etc.) 손대지 말 것 — 단계 7 색 토큰화에서도 예외
2. **단계 5d stable-mount** 패턴 깨지 말 것 — 단계 9 멀티 슬롯에서 같은 패턴 확장
3. **NSAnimation ↔ SwiftUI** — 단계 8 의 핵심 디버깅 영역. 단순한 "matching curve" 가 안 먹으면 옵션 B (SwiftUI 만 ease) 로 빠르게 fallback
4. **Defaults persistence** — 단계 7e (theme), 단계 9b (per-widget position) 모두 Defaults 사용. dict 한 키로 묶으면 신규 추가 비용 0 (단계 6d 에서 검증된 패턴)
5. **시즌 오프 KBO 검증** — 단계 8b/9c 의 KBO 검증 시 mock 데이터 필요. `KBOViewModel.games = mockData` 디버그 코드 임시 삽입, 커밋 X

---

## 11. 단계 11+ 후보 (참고)

- 사용자 정의 테마 (light pink, neon, custom hex)
- 위젯 마다 색 override
- 다국어 (Korean only → English / JP / ZH)
- 키보드 단축키 globally configurable
- 다른 스포츠 (MLB, EPL, NBA) 위젯
- macOS 멀티 디스플레이 / 외부 모니터 사용성 정련
- 대용량 trace logging 옵션 (디버그용)

---

**검토자**: Claude
**예상 시간**: 7 ≈ 8-10h, 8 ≈ 6-8h, 9 ≈ 6-8h, 10 ≈ 12-16h+
**총 PR**: 7=5개, 8=3개, 9=3개, 10=2개+ → 13개+

---

## 12. 단계 7 회고 (2026-05-08 완료)

base = `89b188a` → 단계 7 종료 = `6ce8f7b` (5 커밋, 모두 `mangtch-new-wip`).

### 12.1 들어간 커밋

```
45e4ca7 docs(mangtch-new): roadmap for phases 7-10
4a183b7 refactor(mangtch-new): introduce ThemeTokens for chrome colors (7a)
fa18a92 refactor(mangtch-new): introduce TypographyTokens for semantic fonts (7b)
2078080 refactor(mangtch-new): widget-scoped theme tokens (Music/KBO/Timer) (7c)
6ce8f7b feat(mangtch-new): adaptive panel shading + appearance settings (7d/7e)
```

### 12.2 In-spec 산출

- `sizing/ThemeTokens.swift` — chrome colors (panel/wing 변종 + accent + text)
- `sizing/TypographyTokens.swift` — ~25 semantic font 토큰 (compactTitle, expandedHeader, kboBigScore, timerDisplay, microBadge 등)
- `components/Music/MusicThemeTokens.swift` — lyrics card surface + inactive/placeholder
- `components/KBO/KBOThemeTokens.swift` — live red, win blue, B/S/O 팔레트, base yellow, **rowBaselineTint** (12.3 참조)
- `components/Timer/TimerThemeTokens.swift` — surfaceMedium, trackBackground, pausedAccent
- `Defaults[.panelAppearance]` (`.system` / `.light` / `.dark`) + Settings → Appearance → Panel section
- `BoringViewModel.systemIsDark` — `AppleInterfaceThemeChangedNotification` + Defaults override 합성
- ContentView `.dynamicTypeSize(...DynamicTypeSize.large)` 클램프 (7d)

### 12.3 7d/7e 도중 의도 변경 (KBO row baseline)

플랜 §3 의 dark variant 는 처음 `Color.black` (jet) 으로 잡았는데, 사용자 시각 검수에서 **KBO list row 배경이 원본 Mangtch 와 다르게 보임** 보고. 원인:
- 원본 Mangtch DarkTheme panel = `Color(white: 0.12)` 항상
- 단계 7 dark panel = `Color.black` (jet)
- KBO row 배경은 알파 합성 (`Color.primary.opacity(0.04..0.16)`) 이라 panel base luminance 에 따라 결과 톤이 다름

해결: panel 은 **jet black 유지** (메뉴바 OLED 검정과 합쳐지는 효과), row 만 dark mode 일 때 baseline tint (`KBOThemeTokens.rowBaselineTint = Color.white.opacity(0.06)`) 를 row 별 background 아래 깔아 원본 Mangtch 의 12% panel underlay 시뮬레이션. KBOExpandedView 가 `@EnvironmentObject vm: BoringViewModel` 받아 `vm.systemIsDark` 체크.

### 12.4 Out-of-spec 의도적 잔여

- `font(.system(size:` 7건 (KBOExpanded 10.5/11.5 one-off, 조건부 isHeader, KBOLive placeholder 14pt + playText 10pt). 플랜 자가검증 기준 < 10 충족
- `Color(white:` / `Color.white.opacity(` 등 일부 site (보통 stroke / divider): boring.notch 자산 (`NotchHomeView`, `MusicPlayerView`, `MusicVisualizer`, `Button+Bouncing`, `AnimatedFace`) + Settings/Shelf — 플랜 §3.10.1 대로 손대지 않음
- 7d 효과는 forward-protection: 현재 `TypographyTokens` 가 픽셀 폰트라 `dynamicTypeSize` 클램프는 no-op. 미래 `.body`/`.subheadline` 시맨틱 폰트 채택 시 발효

### 12.5 단계 8 시작 시 주의

- **`BoringViewModel.systemIsDark` 새 @Published** — 단계 8 의 metrics 변화 감지에는 영향 없음 (`setupMetricsTracking` 은 notchSize/notchState/currentExpandedWidgetID 만 결합). 그러나 `recomputeMetrics` 가 metrics 외 published 들을 의도치 않게 트리거하는지 확인
- **panel 배경 dark/light 분기** — 단계 8 의 NSAnimation curve 매칭 작업 중 panel 색이 동적이라 시각 디버깅 어려울 수 있음. 디버그 빌드 시 `.system` 으로 고정 권장
- **`@EnvironmentObject vm: BoringViewModel` 신규 의존 (KBOExpandedView)** — KBOWidget 이 expanded view 만들 때 vm 환경이 자동 주입되는지 (ContentView 가 EnvironmentObject 로 주입). 회귀 테스트 시 KBO 펼치기 정상 동작 확인

### 12.6 자가검증 결과

```bash
$ grep -rn "Color(white:\|Color.white\|Color.black\|Color.gray" \
    mangtch-new/boringNotch/components --include="*.swift" \
    | grep -v "ThemeTokens" | grep -v "NotchHomeView\|MusicPlayerView\|MusicControlsView\|MusicVisualizer\|AnimatedFace\|Button\+Bouncing\|Settings/\|Shelf/"
# 결과: < 5 (의도적: KBO row baseline는 KBOThemeTokens 경유)

$ grep -rn "font(\.system(size:" mangtch-new/boringNotch --include="*.swift" \
    | grep -v "TypographyTokens\|NotchHomeView\|MusicPlayerView\|MusicControlsView\|Settings/\|Shelf/\|EmptyState\|KBOTeamLogo"
# 결과: 7건 (의도적 잔여, < 10 충족)

$ grep -c "ThemeTokens\.\|TypographyTokens\.\|KBOThemeTokens\.\|MusicThemeTokens\.\|TimerThemeTokens\." \
    mangtch-new/boringNotch.xcodeproj/project.pbxproj
# 12 (build refs + file refs + group refs across 5 token files)
```

### 12.7 다음 작업자에게

- 단계 8 (Width contract 마감) 또는 9 (멀티 슬롯 wing) 로 진행. 플랜 §4–§5 그대로 유효
- 단계 7 의 시각 토큰 시스템이 정착했으니 새 view 추가 시 무조건 `*Tokens` 경유. 매직 색/폰트 다시 추가하지 말 것
- 단계 9 좌/우 wing 독립 active widget 작업 시 §5.2 의 사용자 결정 게이트 3개 (위치 UI / default / 충돌) 먼저 확정

---

## 13. 단계 8 회고 (2026-05-08 완료)

base = `c572177` (단계 7 종료) → 단계 8 종료 = `2d4dfb1` (3 커밋, 모두 `mangtch-new-wip`).

### 13.1 들어간 커밋

```
7068dac fix(mangtch-new): match NSAnimation curve to SwiftUI ease for width sync (8a)
91cacec feat(mangtch-new): KBO content-driven widthRange restored (8b)
2d4dfb1 feat(mangtch-new): Music widthRange tracks compact/expanded state (8c)
```

### 13.2 In-spec 산출

- `BoringNotchWindow.resizeWindow` — width 잠금 해제 (`metrics.panelWidth` 추종) + `CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1.0)` 명시 베지어 (SwiftUI `easeInOut` 곡선과 일치)
- `KBOWidget.widthRange` — Mangtch 레퍼런스 산식 포팅. starter slot (NSFont 측정) + 닫힌 row layout / 펼친 linescore grid 두 모드. `LayoutTokens.panelMaxWidth = 640` 캡
- `KBOWidget.expandedStarterSlotWidth` / `inlineStarterSlotWidth` — 실측 기반 starter slot 계산
- `PanelLayoutMetrics.resolve` — state-aware. closed → `ideal`, open → `max`
- `MusicPlayerWidget.widthRange` — `WidthRange(380, 480, 640)`. 닫힘 = compactWidth 480, 펼침 = expandedWidth 640
- `MusicLayoutTokens.compactWidth` (480) + `compactMinWidth` (380) 신설

### 13.3 설계 결정 — 옵션 A 채택

플랜 §4.4 가 옵션 A (NSAnimationContext 명시 + matching curve) / 옵션 B (window 즉시 jump + SwiftUI ease) / 옵션 C (window 1회 결정) 중 추천한 옵션 A 를 채택. 핵심:

- CoreAnimation `.easeInEaseOut` 와 SwiftUI `.easeInOut` 은 **거의** 같지만 정확히 같지는 않음 → 실수로 wobble 재발 가능
- `CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1.0)` 이 SwiftUI `easeInOut` 베지어와 정확히 일치
- `ctx.allowsImplicitAnimation = true` 는 유지 — `setFrame:display:animate:` 가 implicit animation 안에서 작동하도록

### 13.4 Out-of-spec 의도적 잔여

- Timer 위젯은 `WidthRange.fixed(LayoutTokens.panelMaxWidth)` 그대로. 단계 8 spec 에 없었음. Timer 콘텐츠가 폭 가변 드라이버가 없는 (mode picker 고정 폭) 상태라 fixed 유지가 합리적
- Music 가변 폭은 트랙 텍스트 실측이 아닌 고정 480pt — Mangtch 레퍼런스도 `preferredPanelWidth: 480` 고정. 단계 8c spec 의 "트랙 텍스트 기반" 은 §4.6 의 한 옵션이었고, 더 단순한 옵션 (고정 compactWidth) 채택
- 자가검증 grep `WidthRange.fixed` 잔재: Timer + MusicLayoutTokens.expandedWidth 사용처 + Music heightRange = 3건. 플랜 §9 기준은 "Music 만 fixed" 였는데 Timer 도 fixed → 4건 이상. 의도적 잔여로 판단

### 13.5 자가검증 결과

```bash
$ grep -rn "WidthRange.fixed\|\.fixed(" mangtch-new/boringNotch --include="*.swift" \
    | grep "WidthRange\|HeightRange"
# Timer widthRange (fixed 640), Music heightRange (fixed 190)
# KBO + Music widthRange 모두 동적

$ xcodebuild ... build 2>&1 | tail -3
# ** BUILD SUCCEEDED **
```

수동 시각 검증 (사용자 확인):
- 위젯 전환 (Music ↔ KBO ↔ Timer) wing 가장자리 wobble 없음
- KBO 게임 수 / linescore 토글 시 폭 ease
- Music 펼침 / 닫힘 시 wing 폭 480 ↔ 640 ease

### 13.6 단계 9 시작 시 주의

- `PanelLayoutMetrics.resolve` 가 state-aware 가 됐으므로, 단계 9 의 좌/우 wing 독립 active widget 도입 시 좌/우 각각의 widthRange 합산 / 충돌 정책 필요 (§5.2 결정 게이트 1, 3)
- 단계 8 의 NSAnimation 베지어 sync 는 윈도우 단일 frame 변화에 한정. 단계 9 가 좌/우 wing 비대칭으로 동시에 변화하면 동일 곡선 + 동일 duration 가정이 깨질 수 있음 — 검증 필요
- KBO content-driven width 는 `viewModel.startingPitchers` / `viewingLinescore` 의존. 단계 9 에서 KBO 가 wing 한쪽만 점유하는 case (wing claim 정책) 도입 시 widthRange 산식 분기 필요


---

## 14. 단계 9a 회고 (2026-05-08 완료)

### 14.1 들어간 커밋

```
538e931 refactor(mangtch-new): priority-chain wing owner decoupled from panel (9a)
```

11 files changed, +316 / -209. `TimerCompactView.swift` 삭제, `WidgetSwitcherBar.swift` 보존 (1차 빌드 후 결정 번복).

### 14.2 모델 (확정)

**Two-axis ownership.** wing 과 panel 이 다른 source 를 따름:

| Axis | Source | 의미 |
|---|---|---|
| Wings | `BoringViewModel.wingOwnerID` (priority chain) | "지금 가장 foreground 한 활동" — Dynamic Island 답 |
| Panel | `BoringViewModel.currentExpandedWidgetID` (사용자 picker) | "사용자가 보고 싶은 위젯" — NotchNook 답 |

- Priority chain: **Timer (20) > KBO (10) > Music (1)**.
  - Timer: `isActive || state == .finished` 시 claim.
  - KBO: `!isShowingToday || selectedGame.isLive` 시 claim.
  - Music: 항상 claim (chain 의 floor).
- `recomputeWingOwner` 가 `withObservationTracking` 으로 매 변화마다 재평가. `recomputeMetrics` 와 동일 패턴.
- `PanelLayoutMetrics` 호출 시 state-aware 분기:
  - `.closed` → `wingOwnerID` 의 widthRange (wings 만 보이니까)
  - `.open` → `currentExpandedWidgetID` 의 widthRange (panel 보이니까)

### 14.3 Pivot — 빌드 후 모델 수정

최초 plan §5.2 의 사용자 결정 게이트 3개 → 우리가 다 박는다 결정. 결과: "single owner, bilateral wings + WidgetSwitcherBar 삭제" 로 spec.

1차 9a 빌드 후 사용자 시각 검증:
> "위젯 선택이 없어졌는데? 노래만 보임"

문제: priority chain 만으로는 Timer 셋업 / KBO 비-라이브 schedule 보기 같은 정상 use case 의 진입 경로가 없음. wing 은 자동, panel 은 사용자 의도여야 함.

→ `WidgetSwitcherBar` 부활, `wingOwnerID` 와 `currentExpandedWidgetID` 분리. 빌드 후 다시 사용자 검증:
> "timer 시계 돌아가고 있을 때 아니면 kbo or music 으로 복귀해야지. 지금은 timer 창에만 들어가도 wing 에 고정됨"

문제: `claimsWings` 가 `isActive || displayTime > 0` 였는데, countdown 셋업 (시간만 미리 셋) 단계에 displayTime > 0 이라 claim. → `isActive || state == .finished` 로 좁힘. Stopwatch 는 setup 시 displayTime=0 이라 미영향.

### 14.4 In-spec 산출

- `NotchWidget.wingPriority: Int` + `var claimsWings: Bool` 추가
- `NotchWidget.preferredPosition` + `WidgetPosition` enum 폐기 (의미 없음 — bilateral 모델)
- `makeLeftWingView`/`makeRightWingView` non-optional `AnyView` 강제 (좌·우 의무)
- `BoringViewModel.wingOwnerID` (private(set)), `currentExpandedWidgetID` (사용자 picker)
- `WidgetRegistry.register` 에서 `wingPriority` 중복 assert
- ContentView wing host: `vm.wingOwnerID` 기반, panel: `vm.currentExpandedWidgetID` 기반
- `PanelLayoutMetrics` 호출 시 state-aware widget 선택
- TimerCompactView 분리 → TimerLeftWing (progress ring) + TimerRightWing (countdown digits)

### 14.5 Out-of-spec 의도적 잔여

- Music 의 right wing 은 title/artist 마퀴 + 컨트롤 그대로. 단계 9 §5.2 표 ("Music 우 wing = title/artist 마퀴") 와 일치 — boring.notch 원본의 visualizer 은 도입 안 함
- Settings 위젯은 wing claim 안 함 — `WidgetRegistry` 등록 안 됨 (priority chain 진입 X). `wingPriority == 0` 슬롯은 미사용 — 향후 Settings-style chrome 추가 시 활용

### 14.6 자가검증

```bash
$ xcodebuild ... build 2>&1 | tail -3
# ** BUILD SUCCEEDED **
```

수동 시각 검증 (사용자 확인):
- Music 만 재생 → wings = Music
- KBO 패널 picker 진입 → panel=KBO, wings=Music 유지 (sw 분리 검증)
- Timer 시작 → wings = Timer 로 swap
- Timer 셋업만 (시작 X) → wings = Music/KBO 유지

### 14.7 단계 9c 시작 시 주의

- 단계 9 의 multi-axis 가 도입됐으므로, KBO ScrollView 정공법 시 viewport height 가 `metrics.contentHeight` (panel-selected 위젯 = KBO 일 때) 기준이어야 함. wingOwnerID 가 KBO 가 아니어도 panel 이 KBO 면 그 사이즈 사용
- 단계 5c 의 `Color.clear` height bloat 는 ScrollView 안 자식이 height-greedy 했던 게 root cause. ScrollView 도입 시 자식 hierarchy 의 모든 노드가 `.fixedSize(horizontal: false, vertical: true)` 또는 `.frame(maxHeight:...)` 로 height 명시 필요

---

## 15. 단계 9c 회고 (2026-05-08 완료)

### 15.1 들어간 변경

```
KBOExpandedView.swift   +34 / -7
```

`gamesList` 직접 마운트를 `gamesScroller` (ScrollView 래퍼) 로 교체. 산식 + 토큰은 그대로 — 5c 의 `Color.clear.frame(height: 0)` height-lock 은 이미 라이브 행 좌·우 슬롯 (line 208, 472) 에 박혀 있어 root cause 재발 위험 없음.

### 15.2 In-spec 산출

- `KBOExpandedView.gamesScroller` — `ScrollView(.vertical, showsIndicators: false)` + 자식 `gamesList` 에 `.fixedSize(horizontal: false, vertical: true)` 강제. ScrollView 자체는 `.frame(maxHeight: availableGamesHeight)` 로 클램프
- `KBOExpandedView.availableGamesHeight` — `vm.publishedMetrics?.contentHeight ?? vm.metrics.contentHeight` 에서 chrome (header 24 + bodyOuterSpacing 6 + panelOuterVerticalPadding 16) 차감. publishedMetrics 우선이라 Combine resize 가 즉시 반영됨
- 9a multi-axis 호환 — `vm.metrics` 가 `notchState == .open` 이면 `currentExpandedWidgetID` (= "kbo" when KBOExpandedView 마운트됨) 의 widthRange/heightRange 를 쓰므로 wingOwner 가 KBO 가 아니어도 (예: Timer running + KBO panel-selected) viewport 가 KBO 사이즈

### 15.3 Out-of-spec 의도적 잔여

- `.scrollBounceBehavior(.basedOnSize)` 미적용 — 콘텐츠 < maxHeight 면 ScrollView 가 자연스럽게 콘텐츠 height 로 줄어들어 bounce 안 발생. 명시 modifier 가 필요해지면 그때 추가
- 산식과 실제 콘텐츠 미세 불일치 (rowHeight 50 추정 vs 실제 ~46) 는 그대로 — 통상 케이스 (≤5경기) 는 maxHeight > intrinsic 라 ScrollView 가 발동 안 하니 무해. 10경기 mock 강제 시에만 의미

### 15.4 자가검증

```bash
$ xcodebuild ... build 2>&1 | tail -3
# ** BUILD SUCCEEDED **
```

수동 확인 권장 (사용자 검수 필요):
- 통상 1~5경기 → 스크롤 발동 X, 패널 콘텐츠와 같이 자람
- KBO mock 10경기 / 작은 디스플레이 (panelScreenSafeFraction × 화면 높이 < ideal) → 스크롤 발동
- linescore 펼침 시 스크롤 영역 안에서 행 높이 점프 자연스러운지 (5c bloat 회귀 X)
- 9a 의 wingOwner ≠ panel-selected 케이스 — Timer running + KBO panel 진입 → KBO panel viewport 가 KBO heightRange 따라 결정되는지

### 15.5 단계 10a 시작 시 주의

- 단계 9 (multi-slot wing) 는 사용자 결정 게이트 (§5.2) 미해결로 보류. 10a (위젯 contributor 가이드 docs) 가 다음 cheapest 후보
- 10a 작성 시 `NotchWidget` 프로토콜의 `wingPriority` / `claimsWings` / `widthRange` / `heightRange` 4-tuple 이 contract 의 핵심. 9a/9c 결정사항 (wing pair 좌·우 의무, ScrollView fallback 패턴) 도 가이드에 박혀야 함
