# mangtch-new — 단계 5: 콘텐츠 주도 sizing + 실제 NSPanel resize

> **역할**: 이 문서는 **착수자(FE)**용입니다. 작성자(Claude)는 **검토만** 합니다.
> **선행**: 단계 1–4 완료. base 커밋 = `dfca2e4`.
> **선행 문서**: `HANDOFF.md` §1, `PLAN-layout-refactor.md` (전 단계의 contract 이해)
> **브랜치**: `mangtch-new-wip` 분기. 단계 분할은 §3 참조.

---

## 진행 상태 (2026-05-07)

`mangtch-new-wip` 위에 다음이 머지됨:

| Sub | 상태 | 커밋 |
|---|---|---|
| **5a** sizing contract 콘텐츠 주도화 | ✅ done | `578d715` |
| **5b** NSPanel resize 와이어링 | ⚠️ partial | `dad25a1` |
| **5c** ScrollView fallback + 화면 안전 영역 | ⏳ not started | — |
| **5d** wing 콘텐츠 swap 플리커 (신규) | ⏳ FE 인수 | `69cac3b` |

### 5b 실제 적용된 결정 (플랜과 차이)

플랜이 가정한 "콘텐츠 주도 width + height"가 wing/패널 사이즈 변화 시
시각 회귀를 발생시킴 → 절충안으로 다음 채택:

1. **width는 모든 위젯에서 `WidthRange.fixed(LayoutTokens.panelMaxWidth)` (640pt) 로 고정**.
   KBO/Timer의 동적 widthRange 산식 (starter slot 등)은 제거.
   - 이유: window의 NSAnimation과 SwiftUI 내부의 wing-frame ease가 서로 다른
     curve로 돌면서 "바깥부터 채워지는" wobble 발생. width 변동을 없애면 문제 자체가 소거됨.
   - 부작용: KBO 게임이 적은 날의 패널이 항상 640pt 캔버스로 렌더 — 콘텐츠가
     가운데에 떠 보일 수 있음 (현재까지는 시각 OK).

2. **height만 NSPanel resize**. `BoringNotchWindow.resizeWindow(metrics:notchHeight:isOpen:animated:)`
   가 isOpen 분기에 따라 `notchH+content+chrome+shadow` 또는 `notchH+shadow`로
   setFrame. width는 항상 `LayoutTokens.panelMaxWidth`.

3. **metrics 변화 추적은 `withObservationTracking` 재무장 + Combine 혼합**.
   `BoringViewModel.publishedMetrics` (@Published) 로 publish. 플랜 §5.2에
   적힌 per-widget `sizeDidChange: AnyPublisher` 프로토콜은 채택 안 함 —
   `withObservationTracking`이 모든 @Observable 위젯 상태를 자동으로 잡아서
   protocol 추가 없이 동작.

4. **`WidgetRegistry.activateAll()`** 을 `applicationDidFinishLaunching` 끝에
   호출. KBO `startMonitoring`이 앱 시작 시점에 fetch를 트리거함 (이전엔 사용자가
   날짜 이동을 해야 fetch가 돌았음 — 첫 패널 오픈 시 "경기 없음" 오인 발생).

### 5b 미해결 (5c와 별개로 5d로 분리)

**wing 콘텐츠 swap 플리커**: 위젯 스위처 클릭으로 `currentExpandedWidgetID`가
바뀌면 `leftWingContent = widget.makeCompactView()`가 구조적으로 완전히 다른
view tree를 반환 → SwiftUI는 `.transition(.opacity)` (crossfade) 또는 snap만
가능. 둘 다 사용자에게 "깜빡임"으로 보임.

Mangtch (legacy) 패턴 — wing은 "live content를 가진 위젯"만 takeover —
을 mangtch-new에 옮김 (`hasWingContent` 게이트 + `.transition(.opacity)`,
커밋 `69cac3b`). 이로써 위젯 스위처를 토글해도 KBO 라이브 게임/비-오늘
탐색 / Timer 동작 중일 때만 wing 식별이 변함. **하지만 wing 식별이 실제로
바뀌는 순간엔 여전히 crossfade/snap 한쪽이 발생** → 사용자가 "fade가 아니라
투명도는 유지해야지" 라고 명시적으로 거부.

### 5d — 다음 착수자가 풀어야 할 문제

**문제**: 위젯 간 compact view가 view tree를 공유하지 않아서 SwiftUI가
부드럽게 morph하지 못함.

**근본 해결책 후보 (큰 리팩터)**:
- `NotchWidget` 프로토콜에서 `makeCompactView()` 반환 타입을 `AnyView`에서
  semantic slot 데이터로 바꿈. 예:
  ```swift
  struct WingCompactDescriptor {
      let leadingIcon: WingIcon         // 색/모양 데이터, view 아님
      let primaryLabel: String?
      let badge: WingBadge?
      let trailingControls: [WingControl]
  }
  protocol NotchWidget {
      var compactDescriptor: WingCompactDescriptor { get }
      ...
  }
  ```
- `ContentView`가 단일 stable HStack 안에서 descriptor 데이터를 채움.
  SwiftUI는 같은 view tree에서 값만 변하는 거라 frame을 자연스럽게 morph.
- 비용: Music/KBO/Timer compact view를 데이터 모델로 분해 + 렌더링 로직을
  ContentView 또는 공용 wing-renderer에 통합. 4–6h 리팩터 + 시각 회귀 검증.

**대안 (작은 변경)**:
- wing 콘텐츠를 영원히 Music album art로 고정. KBO/Timer 라이브 takeover
  로직 모두 제거. upstream boring.notch와 동일.
- 비용 적음. 단점: "다른 날 KBO 보는 중" / "Timer 카운트다운 중" 시각 신호가
  wing에서 사라짐.

플랜 작성자 (검토자) 권장: **5d 리팩터 (semantic slot)** — 한 번 큰 작업으로
플리커도 풀고 향후 위젯 추가도 깔끔해짐. 즉시 ship이 우선이라면 대안 채택.

---

## 0. 왜 (1분)

지금 `.open` 패널은 항상 640×190 (Music 픽셀 디자인 캔버스)로 강제 스냅됩니다. 이건 chrome 이 특정 위젯(Music)에 오염된 형태로, KBO 5경기·linescore 펼침이 들어가면 잘립니다. 단계 5는 sizing 책임을 **콘텐츠 주도**로 뒤집고, NSPanel 자체를 metrics 에 따라 실제로 resize 합니다. Music 의 640×190 은 Music 위젯 본인이 `fixed` 로 선언.

---

## 1. 사용자 결정 사항 (확정 — 변경 금지)

1. **Width 정책**: 콘텐츠 주도. `widthRange.ideal` 사용. 위젯 전환 시 wing 폭 변화 허용, 애니메이션으로 흡수.
2. **윈도우 전략**: NSPanel 자체를 resize. 큰 투명 hit-zone 방안은 채택 안 함 (Space 전환 / focus / hover capture 디버깅 비용 우려).
3. **`LayoutTokens.openCanvasHeight/Width` 처분**: 전역에서 삭제. `MusicLayoutTokens.expandedWidth/Height` 로 이전 (Music 소유 의미 명시).

---

## 2. 범위

### In scope
- `LayoutTokens` 에서 `openCanvasWidth/Height` 제거
- `MusicLayoutTokens.swift` 신규 — Music 자기 캔버스 선언
- `WidthRange/HeightRange` ergonomics — `.fixed(_)` static factory
- `PanelLayoutMetrics.resolve` — `.open` 분기에서 캔버스 스냅 제거, 단일 path 로 통합 (콘텐츠 주도 + clamp)
- `NotchWidget` 3개 (Music/KBO/Timer) range 재선언
- NSPanel resize: `BoringViewModel.metrics` 변화 → `window.setContentSize` + top-anchor 유지 `setFrameOrigin`
- KBO ScrollView fallback (max 초과 시)
- 화면 안전 영역 max — `heightRange.max` 가 화면 절반 정도로 자동 클램프
- 애니메이션: panel resize 부드럽게 (`setFrame:display:animate:` 또는 SwiftUI animation hook)

### Out of scope
- 폰트/컬러/Theme 토큰화
- 위젯 추가/제거 UI
- KBOExpandedView 의 view 구조 자체 리팩터 (ScrollView 외 변경 X)

### 절대 금지
- `boring.notch` 자산 직접 수정 (NotchHomeView, MusicPlayerView, AlbumArtView)
- BC shim 잔존
- Music 시각 회귀 (지금 보이는 모습과 픽셀 동일해야 함)

---

## 3. 단계 분할 (PR 3개 권장)

| Sub | 작업 | 위험도 |
|---|---|---|
| **5a** | `LayoutTokens` cleanup + `MusicLayoutTokens` + `WidthRange.fixed(_)` factory + `PanelLayoutMetrics` 단일 path | 중. metrics 동작 변화 |
| **5b** | NSPanel resize 와이어링 (window.setContentSize + top-anchor + 애니메이션) | 중–높. 멀티 디스플레이 / Space 전환 검증 필요 |
| **5c** | KBO ScrollView fallback + heightRange.max 화면 안전 영역 클램프 | 낮. 격리된 변경 |

각 sub 후 빌드 + 시각 검증.

---

## 4. 단계 5a — sizing contract 콘텐츠 주도화

### 4.1 `LayoutTokens` 변경

**삭제**:
```swift
static let openCanvasWidth: CGFloat = 640
static let openCanvasHeight: CGFloat = 190
```

`shadowPadding`, `chromeTopHeight`, `wingTopOuterRadius`, `panelCornerRadius`, `minWingWidth`, `absoluteMaxWingWidth` 등 chrome 공유 상수는 **유지**.

`absoluteMaxWingWidth` 도 재고: 지금 480pt 캡인데 콘텐츠 주도로 가면 KBO/Music 모두 640까지 갈 수 있음. **유지하되 의미 재정의**: "단일 화면에서 패널이 차지할 수 있는 wing 폭의 절대 ceiling". 값은 그대로 480 또는 화면 폭 기준 동적으로.

→ 권장: 화면 기준 동적 값.
```swift
@MainActor
static func absoluteMaxWingWidth(for screen: NSScreen?) -> CGFloat {
    let screenW = screen?.visibleFrame.width ?? 1440
    return min(480, screenW * 0.4)   // 화면이 좁아도 패널이 안 넘치도록
}
```

또는 단순히 `static let = 480` 유지하고 §5b 의 `heightRange.max` 만 화면 기반으로. **단순함을 위해 후자 권장**.

### 4.2 `MusicLayoutTokens.swift` 신규

`mangtch-new/boringNotch/components/Music/MusicLayoutTokens.swift`:

```swift
import SwiftUI

/// Music widget's pixel-design canvas. boring.notch's MusicPlayerView,
/// AlbumArtView, and MusicControlsView are pixel-laid against this exact
/// canvas — 640pt wide leaves album art + controls + lyrics panel at
/// their native proportions, 190pt tall keeps the slider/marquee row
/// from being cropped. These are NOT to be reused as global panel
/// dimensions; KBO/Timer have their own content-driven sizing.
enum MusicLayoutTokens {
    static let expandedWidth: CGFloat = 640
    static let expandedHeight: CGFloat = 190
}
```

pbxproj 등록 필수 (`PBXFileSystemSynchronizedRootGroup` 아님, `MusicPlayerWidget.swift` 엔트리 패턴 복사).

### 4.3 `WidthRange/HeightRange` 확장

`Widgets/NotchWidget.swift` 의 두 struct 에 static factory 추가:

```swift
struct WidthRange {
    let min: CGFloat
    let ideal: CGFloat
    let max: CGFloat

    static let `default` = WidthRange(min: 320, ideal: 480, max: 640)

    /// 위젯이 단일 고정 폭을 요구할 때 (Music 의 boring.notch 픽셀 캔버스).
    /// min == ideal == max 라 metrics clamp 가 사실상 no-op.
    static func fixed(_ value: CGFloat) -> WidthRange {
        WidthRange(min: value, ideal: value, max: value)
    }
}

struct HeightRange {
    let min: CGFloat
    let ideal: CGFloat
    let max: CGFloat

    static let `default` = HeightRange(min: 180, ideal: 260, max: 400)

    static func fixed(_ value: CGFloat) -> HeightRange {
        HeightRange(min: value, ideal: value, max: value)
    }
}
```

### 4.4 `PanelLayoutMetrics.resolve` 단일 path

지금 `.open` 분기에서 캔버스 스냅을 박는데, 이걸 제거하고 **closed/open 모두 widget 의 range 를 사용**합니다. 단 `.open` 에서는 `ideal` 을 따르되 `[min, max]` 로 클램프, `.closed` 에서는 `widthRange.ideal` 그대로 (기존 동작).

```swift
@MainActor
static func resolve(widget: (any NotchWidget)?,
                    notchSize: CGSize,
                    state: NotchState) -> PanelLayoutMetrics {
    let widthR = widget?.widthRange ?? .default
    let heightR = widget?.heightRange ?? .default

    // Width: 두 state 모두 widget-driven. .open 에서는 ideal 그대로 사용.
    // (Music 는 .fixed(640) 이라 자동으로 640 유지됨.)
    let panelW = clamp(widthR.ideal, min: widthR.min, max: widthR.max)
    let wingW = clamp((panelW - notchSize.width) / 2,
                      min: LayoutTokens.minWingWidth,
                      max: LayoutTokens.absoluteMaxWingWidth)

    // Height: .open 에서만 사용 (.closed 에서는 hit-zone 계산용으로만).
    let contentH = clamp(heightR.ideal, min: heightR.min, max: heightR.max)

    return PanelLayoutMetrics(
        closedWidth: notchSize.width + wingW * 2,
        openWidth: notchSize.width + wingW * 2,   // 동일 — width 정책 단일화
        wingWidth: wingW,
        panelWidth: notchSize.width + wingW * 2,
        contentHeight: contentH,
        chromeHeight: LayoutTokens.chromeTopHeight
    )
}
```

→ `closedWidth/openWidth` 가 같아짐. 두 이름 유지하되 의미 동일이라는 docstring 추가하거나, `panelWidth` 하나로 통합. **단순화 권장**: `closedWidth/openWidth` 필드 삭제, `panelWidth` 만 남김.

```swift
struct PanelLayoutMetrics {
    let panelWidth: CGFloat
    let wingWidth: CGFloat
    let contentHeight: CGFloat
    let chromeHeight: CGFloat
    var totalHeight: CGFloat { contentHeight + chromeHeight }
}
```

호출부 (`closedWidth/openWidth` 참조하는 코드) 모두 `panelWidth` 로 치환. grep 으로 확인.

### 4.5 위젯 3개 range 재선언

#### Music (`MusicPlayerWidget.swift`)

기존 텍스트 길이 기반 `widthRange` 산식 **삭제**. fixed canvas 로 대체:

```swift
var widthRange: WidthRange { .fixed(MusicLayoutTokens.expandedWidth) }
var heightRange: HeightRange { .fixed(MusicLayoutTokens.expandedHeight) }
```

> **주의**: 닫힘 상태에서도 wing 폭이 320pt (= (640-200)/2) 정도가 됩니다. 지금은 트랙 텍스트 길이로 동적이라 짧은 곡은 좁고 긴 곡은 넓은데, 이게 사라집니다.
> **사용자 결정 필요**: 이 변화 OK 인가? 아니면 Music 도 closed 시 동적, open 시 fixed 인가?
> 플랜 작성자 의견: **허용**. "콘텐츠 주도 + Music 은 자기 캔버스 선언" 의 정합성 유지가 더 중요. 닫힘 시 가변 폭은 단계 6 에서 별 정책으로 (예: `WidthRange` 에 `closedIdeal` 따로 추가).

#### KBO (`KBOWidget.swift`)

기존 산식 유지. 단:
- `widthRange.max` 를 `LayoutTokens.absoluteMaxWingWidth * 2 + notchSize.width` 정도로 (의미: panel 최대 폭). 단순화: `640` 또는 화면 기반 동적.
- `heightRange.max` 는 §5c 에서 화면 안전 영역으로 갈음.

#### Timer (`TimerWidget.swift`)

기존 그대로. `panelMaxHeight = 320` 유지.

### 4.6 검증 (5a)

```bash
xcodebuild ... build 2>&1 | tail -5    # SUCCEEDED
```

수동:
- Music 패널 펼침 → 640×190 보존 (시각 회귀 0)
- KBO 패널 펼침 → **여전히 잘릴 가능성 큼** (NSPanel resize 가 5b 작업이라). 콘텐츠 frame 만 키워봤자 윈도우가 작아서 클립됨. → **5a 단독 검증은 빌드/Music 만**, KBO 검증은 5b 후로.
- Timer 패널 펼침 → Timer 콘텐츠가 190 안에 들어가면 OK, 그 이상이면 5b 후 검증.

### 4.7 커밋 (5a)

```
refactor(mangtch-new): content-driven panel sizing in PanelLayoutMetrics

Removes the .open canvas snap. Widget range is the single source of
truth for both width and height; Music declares its 640×190 canvas
via .fixed(_) factory in WidthRange/HeightRange. LayoutTokens drops
openCanvasWidth/Height; those move to MusicLayoutTokens.

Note: NSPanel window itself is not yet resized to follow metrics —
that lands in the next commit (5b). KBO/Timer expanded views still
clip until then.
```

---

## 5. 단계 5b — NSPanel resize 와이어링

### 5.1 변경 위치

- `boringNotchApp.swift` — `createBoringNotchWindow` 부근, `setFrame` 호출
- `BoringNotchWindow.swift` — resize 메서드 추가
- `BoringViewModel.swift` — metrics 변화 publish (Combine)
- `sizing/matters.swift` — `windowFrame(for:)` 시그니처 확장 또는 deprecate

### 5.2 metrics 변화 감지

`BoringViewModel.metrics` 는 computed 라 SwiftUI 는 알아서 재평가. 하지만 NSPanel 은 별도 트리거 필요.

```swift
class BoringViewModel: NSObject, ObservableObject {
    // ...
    /// Last known metrics — observers (NSPanel resize) react when this changes.
    @Published private(set) var publishedMetrics: PanelLayoutMetrics?

    /// Recompute and publish metrics. Called whenever notchState, widget
    /// selection, or active widget's range changes.
    @MainActor
    func recomputeMetrics() {
        let m = metrics  // computed
        if publishedMetrics != m {
            publishedMetrics = m
        }
    }
}
```

`PanelLayoutMetrics` 가 `Equatable` conform 필요. struct 라 `==` 자동 생성.

트리거 포인트:
- `notchState` setter
- `currentExpandedWidgetID` setter
- 위젯 자체의 변화 — KBO 의 `viewModel.games.count` / `viewingLinescore` 변화. KBO 는 `@Observable` 이라 SwiftUI 는 잡지만 BoringViewModel 은 모름. **위젯이 chrome 에게 신호 보낼 hook 필요**.

#### 위젯-chrome 신호 — `WidgetSizeChangePublisher`

```swift
protocol NotchWidget: AnyObject, Identifiable where ID == String {
    // ... 기존 멤버
    /// Emits when widthRange/heightRange would return different values.
    /// chrome subscribes and recomputes metrics. Optional — widgets with
    /// static ranges can return Empty publisher.
    var sizeDidChange: AnyPublisher<Void, Never> { get }
}

extension NotchWidget {
    var sizeDidChange: AnyPublisher<Void, Never> {
        Empty().eraseToAnyPublisher()
    }
}
```

KBO 구현:
```swift
let viewModel = KBOViewModel()
private let sizeChangeSubject = PassthroughSubject<Void, Never>()
var sizeDidChange: AnyPublisher<Void, Never> { sizeChangeSubject.eraseToAnyPublisher() }

// KBOViewModel 에 변화 hook — games.count, viewingLinescore, startingPitchers
// 변화 시 sizeChangeSubject.send() 호출. KBOViewModel 이 @Observable 이므로
// withObservationTracking 또는 명시적 didSet 으로 구독.
```

`BoringViewModel` 에서 위젯 활성화 시 구독:
```swift
private var widgetSizeCancellable: AnyCancellable?

func setActiveWidget(_ id: String) {
    currentExpandedWidgetID = id
    widgetSizeCancellable?.cancel()
    widgetSizeCancellable = WidgetRegistry.shared.widget(for: id)?.wrapped
        .sizeDidChange
        .sink { [weak self] in self?.recomputeMetrics() }
    recomputeMetrics()
}
```

### 5.3 NSPanel resize

`BoringNotchWindow` 에 메서드:

```swift
extension BoringNotchWindow {
    /// Resize while preserving top edge anchor (panel grows/shrinks
    /// downward from the notch). Animated.
    @MainActor
    func resizeContent(to size: NSSize, animated: Bool = true) {
        guard let screen = self.screen ?? NSScreen.main else { return }

        let currentFrame = self.frame
        let topY = currentFrame.maxY   // 현재 top edge

        // shadow padding 포함한 실제 window size
        let windowSize = NSSize(
            width: size.width,
            height: size.height + LayoutTokens.shadowPadding
        )

        let newOriginX = screen.frame.midX - windowSize.width / 2
        let newOriginY = topY - windowSize.height
        let newFrame = NSRect(origin: NSPoint(x: newOriginX, y: newOriginY),
                              size: windowSize)

        self.setFrame(newFrame, display: true, animate: animated)
    }
}
```

`boringNotchApp.swift` 에서 `BoringViewModel.publishedMetrics` 변화 구독:

```swift
viewModel.$publishedMetrics
    .compactMap { $0 }
    .removeDuplicates()
    .sink { [weak window] metrics in
        let notchH = viewModel.closedNotchSize.height
        let totalH = notchH + metrics.totalHeight   // notch + content + chrome
        window?.resizeContent(
            to: NSSize(width: metrics.panelWidth, height: totalH),
            animated: viewModel.notchState == .open || ...
        )
    }
    .store(in: &cancellables)
```

> **주의**: 닫힘 상태에서는 콘텐츠 영역 0 으로 줘서 wing 만 보이게. `.frame(height: vm.notchState == .open ? m.totalHeight : 0)` 가 SwiftUI 단에서 처리하는데, NSPanel 은 콘텐츠 + notch 공간 모두 가져야 함. 닫힘 시에도 `notchH + chromeOnly` 정도 두는 게 맞을지 결정. **권장**: 닫힘 시 `notchH + shadow` 만 (= 기존 동작). 펼침 시 `notchH + content + chrome + shadow`.

### 5.4 `windowFrame(for:)` 정리

함수 자체는 초기 윈도우 크기 결정 1회용으로 유지하되, 의미 명시:

```swift
/// Initial window size before any widget is active. Conservative —
/// enough to host one row of compact wings + small expanded fallback.
/// Real sizing happens via BoringNotchWindow.resizeContent once metrics
/// are available.
@MainActor
func initialWindowFrame(for screenUUID: String? = nil) -> CGSize { ... }
```

기존 `windowFrame` 호출처 모두 `initialWindowFrame` 으로 rename.

### 5.5 애니메이션

`setFrame:display:animate:true` 가 NSAnimation 으로 약 0.25s 부드럽게 처리. SwiftUI 의 `.animation(.easeInOut(duration: 0.22), value: vm.notchState)` 와 동기화.

체감 점프 발생 시:
- NSAnimation duration 명시 조절: `NSAnimationContext.runAnimationGroup { context in context.duration = 0.22; window.animator().setFrame(...) }`
- 또는 SwiftUI 애니메이션 disable 하고 NSPanel 만 애니메이트

### 5.6 멀티 디스플레이 / Space 전환

검증 항목:
- 두 모니터 환경에서 각 화면별 NSPanel 이 자기 화면 metrics 따라 resize
- Mission Control / Space 전환 후 panel 위치/크기 보존
- 화면 회전 / 디스플레이 추가 제거 (`NSScreen.didChangeNotification`)

### 5.7 검증 (5b)

수동:
- KBO 5경기 (시즌 중) → 펼치면 panel 이 312pt 콘텐츠 영역까지 자람, 5경기 모두 보임
- KBO 게임 클릭 → linescore 펼침 → +110pt 추가 자람 → 부드럽게 애니메이션
- 다시 게임 클릭(접기) → 줄어듦
- 위젯 전환 (KBO → Music → KBO) → 폭/높이 모두 부드럽게 변화
- 닫기/열기 토글 → top-anchor 보존 (위쪽 가장자리는 고정)

### 5.8 커밋 (5b)

```
feat(mangtch-new): NSPanel resizes to follow widget metrics

BoringNotchWindow.resizeContent rewrites the window frame whenever
PanelLayoutMetrics changes — preserving the top edge anchor so the
panel grows/shrinks downward from the notch. Widgets opt in via
NotchWidget.sizeDidChange publisher; KBO emits on game count /
linescore / starting pitcher changes.
```

---

## 6. 단계 5c — KBO ScrollView fallback + 화면 안전 영역

### 6.1 화면 안전 영역 max

`KBOWidget.heightRange.max` 를 화면 기반으로:

```swift
@MainActor
var heightRange: HeightRange {
    let ideal = computeIdealHeight()
    let safeMax = (NSScreen.main?.visibleFrame.height ?? 800) * 0.7
    return HeightRange(min: ideal * 0.5, ideal: ideal, max: min(safeMax, 700))
}
```

값 조정은 시각 검증 후. `0.7` 비율 / `700pt` 절대 ceiling 은 출발점.

### 6.2 ScrollView fallback

`KBOExpandedView` 의 게임 리스트 (정확한 행 위치는 착수자가 코드 읽고 결정) 를 `ScrollView(.vertical, showsIndicators: false)` 로 감싸기:

```swift
ScrollView(.vertical, showsIndicators: false) {
    LazyVStack(spacing: KBOLayoutTokens.rowGap) {
        ForEach(viewModel.games) { game in
            // 기존 game row
        }
    }
}
.frame(maxHeight: ...)   // metrics.contentHeight - header - linescore
```

> **함정**: ScrollView 가 들어가면 SwiftUI 의 intrinsic height 를 잃습니다. `heightRange` 산식이 ScrollView 안 콘텐츠 높이를 모르니 max 에 도달하면 강제 클램프 + 스크롤. 산식과 실제 콘텐츠가 어긋날 가능성 — 행 추가/삭제 애니메이션 깨질 수 있음.
>
> **권장 동작**: max 미만에서는 ScrollView 도 콘텐츠와 같이 자라고 (스크롤 비활성), max 초과 시에만 스크롤 활성. SwiftUI 에서 `ScrollView` + `.fixedSize(horizontal: false, vertical: true)` 조합 또는 `ViewThatFits` 사용.

### 6.3 검증 (5c)

- KBO 1~5경기 → ScrollView 비활성, panel 콘텐츠와 같이 자람
- KBO 10경기 + 모든 linescore (강제 mock) → max 도달, 스크롤 활성
- 스크롤 동작 시 wing/notch chrome 영역은 영향 없음

### 6.4 커밋 (5c)

```
feat(mangtch-new): KBO ScrollView fallback + screen-safe heightRange

heightRange.max now clamps to a fraction of the visible screen so the
panel never grows past viewport. KBOExpandedView wraps the game list
in a ScrollView that activates only when content exceeds max — sub-max
case keeps the panel size = content size.
```

---

## 7. 검토 게이트 (각 PR 본문)

### 5a
- [ ] `xcodebuild` SUCCEEDED
- [ ] `LayoutTokens.openCanvasWidth/Height` grep 결과 0
- [ ] `MusicLayoutTokens.swift` pbxproj 등록 (`grep -c MusicLayoutTokens project.pbxproj` ≥ 3)
- [ ] `WidthRange.fixed`, `HeightRange.fixed` 사용 확인 (`grep WidthRange.fixed`)
- [ ] Music 패널 시각 회귀 0 (640×190 그대로)
- [ ] KBO/Timer 가 잘리는 건 **5b 에서 해결됨을 PR 본문에 명시**

### 5b
- [ ] `xcodebuild` SUCCEEDED
- [ ] KBO 5경기 펼침 → 모든 행 보임 (스크린샷)
- [ ] linescore 펼침/접기 → panel 부드럽게 resize (GIF 권장)
- [ ] 위젯 전환 (Music ↔ KBO ↔ Timer) → 폭/높이 모두 변화 (GIF)
- [ ] top-anchor 보존 (notch 위치 변하지 않음)
- [ ] 멀티 디스플레이 / Space 전환 시 정상 (가능한 환경에서)
- [ ] `windowFrame` → `initialWindowFrame` rename 호출처 모두 적용

### 5c
- [ ] `xcodebuild` SUCCEEDED
- [ ] KBO 정상 케이스 (1~5경기) → ScrollView 스크롤 비활성
- [ ] KBO 강제 mock 10경기 → ScrollView 스크롤 활성
- [ ] heightRange.max 가 화면 70% 또는 700pt 클램프되는지 확인

---

## 8. 자가검증 grep

```bash
# 5a 후 — 전역 캔버스 상수 잔재 0
grep -rn "openCanvasWidth\|openCanvasHeight" mangtch-new --include="*.swift" \
  | grep -v "MusicLayoutTokens.swift"
# 결과: 비어있어야 함

# 5b 후 — windowFrame 호출 0 (initialWindowFrame 으로 통일)
grep -rn "windowFrame\b" mangtch-new --include="*.swift" \
  | grep -v "initialWindowFrame"
# 결과: 비어있어야 함

# 5b 후 — sizeDidChange publisher subscription
grep -rn "sizeDidChange" mangtch-new --include="*.swift"
# 결과: protocol 1, KBO 1, BoringViewModel 1 (subscribe), Music/Timer 0 (default empty)
```

---

## 9. 함정 / 주의

1. **Music 닫힘 시 wing 폭** — fixed(640) 으로 가면 닫힘 시도 (640-notch)/2 ≈ 220pt 고정. 트랙 텍스트 길이로 동적이던 게 사라짐. 사용자가 OK 했으니 진행하되, 시각적으로 어색하면 단계 6 으로 closed-time 폭 정책 분리.
2. **`@Observable` KBOViewModel → Combine publisher** 변환 — `@Observable` 의 변화 추적은 `withObservationTracking` 클로저 기반이라 Combine 으로 직접 못 옮김. 명시적 `didSet` 또는 별도 `@Published` mirror 추가 필요. KBOViewModel 손대기 싫으면 `Timer.publish(every: 0.5)` 폴링으로 `widthRange/heightRange` 비교해서 변화 감지. **권장**: KBOViewModel 에 `sizeDidChange` Publisher 직접 추가.
3. **Combine `removeDuplicates`** — `PanelLayoutMetrics` 가 `Equatable` 이어야 함. struct 자동 생성으로 OK.
4. **NSPanel resize 무한 루프** — `setFrame` → `screen` change → `BoringViewModel.recomputeMetrics` → `setFrame` ... 가능. `removeDuplicates` 로 차단되지만 검증 필요.
5. **`HoveredWing` / hit-zone** — wing 폭 변화 시 hit-zone 좌표가 변화. `WingHitZone` PreferenceKey 가 알아서 재계산하는지 확인. 안 되면 폭 변화마다 강제 invalidate.
6. **시즌 오프 KBO 검증 불가** — 5b 의 핵심 검증인 "5경기" 케이스가 시즌 중에만 자연 발생. 시즌 오프 시 `KBOViewModel.games = mockData` 디버그 코드 임시 삽입. 커밋에는 포함 X.
7. **boring.notch 자산 변경 금지** — `MusicPlayerView` 등 절대 손대지 말 것. Music 의 `widthRange.fixed(640)` 은 widget 선언 단의 변화일 뿐, 내부 view 는 그대로.
8. **Timer 은 어떻게 되나** — Timer 는 `panelMaxHeight = 320` 이라 5b 만 와도 충분히 동작. 5c 의 ScrollView fallback 은 KBO 한정.

---

## 10. 산출물 체크리스트

```bash
# 신규 파일
ls mangtch-new/boringNotch/components/Music/MusicLayoutTokens.swift

# 삭제된 상수
grep -c "openCanvasWidth\|openCanvasHeight" mangtch-new/boringNotch/sizing/LayoutTokens.swift
# 결과: 0

# 빌드
xcodebuild ... build 2>&1 | grep "BUILD SUCCEEDED"

# 시각 검증
# - Music 640×190 (5a/5b/5c 전후 동일)
# - KBO 5경기 다 보임 (5b 후)
# - linescore 펼침 시 panel 자람 (5b 후)
# - KBO 10경기 mock 스크롤 (5c 후)
```

---

**검토자**: Claude
**예상 시간**: 5a ≈ 2h, 5b ≈ 4–6h (NSPanel + Combine 와이어링), 5c ≈ 2h
**총 PR**: 3 (sub 별)
