# Mangtch — Claude working notes

macOS 노치(notch) 패널 앱. SwiftUI + AppKit 인터롭, `.nonactivatingPanel` 윈도우, NSEvent 글로벌 모니터로 wing 클릭/호버 디스패치.

## After every code change

코드 수정 후에는 **항상** 빌드 → 재설치 → 재실행까지 알아서 끝낸다. 사용자에게 빌드해달라고 요청하지 말 것.

```bash
cd /Users/sarang/Projects/mangtch/Mangtch && ./build-app.sh
pkill -9 -x Mangtch; sleep 0.3
rm -rf /Applications/Mangtch.app
cp -R /Users/sarang/Projects/mangtch/Mangtch/.build/release/Mangtch.app /Applications/
open /Applications/Mangtch.app
```

한 줄로 (선호):

```bash
cd /Users/sarang/Projects/mangtch/Mangtch && ./build-app.sh 2>&1 | tail -3 && pkill -9 -x Mangtch; sleep 0.3; rm -rf /Applications/Mangtch.app && cp -R /Users/sarang/Projects/mangtch/Mangtch/.build/release/Mangtch.app /Applications/ && open /Applications/Mangtch.app
```

빌드가 "input file ... was modified during the build" 에러로 실패하면 (사용자가 동시 편집 중일 때) 한 번 더 시도.

## Architecture cheatsheet

- `NotchContentView` — SwiftUI 루트. wings, expanded panel, HUD overlay 조합.
- `NotchViewModel` (@Observable) — 패널 상태(`currentState`), 너비/높이, hoveredWing 등.
- `NotchWindow` (NSPanel) — `.borderless, .nonactivatingPanel, .fullSizeContentView`. `setFrame`으로 직접 위치/크기 갱신.
- `GestureHandler` — 글로벌 NSEvent 모니터로 mouse moved/down 잡아서 hover 상태 갱신 + wing 버튼 클릭 디스패치.
- `WidgetRegistry` (@Observable) — 위젯 등록/조회. `NotchWidget` 프로토콜 구현체들 보관.

## Wing 클릭 디스패치

`.nonactivatingPanel`이라 SwiftUI Button/`.onTapGesture`가 안 먹음. 대신:
1. 각 클릭 가능 버튼이 `.wingHitZone(.musicPrev)` 모디파이어 적용
2. 모디파이어가 `GeometryReader`로 frame을 `.global` (윈도우 좌표) → `NotchWindow.shared.convertToScreen(_:)`로 스크린 좌표 변환 → `WingHitZonesKey` PreferenceKey로 보고
3. `NotchContentView`가 모아서 `NotchViewModel.wingHitZones`에 저장 (id별 dedupe)
4. `GestureHandler.handleWingClick`이 click point가 어느 hit zone rect에 들어가는지 검사해 dispatch

새 wing 버튼 추가 시: `WingButton` enum에 케이스 추가 → 뷰에 `.wingHitZone(...)` 적용 → `GestureHandler.dispatch(_:)`에 분기 추가.

## Wing/패널 너비

- `compactWingWidth`: 컴팩트 모드(idle/hovering)에서 wing 컨텐츠 자연 너비 측정값. PreferenceKey로 측정.
- `wingWidth` (computed): `isPanelMode`면 `panelModeWingWidth`, 아니면 `compactWingWidth`.
- `panelModeWingWidth`: `(현재 위젯의 preferredPanelWidth - notchWidth) / 2` 클램프.
- 위젯이 `preferredPanelWidth: CGFloat?` 선언 → 펼쳐졌을 때 wing/패널 너비 결정.
- 펼침/닫힘 중에는 wing이 expanded 모양 유지 (corner radius도 `expandedHeight` 비율로 보간).

## Conventions

- 응답은 한국어, CTO 스타일로 짧게.
- 코드 코멘트는 영어. WHY 위주, WHAT은 식별자가 설명하니 생략.
- 잘림(`lineLimit`/`truncationMode`) 금지 — chrome을 늘려서 컨텐츠 보이게.
- 다크 패널이 기본 (`Color(white: 0.14)`). `.environment(\.colorScheme, .dark)`로 강제.
