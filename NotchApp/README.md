# NotchApp - macOS 노치 영역 생산성 허브

macOS 노치 영역을 생산성 허브로 변환하는 네이티브 앱입니다. [boring.notch](https://boringnotch.com/)에서 영감을 받아 처음부터 새로 구현했습니다.

**상태**: 베타 (Core 기능 완성, Phase 2 기능 개발 중)
**지원**: macOS 14.0+ (Sonoma), Apple Silicon
**라이선스**: MIT

---

## 특징

- **프로덕티비티 허브**: 노치 영역에 위젯을 배치하여 언제든지 접근 가능
- **음악 플레이어**: 현재 재생 중인 노래 표시 및 컨트롤 (Apple Music, Spotify 등 모든 미디어 앱)
- **파일 셸프**: 최근 파일/스크린샷을 노치에 올려 빠르게 접근
- **시스템 HUD**: 볼륨, 밝기, 키보드 백라이트 컨트롤
- **스프링 애니메이션**: Smooth 호버/클릭 확장 애니메이션
- **글로벌 단축키**: `Cmd+Shift+N`으로 패널 토글
- **외부 의존성 없음**: Apple 프레임워크만 사용 (Swift 5.9+)

---

## 빠른 시작

### 요구사항

- macOS 14.0 (Sonoma) 이상
- Apple Silicon Mac (M1, M2, M3 등) 또는 Intel Mac
- Xcode 15.0+ (빌드용) 또는 Swift 5.9+ 커맨드라인 도구

### 빌드 및 실행

```bash
# 저장소 클론
cd /Users/sarang/Projects/mangtch/NotchApp

# SPM으로 빌드
swift build

# 직접 실행 (테스트용)
.build/arm64-apple-macosx/debug/NotchApp

# 또는 .app 번들 빌드
./build-app.sh

# .app 번들 실행
open .build/release/NotchApp.app
```

### 설치

```bash
# 빌드
./build-app.sh

# Applications 폴더에 복사
cp -r .build/release/NotchApp.app /Applications/

# 실행
/Applications/NotchApp.app/Contents/MacOS/NotchApp

# 또는 Spotlight에서 "NotchApp" 검색 후 실행
```

---

## 프로젝트 구조

```
NotchApp/
├── Package.swift                              # Swift Package Manager manifest
├── Info.plist                                 # 번들 설정 (LSUIElement=true)
├── NotchApp.entitlements                      # Sandbox 권한
├── build-app.sh                               # .app 번들 빌드 스크립트
│
├── Sources/
│   ├── App/
│   │   ├── NotchApp.swift                    # @main 엔트리 포인트
│   │   ├── AppDelegate.swift                 # NSApplicationDelegate
│   │   └── MenuBarManager.swift              # 메뉴바 아이콘 관리
│   │
│   ├── Core/
│   │   ├── NotchWindow/
│   │   │   ├── NotchWindow.swift             # NSPanel (statusBar+1 레벨)
│   │   │   ├── NotchViewModel.swift          # 상태 머신 (idle/hovering/expanded)
│   │   │   ├── NotchContentView.swift        # 루트 SwiftUI 뷰
│   │   │   └── NotchShape.swift              # 노치 모양 + 좌표 감지
│   │   │
│   │   ├── Animation/
│   │   │   └── AnimationTokens.swift         # 스프링 애니메이션 상수
│   │   │
│   │   ├── EventBus/
│   │   │   └── EventBus.swift                # Combine PassthroughSubject
│   │   │
│   │   ├── Gesture/
│   │   │   └── GestureHandler.swift          # NSEvent 모니터, 호버 감지
│   │   │
│   │   └── Settings/
│   │       ├── SettingsManager.swift         # UserDefaults 래퍼
│   │       └── ShortcutManager.swift         # 글로벌 단축키 (Cmd+Shift+N)
│   │
│   ├── Widgets/
│   │   ├── NotchWidget.swift                 # 위젯 프로토콜 정의
│   │   ├── WidgetRegistry.swift              # 위젯 등록/관리/활성화
│   │   │
│   │   ├── MusicPlayer/
│   │   │   ├── MusicPlayerWidget.swift       # NotchWidget 구현
│   │   │   ├── MusicPlayerViewModel.swift    # 재생 상태 관리
│   │   │   ├── NowPlayingView.swift          # 컴팩트 뷰 (앨범아트+제목)
│   │   │   ├── ExpandedPlayerView.swift      # 확장 뷰 (컨트롤+프로그레스바)
│   │   │   └── AudioVisualizerView.swift     # 스펙트럼 바 애니메이션
│   │   │
│   │   ├── FileShelf/
│   │   │   ├── FileShelfWidget.swift         # NotchWidget 구현
│   │   │   ├── FileShelfViewModel.swift      # 파일 관리 및 썸네일
│   │   │   ├── FileShelfItemView.swift       # 파일 아이템 뷰
│   │   │   └── FileShelfDropDelegate.swift   # 드래그앤드롭 처리
│   │   │
│   │   └── HUD/
│   │       ├── HUDWidget.swift               # NotchWidget 구현
│   │       ├── HUDViewModel.swift            # 볼륨/밝기 이벤트
│   │       └── HUDSliderView.swift           # 커스텀 슬라이더 UI
│   │
│   ├── SystemBridge/
│   │   ├── MediaBridge.swift                 # MediaRemote private API (dlopen)
│   │   └── SystemInfoBridge.swift            # IOKit 배터리, CoreAudio 볼륨
│   │
│   └── Settings/
│       ├── SettingsView.swift                # 메인 설정 탭뷰
│       ├── GeneralSettingsView.swift         # 일반 설정
│       ├── WidgetSettingsView.swift          # 위젯 활성화/비활성화
│       └── AppearanceSettingsView.swift      # 테마/외관 설정
│
├── Tests/NotchAppTests/
│   ├── EventBusTests.swift                   # EventBus 단위 테스트
│   ├── NotchViewModelTests.swift             # 상태 머신 테스트
│   └── SettingsManagerTests.swift            # 설정 저장/로드 테스트
│
└── Resources/
    └── (앞으로 이미지, 사운드 등 추가 예정)
```

---

## 핵심 아키텍처

### 1. 노치 윈도우 (NSPanel)

```swift
// NotchWindow는 NSPanel 서브클래스
// - 레벨: .statusBar + 1 (메뉴바 위, 알림 아래)
// - 스타일: .nonactivatingPanel (포커스를 빼앗지 않음)
// - 투명: 배경색 투명, 그림자 동적
```

**노치 감지 로직** (`NotchShape.swift`):
```swift
let screen = NSScreen.screens.first  // 내장 디스플레이
let notchHeight = screen.safeAreaInsets.top  // 38.0pt (M3 MacBook Pro)
let hasNotch = notchHeight > 0
```

### 2. 상태 머신 (State Machine)

```
┌─────────────────────────────────────────┐
│            idle                         │
│  (마우스 위치 노치 아래, 투명)          │
│  - ignoresMouseEvents = true            │
│  - hasShadow = false                    │
└─────────────────────────────────────────┘
              ↓ (마우스 호버)
┌─────────────────────────────────────────┐
│          hovering                       │
│  (날개 확장, 컴팩트 위젯 표시)          │
│  - ignoresMouseEvents = false           │
│  - hasShadow = true                     │
└─────────────────────────────────────────┘
              ↓ (클릭)
┌─────────────────────────────────────────┐
│          expanded                       │
│  (패널 전체 표시, 확장 위젯)            │
│  - 마우스 다운/ESC로 돌아감            │
└─────────────────────────────────────────┘
```

### 3. EventBus (Combine 기반 이벤트 버스)

느슨한 결합을 위해 Combine의 `PassthroughSubject`를 사용합니다:

```swift
// 이벤트 발행
EventBus.shared.send(.stateChanged(.expanded))
EventBus.shared.send(.mediaChanged(mediaInfo))

// 이벤트 구독
EventBus.shared.stateChanges
    .sink { state in print("State: \(state)") }
    .store(in: &cancellables)

// 또는 타입 필터링
EventBus.shared.mediaChanges
    .sink { media in print("Now playing: \(media.title)") }
    .store(in: &cancellables)
```

### 4. 위젯 시스템 (Protocol-Based)

모든 위젯은 `NotchWidget` 프로토콜을 구현합니다:

```swift
protocol NotchWidget: AnyObject, Identifiable {
    var id: String { get }
    var displayName: String { get }
    var icon: String { get }
    var isEnabled: Bool { get set }
    var preferredPosition: WidgetPosition { get }

    // 호버 상태 (컴팩트 뷰)
    @MainActor func makeCompactView() -> AnyView

    // 확장 상태 (풀 패널)
    @MainActor func makeExpandedView() -> AnyView

    func activate()      // 위젯 활성화
    func deactivate()    // 위젯 비활성화
}
```

위젯 추가 예시:

```swift
class ClipboardWidget: NotchWidget {
    let id = "clipboard"
    let displayName = "클립보드"
    let icon = "doc.on.clipboard"
    var isEnabled = true
    let preferredPosition: WidgetPosition = .center

    func makeCompactView() -> AnyView {
        AnyView(Text("📋").font(.system(size: 24)))
    }

    func makeExpandedView() -> AnyView {
        AnyView(ClipboardExpandedView())
    }

    func activate() { /* 모니터링 시작 */ }
    func deactivate() { /* 모니터링 중지 */ }
}

// 등록
WidgetRegistry.shared.register(ClipboardWidget())
```

---

## 애니메이션 토큰 (PRD 기반)

| 토큰 | 값 | 용도 |
|------|-----|------|
| `expandHover` | spring(0.3, 0.7) | 호버 시 날개 확장 |
| `expandClick` | spring(0.35, 0.8) | 클릭 시 패널 확장 |
| `collapse` | spring(0.25, 0.9) | 패널 접힘 |
| `fadeIn` | easeInOut(0.2) | 콘텐츠 나타남 |
| `fadeOut` | easeInOut(0.15) | 콘텐츠 사라짐 |
| `hudAppear` | spring(0.2, 0.8) | HUD 표시 |
| `hudDismiss` | easeOut(0.3) | HUD 사라짐 |

### 사용 예시

```swift
withAnimation(.expandClick) {
    viewModel.state = .expanded
}
```

---

## 시스템 통합

### MediaBridge (미디어 제어)

MediaRemote private API를 `dlopen()`으로 동적 로드합니다:

```swift
// 현재 재생 정보 가져오기
MediaBridge.shared.nowPlaying // MediaInfo?

// 재생 상태
MediaBridge.shared.playbackState // PlaybackState

// 컨트롤
MediaBridge.shared.togglePlayPause()
MediaBridge.shared.nextTrack()
MediaBridge.shared.previousTrack()
```

**지원 앱**: Apple Music, Spotify, YouTube Music, 팟캐스트 등 모든 미디어 앱

### SystemInfoBridge (시스템 정보)

```swift
// 배터리 정보
SystemInfoBridge.shared.batteryLevel // 0.0~1.0
SystemInfoBridge.shared.isCharging

// 볼륨
SystemInfoBridge.shared.systemVolume // 0.0~1.0

// 밝기
SystemInfoBridge.shared.screenBrightness // 0.0~1.0
```

---

## 디버깅 가이드

### 로그 확인

앱 실행 시 콘솔에서 로그를 확인할 수 있습니다:

```bash
# 앱 실행
.build/arm64-apple-macosx/debug/NotchApp 2>&1 | grep "NotchApp\|NotchWindow\|MediaBridge"
```

#### 예상되는 로그 시퀀스

```
[NotchApp] applicationDidFinishLaunching started
[NotchApp] NSApplication activated
[NotchWindow] ✓ Built-in screen found (screens[0])
[NotchWindow] ✓ Notch detected! notchHeight=38.0, hasNotch=true
[NotchWindow] ✓ Window setup complete and visible
[MediaBridge] ✓ MediaRemote framework loaded
[MediaBridge] Function symbols loaded:
  - MRMediaRemoteGetNowPlayingInfo: true
  - MRMediaRemoteRegisterForNowPlayingNotifications: true
  - MRMediaRemoteSendCommand: true
```

### 노치 감지 확인

```bash
swift -e '
import AppKit

if let screen = NSScreen.screens.first {
    print("Screen frame: \(screen.frame)")
    print("Safe area insets (top): \(screen.safeAreaInsets.top)")
    print("Auxiliary areas:")
    print("  - Top Left: \(screen.auxiliaryTopLeftArea)")
    print("  - Top Right: \(screen.auxiliaryTopRightArea)")
}
'
```

또는 제공된 테스트 스크립트 사용:

```bash
swift test-notch.swift
```

### MediaBridge 문제 해결

**증상**: "0 keys received from MediaRemote"

**원인**:
1. MediaRemote 프레임워크 로드 실패
2. macOS 버전 호환성 문제 (함수 시그니처 변경)
3. DistributedNotificationCenter 연결 실패

**해결**:
1. 시스템 요구사항 확인 (macOS 14.0+)
2. `MediaBridge.swift`의 로그 확인
3. 다른 미디어 앱 테스트 (Apple Music 사용)

---

## 개발 가이드

### 새로운 위젯 추가하기

1. **Widgets 디렉토리에 새 폴더 생성**

```bash
mkdir Sources/Widgets/MyWidget
```

2. **NotchWidget 프로토콜 구현**

```swift
// Sources/Widgets/MyWidget/MyWidget.swift
import SwiftUI

class MyWidget: NotchWidget {
    let id = "mywidget"
    let displayName = "내 위젯"
    let icon = "star.fill"
    var isEnabled = true
    let preferredPosition: WidgetPosition = .leftWing

    @MainActor
    func makeCompactView() -> AnyView {
        AnyView(CompactMyWidgetView())
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(ExpandedMyWidgetView())
    }

    func activate() {
        // 초기화: 타이머, 옵저버 등
    }

    func deactivate() {
        // 정리: 타이머 중지, 옵저버 제거 등
    }
}
```

3. **WidgetRegistry에 등록**

```swift
// Sources/App/AppDelegate.swift의 applicationDidFinishLaunching에서
WidgetRegistry.shared.register(MyWidget())
WidgetRegistry.shared.activateAll()
```

### 테스트 작성

단위 테스트는 `Tests/NotchAppTests/` 디렉토리에 위치합니다:

```bash
# 테스트 실행
swift test

# 또는 특정 테스트만
swift test NotchViewModelTests
```

### 빌드 및 배포

```bash
# Release 빌드 (최적화 활성화)
swift build -c release

# .app 번들 생성
./build-app.sh

# 결과
.build/release/NotchApp.app
```

---

## 알려진 문제 및 제한사항

### 현재 알려진 버그

#### 1. MediaRemote Spotify 연동 미작동

**문제**: Spotify에서 현재 재생 정보가 표시되지 않음

**원인**:
- MediaRemote API가 Spotify에서 일부 정보를 제한할 수 있음
- macOS 버전에 따라 함수 시그니처가 다를 수 있음

**디버그 로그** (`[MediaBridge]` 프리픽스):
```
[MediaBridge] Received now playing info with 0 keys
```

**해결 방법** (진행 중):
- `MRMediaRemoteGetNowPlayingInfo` 호출 재검토
- Spotify의 D-Bus/IPC 인터페이스 직접 조회 고려
- Xcode 프로젝트로 전환 (SPM에서 동작이 다를 수 있음)

#### 2. 시스템 HUD 억제 미구현

**문제**: 네이티브 시스템 OSD (볼륨/밝기 표시)가 여전히 나타남

**현재**: `SettingsManager.suppressSystemHUD` 설정은 있지만 실제 억제 로직 미구현

**필요**: CGEventTap 또는 Accessibility API 활용

### Phase 2 예정 기능 (미구현)

- 클립보드 매니저
- 캘린더 & 리마인더 위젯
- 배터리 상태 위젯 (자세한 정보)
- 트랙패드 제스처 지원
- AirDrop 통합
- 플러그인 SDK (XPC)
- 테마 시스템
- Live Activity 지원
- 외부 모니터 폴백 모드
- Sparkle 자동 업데이트

### 아키텍처 개선 사항

- [ ] ThemeEngine 모듈 분리 (현재 .ultraThinMaterial 고정)
- [ ] MusicKit 통합 (현재 MediaRemote만 사용)
- [ ] Free/Pro 라이선스 게이팅
- [ ] 위젯 순서 드래그 재정렬
- [ ] CADisplayLink 기반 애니메이션 동기화
- [ ] 멀티모니터 설정 관리

---

## 기술 스택

| 항목 | 버전/사양 |
|------|---------|
| Swift | 5.9+ |
| Platform | macOS 14.0+ (Sonoma) |
| UI Framework | SwiftUI + AppKit 하이브리드 |
| Package Manager | Swift Package Manager (SPM) |
| Architecture | Apple Silicon (arm64), Intel x86_64 |
| 외부 의존성 | 없음 (Apple 프레임워크만) |

### 사용 중인 Apple 프레임워크

- **AppKit** - 윈도우, 패널, 이벤트 처리
- **SwiftUI** - UI 구성
- **Combine** - 반응형 프로그래밍
- **QuartzCore** - 애니메이션
- **IOKit** - 배터리 정보
- **CoreAudio** - 오디오 볼륨
- **MediaRemote** (private) - 미디어 제어

---

## 참고 자료

- **PRD**: `/Users/sarang/Projects/mangtch/PRD_macOS_Notch_App.md`
- **빌드 가이드**: `BUILD.md`
- **변경 로그**: `CHANGELOG-NSScreen-Fix.md`
- **Apple 문서**: [NSPanel](https://developer.apple.com/documentation/appkit/nspanel), [NSScreen](https://developer.apple.com/documentation/appkit/nsscreen)

---

## 기여 가이드

### 코드 스타일

- Swift 공식 스타일 가이드 준수
- 한글 주석 사용 (한국인 팀용)
- 기술 용어는 영어 유지 (예: `viewModel`, `NotchState`)
- 로그: `[모듈명]` 프리픽스 사용

### 커밋 메시지

```
[모듈명] 변경 사항 요약

상세 설명 (필요시)

예시:
[MediaBridge] Fix Spotify now playing detection
[NotchWindow] Add multi-monitor support
[UI] Improve animation smoothness with CADisplayLink
```

### 테스트

- 새로운 기능은 단위 테스트 포함
- 통합 테스트는 실제 Mac에서 수행
- CI/CD 파이프라인은 추후 구축 예정

---

## 라이선스

MIT License - 자유롭게 사용, 수정, 배포 가능

---

## 지원 및 피드백

이 프로젝트는 개인 개발 중입니다. 버그 리포트나 피드백은 다음을 통해 제출하세요:

- **이슈**: 기술적 문제
- **PRD 검토**: 기능 요청
- **로그 분석**: 디버깅 도움

---

## 빠른 참고 (Cheat Sheet)

### 앱 실행

```bash
swift build && .build/arm64-apple-macosx/debug/NotchApp
```

### 앱 빌드 (.app 번들)

```bash
./build-app.sh && open .build/release/NotchApp.app
```

### 테스트 실행

```bash
swift test
```

### 로그 확인

```bash
swift run NotchApp 2>&1 | grep "\[.*\]"
```

### 노치 감지 테스트

```bash
swift test-notch.swift
```

### 설정 초기화

```bash
defaults delete com.notchapp
```

### 설정 로그인 항목에 추가

```bash
open /Applications/NotchApp.app
# 그 후 System Settings → General → Login Items에 수동으로 추가
```

---

**최종 업데이트**: 2026년 2월 10일
**안정성**: 베타 - 프로덕션 사용 권장하지 않음
