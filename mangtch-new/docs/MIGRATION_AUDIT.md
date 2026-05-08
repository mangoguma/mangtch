# Mangtch → mangtch-new — 마이그레이션 점검

> 목적: `Mangtch/`(SPM 원본)과 `mangtch-new/`(boring.notch 베이스 포팅본) 사이의
> 기능/구조 차이를 한 자리에 정리. 완전 마이그레이션 전 누락된 항목을
> 빠짐없이 식별하고, 가장 시급한 항목 — **호버 시 wing 컨트롤 노출** —
> 의 구현 계획을 박는 문서.
>
> 베이스 비교 시점: `mangtch-new-wip` 브랜치 tip `d5c2365` (2026-05-08).
> 아키텍처 룰(§1 of `HANDOFF.md`)을 우선한다 — boring.notch 클래스명 유지,
> Mangtch 기능만 그래프트.

---

## 1. 한눈 비교

| 영역 | Mangtch | mangtch-new | 상태 |
|---|---|---|---|
| 빌드 | SPM (`Package.swift` + `build-app.sh`) | Xcode (`boringNotch.xcodeproj`) | 의도적 차이 (룰 §1) |
| 메인 윈도우 | `NotchWindow` (NSPanel) | `BoringNotchWindow` (NSPanel) | 동등 — 클래스명만 다름 |
| 패널 VM | `NotchViewModel` (@Observable) | `BoringViewModel` (ObservableObject) | 동등 — 명명 규칙 따로 |
| 멀티 디스플레이 | `NotchWindowManager` 전담 | `AppDelegate.windows` 딕셔너리 | 동등 |
| 위젯 프로토콜 | `NotchWidget` + `WidgetRegistry` | 동일 | 1:1 포팅됨 (10a 시점) |
| 상태 머신 | `idle / hovering / expanded` (3-state) | `closed / open` (2-state) | **갭 — §3 참고** |
| Wing 호버 컨트롤 | 호버 시 노출 (`CompactArtworkView`) | **항상 노출** (`MusicCompactInfo`) | **갭 — §3 참고** |
| Wing 클릭 디스패치 | `WingHitZone` PreferenceKey + GestureHandler | 동일 메커니즘 포팅됨 | 동등 |
| Wing 좌우 owner | 1축(state-driven) | 2축 (`wingOwnerID` + `currentExpandedWidgetID`) | mangtch-new 가 진화 |
| KBO 위젯 | 9 파일 | 동등 + `KBOLayoutTokens` / `KBOThemeTokens` 추가 | 1:1 + 강화 |
| Timer 위젯 | 4 파일 | 동등 + Layout/Theme 토큰 | 1:1 + 강화 |
| Music 위젯 | `MusicPlayerWidget` + 5 파일 | `MusicPlayerWidget` + boring.notch UI 재사용 | 일부 갭 — §4 참고 |
| 가사 (synced) | `LyricsManager` + LRCLIB + NetEase 직접 fetch | `MusicManager.syncedLyrics` 표시만 | **갭 — §4.2** |
| 트랙 변경 알림 | `trackChangeNotificationOverlay` (NotchContentView) | 없음 | **갭 — §4.3** |
| HUD 위젯 | `WidgetRegistry["hud"]` 슬롯 + 오버레이 마운트 | 없음 | 갭 (저우선) |
| Debug 오버레이 | `Defaults[.debugOverlay]` 토글 | 없음 | 갭 (저우선) |
| FileShelf | `FileShelfWidget` (위젯으로 등록) | boring.notch `Shelf*` (위젯 미등록) | 갭 — §4.4 |
| Album-art 테마 추출 | `ColorExtractor` + `ThemeManager` | `MusicManager.avgColor`만 사용 | 의도적 드롭 (룰) |
| Spotify OAuth | `SpotifyAuth` PKCE + `SpotifyAPI` | 없음 (boring.notch `SpotifyController`만) | 의도적 드롭 (룰) |
| Onboarding | `OnboardingWindow` | 없음 | 의도적 드롭 (룰) |
| Settings | 4 view | `SettingsView` + `EditPanelView` 등 | 동등 (강화됨) |
| 사운드 토큰 시스템 | `Core/Theme/*Theme.swift` | `sizing/{Theme,Typography}Tokens` + 위젯별 `*ThemeTokens` | mangtch-new 가 진화 (Phase 7) |
| Sizing 모델 | `preferredPanelWidth: CGFloat?` | `widthRange/heightRange: WidthRange/HeightRange` | mangtch-new 가 진화 (Phase 8) |

> "동등"으로 표시한 항목은 **실제로 동등**한지 코드 디프로 검증한 것이 아니라
> 책임이 같은 지점이 존재한다는 뜻이다. 세부 동작 차이는 §4에서 다룬다.

---

## 2. Mangtch 에만 있는 파일 (포트 검토 대상)

`find` 비교로 추린 목록. `out of scope` 표시는 룰 §1에 의해 의도적으로 미포팅.

### 2.1 코어 인프라
- `App/MenuBarManager.swift` — boring.notch `StatusBarMenu` 가 대체. 동등.
- `App/UpdateManager.swift` — boring.notch `SoftwareUpdater` 가 대체. 동등.
- `Core/Settings/{DefaultsKeys,SettingsManager}.swift` — boring.notch가 sindresorhus/Defaults 직접 사용. 동등.
- `Core/EventBus/EventBus.swift` — **mangtch-new 에 미포팅**. 사용처가 없으면 룰 §1 "fallback shim 금지" 정신상 그대로 둔다. 사용처가 있다면 추적 필요. (현재 검색 결과 Mangtch 내부에서도 사용처 미미)
- `Core/Theme/*` — Album-art 테마 추출 모듈. **의도적 드롭** (룰 §1).
- `managers/{LyricsManager,ShortcutManager,ThemeManager}.swift` — Lyrics/Theme 의도적 드롭. ShortcutManager는 전역 키바인딩 매핑 — boring.notch 가 `Shortcuts/ShortcutConstants.swift` 로 갖고 있으니 동등.
- `SystemBridge/Lyrics/*` — LRCLIB / NetEase 클라이언트. **의도적 드롭** (룰 §1). 실제로는 mangtch-new 의 `MusicExpandedView.LyricsPanel` 이 `MusicManager.syncedLyrics` 를 표시하지만 **fetch 경로가 없다** — §4.2.
- `SystemBridge/Spotify/*` — PKCE OAuth. **의도적 드롭** (룰 §1).
- `SystemBridge/SystemInfoBridge.swift` — 시스템 정보 조회 헬퍼. 사용처 확인 후 결정.

### 2.2 위젯 / UI
- `components/Music/AudioVisualizerView.swift` — 재생 중 막대 비주얼라이저. mangtch-new 는 boring.notch `MusicVisualizer.swift` 가짐 — 시각적으로 다름. Mangtch 의 디자인이 더 컴팩트.
- `components/Music/ExpandedPlayerView.swift` — Mangtch 의 expanded 음악 UI. mangtch-new 는 boring.notch `MusicPlayerView` 재사용 — 의도적 결정.
- `components/Music/MarqueeText.swift` — boring.notch 의 `MarqueeTextView.swift` 가 대체.
- `components/Music/MusicPlayerViewModel.swift` — Mangtch 의 자체 VM. mangtch-new 는 boring.notch `MusicManager.shared` 사용 — 의도적 결정. **여기서 호버-컨트롤이 분기됨** — §3.
- `components/Music/NowPlayingView.swift` — `CompactArtworkView` (좌측, 호버시 컨트롤) + `CompactInfoView` (우측, 텍스트만). **mangtch-new 가 좌우를 뒤집고 항상-노출로 변경**.
- `components/Notch/NotchScreenResolver.swift` — 멀티 디스플레이 스크린 해상 헬퍼. mangtch-new 는 `NSScreen+UUID` + `AppDelegate.windows` 로 처리 — 동등.
- `components/Onboarding/*` — **의도적 드롭**.
- `components/Settings/{Appearance,General,Widget}SettingsView.swift` — mangtch-new 는 단일 `SettingsView` + 분리된 컴포넌트로 재구성. 동등.
- `components/Shelf/FileShelf*.swift` — **갭**. boring.notch `Shelf*` 시리즈가 있으나 위젯 등록 안 됨 → §4.4.

### 2.3 옵저버
- `observers/DragDetector.swift` — mangtch-new 에도 동명 파일 있음. 디프 확인 필요.
- `observers/FullscreenObserver.swift` — mangtch-new 의 `FullscreenMediaDetection.swift` 가 동등 책임. 동등.

---

## 3. 핵심 갭 — Wing 호버-컨트롤 누락 (구현 계획)

### 3.1 현재 상태

**Mangtch (`NowPlayingView.swift:8-101`)**
- 좌측 wing = `CompactArtworkView`. ZStack 두 레이어:
  - 평상시: 앨범아트 24x24 + (재생 중) `AudioVisualizerView`.
  - `notchVM.hoveredWing == .left` 시: `compactControls` (prev/play-pause/next, 각 `wingHitZone(.musicPrev)` 등 부착).
- 두 레이어가 **항상 마운트된 채** opacity + `allowsHitTesting`만 swap — Button 의 mouseDown↔mouseUp 트래킹이 SwiftUI 트리 재구성으로 끊기는 버그를 회피한 의도적 설계 (`NowPlayingView.swift:18-22` 코멘트).
- 우측 wing = `CompactInfoView`: title/artist 마퀴 텍스트만, **컨트롤 없음**.
- 상태머신: `idle → hovering → expanded`. wing 호버는 `.hovering` 상태에서 일어남 — 패널은 컴팩트 폭 유지.

**mangtch-new (`MusicPlayerWidget.swift:74-108`)**
- 좌측 wing = `MusicCompactArtwork`: 앨범아트 22x22 only.
- 우측 wing = `MusicCompactInfo`: title/artist + **prev/play-pause/next 항상 노출**.
- `hoveredWing` 자체는 `BoringViewModel.swift:32` 에 정의되고 `GestureHandler.swift:186-196` 에서 갱신 중 — **사용처가 없음**.
- 상태머신: `closed → open`. hover-zone 진입 즉시 `vm.open()` 호출 (`GestureHandler.swift:199-202`) → "패널 닫혀있는데 wing 만 hover" 라는 중간 상태가 표현 불가.

### 3.2 결정 분기

호버-컨트롤을 살리는 두 갈래:

| | A. 미니멀: opacity 게이팅만 추가 | B. 풀: `.hovering` 중간 상태 도입 |
|---|---|---|
| 변경 범위 | `MusicPlayerWidget.swift` 한 파일 | `BoringViewModel`, `GestureHandler`, `PanelLayoutMetrics`, `ContentView`, `MusicPlayerWidget` |
| 예상 LOC | ~20 | ~150 |
| Mangtch 동작 충실도 | 70% (패널이 호버시 즉시 열림 — 호버 컨트롤은 잠깐만 보임) | 100% |
| 부작용 | 패널 열림이 호버 즉시라 컨트롤 swap 이 시각적으로 의미 약함 | `recomputeMetrics` / `wingOwnerID` 의 state 의존 재검토 필요 |
| 권장 | 임시 패치용 | **본 마이그레이션의 정공법** |

본 문서는 **B 안** 을 기준으로 계획을 박는다. A 는 fallback.

### 3.3 B 안 — 단계별 구현

#### Step 1. `BoringViewModel.NotchState` 에 `.hovering` 추가

```swift
enum NotchState { case closed, hovering, open }
```

기존 `if notchState == .open` 분기는 의미상 셋으로 갈라짐:
- 패널 폭/높이 목적 → `notchState != .closed` (hovering 도 패널-모드 폭이라면) **OR** `notchState == .open` (hovering 은 컴팩트-모드 폭 유지) → **후자가 Mangtch 동작**.
- hit-testing 목적 → `notchState == .open` (.expanded 와 동등).
- wing 컨트롤 노출 목적 → `notchState != .closed` (hover-but-compact 도 컨트롤 보여야 함).

각 분기는 grep 으로 잡아 의미 단위로 재라우팅. 후보 파일:
`BoringViewModel.swift`, `ContentView.swift`, `BoringNotchWindow.swift`, `GestureHandler.swift`, `PanelLayoutMetrics.swift`, `KBOWidget.swift::heightRange`.

#### Step 2. `PanelLayoutMetrics.resolve` 의 `state` 파라미터 3-갈래 처리

현재 (8c) 는 `.closed → ideal`, `.open → max`. 새로:

```swift
switch state {
case .closed:   width = clamp(widthRange.ideal, …)   // 컴팩트 wing
case .hovering: width = clamp(widthRange.ideal, …)   // 컴팩트 유지 — 패널은 안 열림
case .open:     width = clamp(widthRange.max, …)     // 풀 캔버스
}
```

Music 위젯의 경우 `.hovering` 시 wing 이 `compactWidth=480` 이라 prev/play/next 가 끼어들 공간이 부족하면 호버시 폭 boost 가 추가로 필요 — Mangtch 의 `panelModeWingWidth` boost 와 같은 패턴. 실측 후 `compactHoverWidth` 토큰을 `MusicLayoutTokens` 에 추가하는 식.

#### Step 3. `GestureHandler` 의 호버존 처리 재구성

Mangtch (`GestureHandler.swift:189-251`) 의 3-state 로직을 그대로 이식:

```
case .closed:
  hoverZone.contains → vm.hover()       // → .hovering, 패널은 안 열림
case .hovering:
  expandZone (notch body only) dwell → vm.open()
  !hoverZone → vm.close()
case .open:
  !panelZone → vm.close()
```

핵심: `expandZone` 은 notch 본체만, **wing 은 포함하지 않는다**. Wing 위에서 dwell 해도 패널은 안 열림 — 사용자가 컨트롤을 클릭하려는 의도이므로.

mangtch-new 의 현재 구현 (`GestureHandler.swift:198-227`) 은 이미 `notchZone` 과 `hoverZone` 을 분리해 갖고 있으므로 한 단계만 추가하면 됨.

#### Step 4. `MusicCompactInfo` 를 ZStack 호버-스왑으로

Mangtch `NowPlayingView.swift:16-46` 패턴을 그대로 적용:

```swift
struct MusicCompactInfo: View {
    @ObservedObject private var music = MusicManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        let isHovering = vm.hoveredWing == .right    // or .left if 좌측 컨벤션 따름
        ZStack {
            trackInfoView
                .opacity(isHovering ? 0 : 1)
                .allowsHitTesting(!isHovering)
            transportControls
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
        }
        .animation(.easeInOut(duration: 0.18), value: isHovering)
    }
}
```

두 레이어를 항상 마운트한 채 opacity+hit-test 만 토글 — `.nonactivatingPanel` 에서
SwiftUI Button 트래킹이 mount/unmount 사이에 끊기는 문제 (Mangtch 코멘트
`NowPlayingView.swift:18-22`) 회피.

#### Step 5. 좌/우 컨벤션 결정

Mangtch 는 **좌측** = 앨범아트+호버컨트롤, **우측** = 텍스트.
mangtch-new 는 **좌측** = 앨범아트, **우측** = 텍스트+컨트롤.

선택지:
- (A) Mangtch 컨벤션으로 회귀 — 컨트롤을 좌측으로 옮김. 이력적 일관성.
- (B) mangtch-new 의 좌/우는 유지하되 컨트롤만 호버-게이팅. 변경 최소.

사용자 선호에 따라 결정. 본 문서는 일단 **B** 를 디폴트로 가정 — 우측 wing 의
컨트롤이 호버시에만 노출되고, 평상시엔 title/artist 만 보임.

#### Step 6. `KBOWidget.makeRightWingView` / `TimerWidget` 도 동일 패턴 적용 가능성 확인

KBO 의 ticker/TTS 토글 (`KBOWidget` 안의 `wingHitZone(.kboTickerToggle)` /
`.kboTTSToggle` — `GestureHandler.swift:262-271` dispatch) 도 호버시에만
노출하도록 통일. 현재 노출 정책은 `KBOWidget` 코드 직접 확인 후 결정.

#### Step 7. 검증

- 빌드 → 설치 → 수동 QA: 호버 시 컨트롤 fade-in, 클릭 작동, 패널은 안 열림. Notch
  본체에서 dwell 시 (기본 0.3s) 패널 expand. wing 위 dwell 은 패널 안 열어야 함.
- `Defaults[.debugOverlay]` 도입 검토 — Mangtch 의 zone visualization 은
  3-state 게이팅 디버깅에 매우 유용했음. 별도 PR 가능.

#### Step 8. 회귀 체크

- KBO 위젯의 `wingPriority` 결정 — 현재 `wingOwnerID` 가 `notchState` 분기를
  타지 않는지 (`BoringViewModel.swift:79`) 재검토. `.hovering` 이 추가되어도
  owner 결정 로직은 동일해야 함.
- `effectiveTotalHeight`, `effectiveExpandedHeight` 의 `.hovering` 시 0
  반환 보장 — 패널이 안 열려야 하므로.
- NSPanel `setFrame` 애니메이션 (BoringNotchWindow.resizeWindow) 의 `.hovering`
  처리 — 폭/높이 변동 없어야 함.

### 3.4 추정 작업량

- B 안 풀 구현: 0.5 일 (코딩) + 0.5 일 (수동 QA + 회귀)
- A 안 미니멀: 30 분

---

## 4. 그 외 갭

### 4.1 Music wing 의 `AudioVisualizerView`

Mangtch 좌측 wing 은 재생 중 앨범아트 옆에 막대 비주얼라이저를 보여줌
(`NowPlayingView.swift:25-29`). mangtch-new 의 `MusicCompactArtwork` 는
앨범아트 only — 재생 중 신호가 없음. boring.notch `MusicVisualizer.swift`
가 있으니 wing 사이즈에 맞게 스케일해서 끼워 넣으면 됨. 작업량 ~20 LOC.

### 4.2 가사 fetch 경로 부재

`MusicExpandedView.LyricsPanel` (`MusicPlayerWidget.swift:175-275`) 이
`MusicManager.shared.syncedLyrics` 를 표시하지만 `MusicManager` 에는 fetch
구현이 보이지 않음 — `isFetchingLyrics`/`syncedLyrics` 필드만 존재.

룰 §1 은 LRCLIB/NetEase **의도적 드롭** 으로 명시. 의미는:
- (a) UI 만 두고 실제로는 영원히 빈 패널 → 제거가 깔끔.
- (b) MusicManager 에 fetch 를 채워넣되, 직접 호출 대신 `MediaController` 가
  제공하는 metadata 만 사용.

현재 코드는 (a) 의 좀비 UI 상태. **결정 필요**: LyricsPanel 자체를 제거하거나,
fetch 를 살릴지. 룰 §1 을 엄격히 따르면 LyricsPanel 코드 삭제가 정답.

### 4.3 트랙 변경 알림 (`trackChangeNotificationOverlay`)

Mangtch `NotchContentView.swift:415-472` — 곡 바뀔 때 패널이 안 열려있어도
앨범아트+제목 batch 가 노치 아래로 슬라이드 인. 사용자가 "지금 무슨 곡 시작됐지" 를
힐끗 볼 수 있는 핵심 UX. mangtch-new 에 없음.

`MusicManager.shared` 의 `nowPlaying`/`songTitle` 변화 publisher 에 sink 를
달아 ContentView 의 ZStack 최상단에 띄우면 됨. 작업량 ~80 LOC.

### 4.4 FileShelf 위젯 미등록

mangtch-new 는 boring.notch 의 `Shelf/` 시리즈를 그대로 갖고 있으나
`WidgetRegistry.registerDefaults()` 에는 미등록. Mangtch 는 `FileShelfWidget`
을 위젯으로 등록해 wing-drop → 자동 expand 등을 구현. 룰 §1 로 보면 boring.notch
의 Shelf 가 이미 있으니 신규 위젯이 아니라 기존을 위젯 어댑터로 감싸면 됨.

이건 별 PR 거리 — 본 마이그레이션 스코프 밖이지만 추적할 가치 있음.

### 4.5 HUD 위젯 / Debug 오버레이

Mangtch 의 `Defaults[.debugOverlay]` (zone 시각화) 와 HUD 슬롯
(`NotchContentView.swift:401-410`) 은 mangtch-new 에 없음. HUD 는
boring.notch 의 `OpenNotchHUD` / `InlineHUD` 가 phase 2 에서 삭제됨 — 룰 §1 의
"HUD-replacement 제거" 정책에 부합. Debug 오버레이는 §3 작업 시 같이 부활시키면 좋음.

### 4.6 그 외 사소한 갭

- `extensions/View+PanGesture.swift` (Mangtch) vs `extensions/PanGesture.swift` (mangtch-new) — API 시그니처 차이만 존재 (`axis:` vs `direction:`). 동등 기능.
- `helpers/` 디렉토리 — Mangtch 는 빈 듯, mangtch-new 는 boring.notch helpers 다수. 동등.

---

## 5. 권장 작업 순서

1. **§3 호버-컨트롤 (B 안)** — 본 문서의 핵심 요청. 0.5 일.
2. **§4.1 Visualizer 좌측 wing** — 20 LOC, 같은 PR 에 묶어도 됨.
3. **§4.3 트랙 변경 알림 오버레이** — 별 PR. ~80 LOC.
4. **§4.2 LyricsPanel 의 거취 결정** — 사용자 결정 필요. 코드 삭제 vs fetch 부활.
5. **§4.4 FileShelf 위젯 어댑터** — 별 PR. 본 마이그레이션 스코프 밖.

§3 작업이 끝나면 wing 동작은 Mangtch 와 사용자 관점에서 동등해진다. §4
나머지는 미감/완성도 항목.

---

## 6. 검증 체크리스트 (§3 마무리 시)

- [x] hover 시: 우측 wing 의 title/artist 가 prev/play/next 로 fade — 0.18s
- [x] hover 시: 패널은 **안** 열린다 (closed → hovering, 폭 그대로)
- [x] notch 본체 dwell (`Defaults[.minimumHoverDuration]`) → 패널 open
- [x] wing 위 dwell → 패널 안 열림 (사용자가 컨트롤 누르려는 의도)
- [x] hover 영역 이탈 → closed (단, `.open` → close 는 0.5s grace — §7.2 참고)
- [x] play/pause 클릭 → 한번에 동작 (mouseDown 트래킹 끊김 없음)
- [x] 재생 중 좌측 wing 에 visualizer 노출 (§4.1 — `AudioSpectrumView` 14×12)
- [x] 트랙 변경 시 wing 폭 일시 확장 → 3초 후 복귀 (§4.3 — `previewPanelWidth` text-fit)
- [x] 매우 긴 제목/아티스트 노치 침범 없음 — `metrics.wingWidth` 기반 finite frame + tail 트렁케이션
- [x] Timer compact wing 절반 (340pt closed / 640pt open) — 평상시 메뉴바 점유 줄임
- [x] 멀티 디스플레이: 각 패널 hoveredWing 독립
- [x] KBO 가 wing 을 가져갈 때 (live game) 도 호버 컨트롤 분기 정상
- [x] `xcodebuild` 통과, ad-hoc 사인 + `/Applications/Mangtch-new.app` 재설치

---

## 7. 진행 상황 (Handoff — 2026-05-08, 2nd pass)

### 7.1 완료

- **§3 B 안 풀 구현** — `008f38a feat(mangtch-new): wing hover-controls via .hovering intermediate state` (8 files, +459/-41)
  - `NotchState.hovering` 추가 + `BoringViewModel.hover()` 메소드 (`.open` 데모트 가드 포함)
  - `PanelLayoutMetrics.resolve` 의 `state` 3-갈래 처리 (`.closed`/`.hovering`→ideal, `.open`→max)
  - `GestureHandler.handleMouseMoved` 3-state 재구성: `.closed`→`hover()`, `.hovering` 에서 notch 본체 dwell 시 `open()`, wing dwell 은 무시
  - `MusicCompactInfo` ZStack 호버-스왑 (opacity + `allowsHitTesting`, 0.18s easeInOut)
  - 기존 `notchState == .open` 분기 의미 단위 재라우팅 (ContentView drop targeting, boringNotchApp togglePopover/screen-reset)

- **(보너스) `AppDelegate.shared` 캐스트 픽스** — `§3` 빌드 후 검증 중 발견. SwiftUI 의 `@NSApplicationDelegateAdaptor` 가 `SwiftUI.AppDelegate` 래퍼를 `NSApplication.shared.delegate` 로 설치 → 기존 `delegate as? AppDelegate` 가 항상 nil → `viewModel(under:)` 가 nil 을 반환 → `hoveredWing` 업데이트 자체가 차단되던 잠재 버그. `AppDelegate.shared` weak singleton 으로 우회.

- **(추가 결정) `.open` → close 0.5s grace period** — `3bf4a86 feat(mangtch-new): 0.5s grace period before .open auto-close`. 짧은 cursor 이탈에 패널이 즉시 닫히던 동작이 거슬려 grace 도입. `.hovering` 은 즉시 close 유지 (transient 상태).

- **§4.1 좌측 wing AudioVisualizer 부활 + wing 정렬 정리** — `MusicCompactArtwork` 에 `if music.isPlaying { AudioSpectrumView }` 추가 (boring.notch 기존 4-bar 14×12 재사용). 같은 PR 에서 좌측 wing 의 horizontal padding 누락 픽스(앨범아트가 끝에 붙던 기존 이슈), 우측 wing `trackInfoView`/`transportControls` `.trailing` 정렬 통일. (`92332bb`)

- **§4.3 트랙 변경 시 wing-width preview** — Mangtch `previewWingWidth` 패턴 그대로 포팅. `eac7fda feat(mangtch-new): §4.3 wing-width preview on track change`.
  - **컨셉 변경 이력**: 첫 시도(`c8a6e57` → `eec711d` revert)는 노치 아래로 56pt 배너 슬라이드 다운. 사용자 결정으로 wing 폭 절반 + 트랙 변경 시 일시 확장 패턴으로 재설계.
  - `MusicLayoutTokens.compactWidth: 480 → 325`, `compactMinWidth: 380 → 285`. `LayoutTokens.minWingWidth: 130 → 50` (chrome 글로벌 floor — KBO/Timer 의 `widthRange.min` 가 훨씬 위라 영향 없음).
  - `PanelLayoutMetrics.resolve` 시그니처에 `previewPanelWidth: CGFloat?` 추가 — `.closed/.hovering` 의 widthTarget 을 `previewPanelWidth ?? widthR.ideal` 로.
  - `BoringViewModel.previewPanelWidth` + `setupTrackChangeObserver` (sink on `MusicManager.shared.$songTitle`). 첫 로드/같은 제목/`.closed` 아닌 상태/sourceID ≠ "music-player" 모두 가드.
  - `computeTrackChangePreviewPanelWidth(title:artist:)` — 11pt semibold 제목 + 10pt 아티스트 측정 → 더 큰 쪽 + `2*compactHorizontalPadding + 4` 헤드룸 → `notch + 2*textWingW`. floor=compactWidth, ceil=expandedWidth(640) — open-panel cap 과 동일.
  - 3초 후 `previewPanelWidth = nil`. 기존 `m.panelWidth` 0.22s easeInOut 이 그대로 늘어남/줄어듬.

- **(보너스) wing 텍스트 trailing-overflow 픽스** — `8ef6166 fix(mangtch-new): clamp wing text width + halve Timer compact wing`. `.frame(maxWidth: .infinity)` 만으로는 SwiftUI Text 가 finite 폭 제약 받지 않아 intrinsic 으로 렌더 → 노치 chamber 까지 침범. `MusicCompactInfo.trackInfoView` 에서 `notchVM.metrics.wingWidth` 직접 읽어 `textBudget` 계산, `.frame(maxWidth: textBudget, alignment: .trailing)` 의 finite cap 부과. `.lineLimit(1) + .truncationMode(.tail)` 가 그제서야 동작.

- **(보너스) Timer compact wing 절반** — 같은 커밋. `TimerWidget.widthRange` 를 `.fixed(640)` → `WidthRange(min: 285, ideal: 340, max: 640)` 로 전환. Timer 가 wings 를 가져가도 (countdown 진행 중) 평상시엔 좁은 wing, 패널 열리면 640 캔버스. `TimerLayoutTokens.compactWidth=340/compactMinWidth=285` 추가.

- **§4.3 후속 — Music wing hover-width 부스트** — `390d3cb fix(mangtch-new): widen wing on right-hover so transport controls fit`. §4.3 에서 compactWidth 480→325 로 줄인 결과, wing ≈ 62pt 로는 transport 버튼 (3×22 + 2×6 + 2×8 = 94pt) 이 안 들어가 호버 스왑 후에도 사실상 클릭 불가능. `MusicLayoutTokens.hoverWidth = 420` (wing ≈ 110pt) 추가, `BoringViewModel.metrics` 의 hover-boost 분기에서 `hoveredWing == .right && wingOwnerID == "music-player" && notchState != .open` 일 때 `previewPanelWidth` 슬롯에 주입. 트랙 변경 preview 와 hover 가 동시에 활성이면 `max()` 로 큰 쪽이 이김. `setupMetricsTracking` 의 `combineLatest` 체인에 `$hoveredWing` 추가 (3 → 4 publisher).

- **§4.5 Debug zone overlay** — `b9bf1d9 feat(mangtch-new): §4.5 debug zone overlay`. `Defaults[.debugOverlay]` 토글로 4 색 정적 zone (yellow=hover / cyan=L wing / purple=R wing / green=notch) + 오렌지 wing-button hit zones 시각화. ContentView 의 `wingsRow` 위에 overlay. 윈도우가 panelWidth × (notchHeight + extraOpen) 로 사이즈되어 정적 4 rect 는 윈도우-로컬 좌표로 1:1 매핑, hit zones 만 host window frame 으로 screen→local 변환. `notchState == .closed` 에서는 오렌지 미렌더 (compact 에서 버튼이 opacity 0 인 layered 상태 — 보여줘봐야 클릭 안 되는 영역만 표시됨). Settings → General → Notch behavior 에 토글.

- **§7.2 Spotify 하트 (Liked Songs)** — `4b122cb feat(mangtch-new): §7.2 Spotify 하트 — Web API PKCE + NowPlaying 분기`. Mangtch `Sources/SystemBridge/Spotify/SpotifyAPI.swift` + PKCE OAuth 플로우 포팅. `NowPlayingController` 와 `SpotifyController` 두 경로 모두 분기 — bundleIdentifier == `com.spotify.client` 또는 controller 가 SpotifyController 일 때 `SpotifyAuth.isAuthorized` 체크 후 `MusicManager.canFavoriteTrack` 게이팅. trackID 는 AppleScript `id of current track` → `SpotifyTrackID.extract(from:)` 로 3 가지 입력 형태 처리. `/me/tracks/contains` + `PUT/DELETE /me/tracks` 호출, 60s 캐시 (rate-limit 회피). setLiked 성공 시 캐시도 같이 갱신해 UI 라운드트립 없이 즉시 반영. SpotifyController 의 후속 emit 패턴: updatePlaybackInfo 가 메인 state 푸시 후 likedFetchTask 비동기로 isFavorite 추가 emit, 트랙 변경 사이 race 가드 (`currentTrackID == trackID`). Keychain 네임스페이스 `com.yojeong.mangtch.spotify` — Mangtch 와 공유 (동일 OAuth 앱, redirect `mangtch://spotify-callback`). Settings → Media → Spotify 에서 Client ID 입력.

- **§7.2 가사 — LRCLIB + NetEase 폴백** — `7860b33 feat(mangtch-new): §7.2 가사 — LRCLIBService 액터 + NetEase 폴백`. `MusicManager.fetchLyricsFromWeb` 의 인라인 LRCLIB 호출 + 자체 LRC 파서 제거, Mangtch `LRCLIBService` (actor) + `NetEaseLyricsService` (actor) + `LRCParser` 포팅해 `mangtch-new/boringNotch/SystemBridge/Lyrics/` 신설. fetch 체인: LRCLIB `/api/get` (정확 매칭, duration+album 사용) → LRCLIB `/api/search` (relaxed) → NetEase `music.163.com/api/search/get` + `/api/song/lyric`. NetEase 응답은 script-mix 게이팅 (한글/카나/한자 + 라틴 letter 비율) 으로 K-pop/J-pop 트랙에 중국어 번역본 매칭 차단. 둘 다 액터 + 10분 negative-cache. `syncedLyrics` 의 published 타입은 기존 `[(time: Double, text: String)]` 유지, `LRCLine` 에서 변환. 룰 §1 의 "LRCLIB/NetEase 드롭" 명시는 사용자 결정으로 오버라이드.

### 7.2 잔여 작업 (우선순위 順)

§4 잔여 항목들은 본 마이그레이션의 핵심 wing-hover 동작과 독립된 미감/완성도 작업이다.

| 우선 | 항목 | 출처 | 규모 | 비고 |
|---|---|---|---|---|
| ~~1~~ | ~~좌측 wing AudioVisualizer 부활~~ | §4.1 | done | `92332bb`. `AudioSpectrumView` 4-bar 14×12 + 좌/우 wing 정렬 정리. |
| ~~2~~ | ~~트랙 변경 알림~~ | §4.3 | done | `eac7fda` (구현체) + `8ef6166` (텍스트 clamp + Timer wing 절반). 배너 안 띄우고 wing 폭 일시 확장 — Mangtch `previewWingWidth` 패턴. 자세한 내용은 §7.1 참고. |
| ~~1~~ | ~~LyricsPanel 거취 결정~~ | §4.2 | done | `7860b33 feat(mangtch-new): §7.2 가사 — LRCLIBService 액터 + NetEase 폴백`. 인라인 LRCLIB 호출을 actor 기반 `LRCLIBService` 로 교체, 미스 시 `NetEaseLyricsService` 로 폴백 (K-pop/CJK 커버리지). NetEase 응답은 script-mix 게이팅으로 잘못된 언어 가사 차단. 룰 §1 의 "LRCLIB/NetEase 드롭" 항목은 사용자 결정으로 오버라이드. |
| ~~2~~ | ~~Spotify 하트(Liked Songs) 거취 결정~~ | 신규 | done | `4b122cb feat(mangtch-new): §7.2 Spotify 하트 — Web API PKCE + NowPlaying 분기`. PKCE OAuth + `/me/tracks` API 포팅. NowPlayingController/SpotifyController 둘 다 분기. Settings → Media → Spotify 에서 Client ID 입력. |
| 3 | FileShelf 위젯 어댑터 | §4.4 | TBD | boring.notch `Shelf*` 시리즈를 `NotchWidget` 으로 감싸 `WidgetRegistry` 에 등록. 본 마이그레이션 스코프 밖이지만 추적 가치 있음. |
| ~~3~~ | ~~Debug 오버레이 (zone 시각화)~~ | §4.5 | done | `b9bf1d9`. 4 색 정적 zone + 오렌지 wing-button hit zones. Settings → General → Notch behavior → "Debug zone overlay" 토글. `.closed` 에서는 오렌지 미렌더. 자세한 내용은 §7.1 참고. |
| 4 | (옵션) 매우 긴 제목 marquee | §4.3 후속 | ~30 LOC | 현재 preview cap=640pt(=open-panel max). 제목+아티스트가 그 이상 필요해도 cap 에서 막혀 잘림 — 사용자 동의(8ef6166 직후). 더 길게 보여주고 싶으면 (a) cap 상향 또는 (b) cap 닿은 상태에서 boring.notch `MarqueeTextView` 로 scroll fallback. |

### 7.3 다음 작업자에게

- **상태머신 컨벤션** — `.closed/.hovering/.open` 셋만 존재. 새 코드에서 `notchState ==` 분기 추가 시 의미 단위로 셋 다 고려: 패널 폭 기준이면 `.open` 만, hit-testing 이면 `.open` 만, wing 컨텐츠 노출이면 `!= .closed`, hover 영역 유지면 `!= .closed`. fallback `!= .closed` / `!= .open` 한 줄 swap 으로 퉁치지 말 것 — §3.3 Step 1 참고.

- **AnyView 캐싱과 `@EnvironmentObject`** — `AnyNotchWidget.{leftWingView,rightWingView}` 가 위젯 등록 시 한 번 만들어져 영구 보관됨. 그 안에 `@EnvironmentObject` 가 들어 있어도 SwiftUI 트리 재구축에서 정상 반응함이 검증됨 (`MusicCompactInfo` body re-eval 확인). 새 위젯 작성 시 동일 패턴 OK.

- **NSPanel + SwiftUI Button 트래킹** — `.nonactivatingPanel` 환경에서 SwiftUI `Button` mouseDown↔mouseUp 트래킹은 view tree 재구축에 취약. 호버 swap UI 작성 시 `if/else` 로 갈아치우지 말고 ZStack opacity + `allowsHitTesting` 조합 사용. `MusicCompactInfo` / `KBOCompactView` 가 같은 패턴.

- **GlobalMonitor 권한** — `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` 는 macOS Accessibility 권한 필요. ad-hoc 재사인할 때마다 designated requirement 가 갱신되어 TCC 권한이 silently 무효화되는 케이스 있음. `globalMonitor=ok` 로깅됐는데 mouseMoved 이벤트 0건이면 권한 문제 의심 — System Settings → Privacy & Security → Accessibility 에서 토글 OFF→ON.

- **검증 절차** — `§0` (HANDOFF.md) 의 ad-hoc 사인 흐름 그대로. 빌드 후 `Frameworks/*` + `.app` 재사인 → `/Applications/Mangtch-new.app` 갈아치우고 `open`. 직접 binary 실행보다 `open` 이 LaunchServices 등록 + 권한 컨텍스트 제대로 잡힘.

- **SwiftUI Text + finite frame** — `.frame(maxWidth: .infinity)` 는 Text 에 finite 폭 제약을 **전파하지 않음**. trailing 정렬 + intrinsic 폭이 부모보다 크면 트레일링 앵커는 부모 끝, leading 쪽으로 오버플로우 → 인접 영역 침범. 해결: 부모의 실제 폭(`vm.metrics.wingWidth` 등)을 직접 읽어 `.frame(maxWidth: budget)` 로 finite cap. `.lineLimit(1) + .truncationMode(.tail)` 는 finite 제약이 있어야 트리거됨. 참고: `MusicCompactInfo.trackInfoView`.

- **§4.3 wing-width preview 의 게이팅** — `previewPanelWidth` 는 `metrics` 안에서 sourceID 가 `"music-player"` 일 때만 `resolve` 에 전달됨. KBO/Timer 가 wing 가져갔을 때 트랙이 바뀌어도 wing 폭 안 흔들림. 새 위젯이 비슷한 preview 동작 필요하면 `metrics` accessor 의 게이팅 분기 추가.

- **resize pipeline 의 publisher 체인** — `BoringViewModel.setupMetricsTracking` 의 `combineLatest` 에 새로운 입력 추가 시 `.sink` 의 튜플 패턴도 같이 고침 (현재 4-tuple — `390d3cb` 에서 `$hoveredWing` 추가). `boringNotchApp.swift` 의 `resolvedFrame` 체인은 내부적으로 `compactMap`/`combineLatest` 로 `ResolvedFrame` 만드는데, Swift 타입 추론 폭주 방지 위해 명명된 struct 로 풀어둠 — 새 입력은 두 번째 `combineLatest` 로 묶고 mapper 에서 풀기 (배너 시도 시도했던 패턴 — 결국 revert 했지만 패턴은 참고용).

- **compactWidth 와 wing 컨텐츠 폭의 트레이드오프** — `390d3cb` 에서 보듯 compactWidth 를 줄이면 wing 가 narrow 해져서 transport 류 컨텐츠가 안 들어감. 새 위젯이 hover-스왑 패턴으로 wing 에 control 띄울 때, **`(compactWidth - notchWidth)/2` 가 control 폭보다 작으면 hover-width 부스트가 필요**. 현재 패턴: 위젯 별 `hoverWidth` 토큰 + `BoringViewModel.metrics` 의 hover-boost 분기 (`hoveredWing` + `wingOwnerID` 게이팅) → `previewPanelWidth` 슬롯에 주입 → `max()` 로 다른 boost 와 합쳐짐. KBO 도 hover-스왑 (ticker/TTS toggle) 이라 비슷한 폭 부스트가 필요할 수 있는데, 현재 KBO compact 는 280+ 폭이라 아슬아슬 — 뭔가 안 클릭되면 여기 의심.

- **SourceKit `No such module 'Defaults'` 등 false positive** — Xcode 가 SwiftPM 패키지 resolve 안 한 상태에서 신규/수정 파일에 대해 빈번히 발생. `xcodebuild` 가 통과하면 무시. HANDOFF §3 에도 명시. SourceKit 만 보고 코드 수정하지 말 것.

- **트랙 변경 시뮬레이션** — 실제 곡 바뀌는 거 기다리기 귀찮으면 `MusicManager.shared.songTitle` 에 직접 다른 값 할당해도 publisher 가 fire 함 (테스트 한정). 평상시는 `nowPlayingObserver` 가 자동 갱신.

- **Debug zone overlay 켜기** — `b9bf1d9` 의 §4.5 도구. Settings → General → Notch behavior → "Debug zone overlay" 토글. wing/notch 클릭 안 됨, hover 영역 안 잡힘, hit zone 어긋남 류 디버깅에 필수. 4 색 정적 zone 은 metrics-driven 이라 panelWidth/wingWidth 가 의도대로 변하는지 즉시 보임 (트랙 변경 preview, hover-boost 둘 다 시각 검증 가능). 오렌지 hit zone 은 PreferenceKey 리포트 결과 — wing 컨텐츠 layout 이 클릭 영역과 어긋나면 여기서 잡힘. `.closed` 에선 오렌지 안 그림 (compact 에서 invisible 한 버튼 영역까지 표시하면 노이즈) — hover 한 번 거쳐서 봐야 함.
