# mangtch-new — 단계 6: 부채 정리 + 위젯 관리 UI

> **역할**: 이 문서는 **착수자(FE)**용입니다. 작성자(Claude)는 **검토만** 합니다.
> **선행**: 단계 1–5 완료. base 커밋 = `ef70bf6`.
> **선행 문서**: `HANDOFF.md` §1 (architectural rules), `PLAN-content-driven-sizing.md` (단계 5 결과 회고)
> **브랜치**: `mangtch-new-wip` 분기.

---

## 0. 왜 (1분)

단계 1–5 가 chrome ↔ widget 경계를 정리했습니다. 이제 chrome 은 widget-agnostic 이고 새 위젯 추가 시 chrome 수정 0. 다음 단계는 **그 경계 위에서 사용자가 위젯을 켜고 끄고 정렬**할 수 있게 해야 위젯 시스템이 실제로 "확장 가능" 합니다. 동시에 단계 1–5 동안 의도적으로 미뤘던 부채 (XPCHelperClient stub, Calendar Settings stub, BoringNotchXPCHelper target shell) 를 같이 정리합니다 — 모두 SettingsView 를 건드리는 작업이라 한 번에 하는 게 효율적입니다.

---

## 1. 단계 1–5 이후 남은 작업 인벤토리

작성자가 코드 베이스 + HANDOFF.md 를 훑고 추린 잔여 작업 (단계 6 후보 + 그 이후 후보):

### Tier A — 부채 정리 (HANDOFF.md 명시 / 단계 1–5 누적)

| 항목 | 위치 | 현황 |
|---|---|---|
| `XPCHelperClient.swift` no-op stub | `boringNotch/managers/` | SettingsView (4 호출) + BrightnessManager (2 호출) + VolumeManager 가 의존. 하지만 BrightnessManager / VolumeManager 는 **외부에서 참조 0** (`grep -rn BrightnessManager` 결과 managers/ 외에 없음) → 같이 제거 가능 |
| `BoringNotchXPCHelper` target shell | `boringNotch.xcodeproj/project.pbxproj` | 빈 껍데기. 빌드 산출물 (`BoringNotchXPCHelper.xpc`) 만 남음 |
| `CalendarSettings` stub | `SettingsView.swift:80` | 빈 EmptyView. Settings 메뉴에 빈 섹션으로 보임 |
| `mediaremote-adapter/` 디렉토리 | repo root | **삭제 X**. `NowPlayingController.swift:193` + `MediaChecker.swift:20` 가 실제 사용. HANDOFF.md 의 "삭제 검토" 권장은 잘못된 정보. HANDOFF.md 만 정정 |
| `Notification.Name.boringNotchDidOpen` | `BoringViewModel.swift:226` post / `KBOViewModel.swift:183` subscribe | **사용 중**. HANDOFF.md 의 "옵저버 없음" 도 outdated. HANDOFF.md 정정만 |
| `.gitignore` 누락 | repo root | `Mangtch/Mangtch-0.7.1.zip`, `boring.notch/` untracked. 빌드 산출물 / 참고자료 / OS 메타파일 누락 가능 |

### Tier B — 확장성 기능 (단계 6 핵심 산출)

| 항목 | 비용 추정 |
|---|---|
| **위젯 enable/disable UI** | Settings 안 새 섹션. Defaults 키 + WidgetRegistry 와 sync. 2-3h |
| **위젯 순서 변경 UI** | drag-reorder list. WidgetRegistry 에 ordering 추가. 2-3h |
| **현재 활성 wing 위젯 선택 UI** | Settings 또는 WidgetSwitcherBar 컨텍스트 메뉴. 1-2h |

### Tier C — 단계 5 에서 의도적 보류

| 항목 | 비고 |
|---|---|
| Width 동적화 (NSAnimation ↔ SwiftUI ease sync) | 단계 5b 에서 wobble 발견되어 fixed(640) 로 절충. 다시 들어가려면 두 애니메이션 시스템 sync 또는 SwiftUI 단독 처리로 NSPanel 우회. 4-6h. **단계 7+** |
| Music 닫힘 시 wing 폭 동적 (트랙 텍스트 길이) | 위 Width 동적화의 부분집합. 별도로는 무의미 |

### Tier D — 새 기능 (단계 7+)

- 좌우 wing **동시** 위젯 표시 (좌=Music, 우=KBO)
- Theme/컬러 토큰 시스템 (현재 hard-coded `Color(white: 0.14)` 등)
- Dynamic Type / 폰트 사이즈 토큰화
- 외부 위젯 (sandbox, 다른 프로세스 또는 plugin bundle)
- KBO ScrollView 재시도 (단계 5c 에서 폐기 — 10경기 mock 케이스 안전망)

---

## 2. 단계 6 권장 범위

**Tier A (부채) + Tier B (위젯 관리 UI)**.

이유:
1. 둘 다 **SettingsView 를 건드림**. 한 번에 처리해서 PR 분산 비용 절약
2. Tier A 정리하면 SettingsView 가 ~150 lines 가벼워져서 Tier B (위젯 관리) 추가 비용 절감
3. Tier B 가 단계 1–5 의 "확장성 있는 chrome" 의 마지막 사용자 가시 산출물 — 여기까지 와야 위젯 시스템이 "쓸 수 있는" 모양이 됨
4. Tier C/D 는 더 큰 작업이라 별 단계로 두는 게 맞음

**제외**:
- Tier C (Width 동적화) — wobble 디버깅 비용 큼, 사용자 영향 작음 (현재 OK)
- Tier D — 별 작업, 단계 7+

---

## 3. 단계 분할 (PR 4개 권장)

| Sub | 작업 | 위험도 | 의존 |
|---|---|---|---|
| **6a** | `.gitignore` 신설 + HANDOFF.md 정정 (mediaremote-adapter / boringNotchDidOpen / 단계 5 진행 상태) | 낮음 | — |
| **6b** | XPCHelperClient + BrightnessManager + VolumeManager 제거 (사용처 없음 검증). SettingsView 의 accessibility 섹션 제거 | 중. 빌드 깨질 수 있음 — 엣지 콜사이트 확인 필수 | 6a 먼저 정정된 HANDOFF 참조 |
| **6c** | CalendarSettings stub 제거. SettingsView 메뉴에서 Calendar 항목 제거 | 낮음 | 6b |
| **6d** | 위젯 관리 Settings 섹션 (enable/disable + order). `WidgetRegistry` 에 ordering API 추가, Defaults persist | 중. WidgetRegistry contract 변화 | 6c |

선택 사항: **6e** BoringNotchXPCHelper target 삭제. pbxproj 수동 편집 필요. 빌드 산출물 가벼워짐. 위험도 낮지만 별도 PR 권장 (pbxproj 변경 scope 명확화).

---

## 4. 단계 6a — `.gitignore` + HANDOFF 정정

### 4.1 `.gitignore` 신설

repo root 에 `.gitignore` 만들거나 기존 파일에 append. 후보 패턴:

```
# Build artifacts
mangtch-new/build/
Mangtch/.build/
*.dSYM/

# OS
.DS_Store

# Editor
.swiftpm/
.idea/
*.xcuserdata/

# Project-specific
Mangtch/Mangtch-*.zip
boring.notch/
```

`boring.notch/` 가 untracked 로 잡히는 건 upstream reference clone 같음. 사용자에게 의도 확인. 의도면 ignore, 아니면 삭제.

### 4.2 HANDOFF.md 정정

- §3 "How to build" — Xcode GUI / pbxproj 등록 / SourceKit false positive 등 단계 4-5 동안 보강된 안내 통합
- "Known issues" 섹션 갱신:
  - 🔴 wing 사이즈 어긋남 → **해결됨** (단계 5d stable-mount). 회고 항목으로 이동
  - 🟡 `XPCHelperClient.swift` 스텁 → **단계 6b 에서 제거됨** (작업 후 갱신)
  - 🟡 `boringNotchDidOpen` post 가 dead → **틀린 정보**. KBOViewModel 이 subscribe. 정정
  - 🟡 SettingsView Calendar stub → 단계 6c 에서 제거됨
  - 🟢 `mediaremote-adapter` 사용 검증 권장 → **사용 중**. NowPlayingController + MediaChecker 가 의존. 정정 (삭제 권장 X)
- §6 "Where the design decisions live" — 단계 5 결과 추가 (`PanelLayoutMetrics`, `BoringNotchWindow.resizeWindow`, stable-mount wing 패턴)

### 4.3 검증

빌드 영향 0. 그래도 빌드 한 번 돌려서 SUCCEEDED 확인.

### 4.4 커밋 (6a)

```
chore(mangtch-new): .gitignore + HANDOFF refresh after phases 1-5

.gitignore covers build artifacts, OS metadata, and reference clones.
HANDOFF.md updated to reflect: wing sizing fixed (5d), mediaremote-adapter
is in use (HANDOFF was wrong), boringNotchDidOpen has an observer (KBO).
```

---

## 5. 단계 6b — XPCHelperClient + Brightness/Volume 제거

### 5.1 사용처 사전 검증

```bash
grep -rn "XPCHelperClient" mangtch-new/boringNotch --include="*.swift"
grep -rn "BrightnessManager\|VolumeManager" mangtch-new/boringNotch --include="*.swift" | grep -v "managers/"
```

작성자 확인: BrightnessManager / VolumeManager 는 **외부 참조 0**. SettingsView 의 XPCHelperClient 호출만 정리하면 cascade 안전.

### 5.2 삭제 대상

- `boringNotch/managers/XPCHelperClient.swift`
- `boringNotch/managers/BrightnessManager.swift`
- `boringNotch/managers/VolumeManager.swift`
- pbxproj 에서 위 3 파일 entry 제거 (`PBXFileReference` + `PBXBuildFile` + Sources build phase)

### 5.3 SettingsView 정리

`SettingsView.swift:376, 501, 577, 580, 583` 참조점 모두 제거. 관련 UI 섹션 제거 (보통 "Accessibility" 또는 "Permissions" 라벨). `accessibilityAuthorized: Bool` State variable 도 제거.

> **주의**: HANDOFF.md §1 "No fallback shims" 원칙. 호출 자체를 지우는 게 맞고, 다른 stub 으로 대체 X.

### 5.4 검증

```bash
xcodebuild ... build 2>&1 | tail -5    # SUCCEEDED
```

수동:
- 앱 실행 → 충돌 없음
- Settings 열기 → Accessibility 섹션 사라짐, 다른 섹션은 정상

### 5.5 커밋 (6b)

```
refactor(mangtch-new): remove dead XPCHelperClient + Brightness/Volume managers

XPCHelperClient was a no-op stub left behind from the boring.notch fork
strip. Its only consumers in main code (BrightnessManager, VolumeManager,
SettingsView accessibility section) are themselves unused — Brightness/
Volume managers have zero call sites outside managers/, and the
accessibility prompt UI was tied to the deleted MediaKeyInterceptor.
```

---

## 6. 단계 6c — Calendar Settings stub 제거

### 6.1 변경

- `SettingsView.swift:80` `CalendarSettings()` 호출 제거
- 사이드바 메뉴에서 Calendar 항목 제거 (`enum SettingsSection.calendar` 제거)
- `CalendarSettings` 정의 자체가 stub 인지 별 파일인지 확인:
  - 별 파일이면 파일 삭제 + pbxproj 정리
  - 인라인이면 SettingsView 안에서 제거

### 6.2 검증

- Settings 메뉴에 Calendar 안 보임
- 다른 섹션 정상 동작

### 6.3 커밋 (6c)

```
refactor(mangtch-new): remove Calendar Settings stub

Calendar functionality was stripped during the boring.notch fork
(Phase 2). The Settings entry was kept as an EmptyView stub — now
removed for parity with what the app actually exposes.
```

---

## 7. 단계 6d — 위젯 관리 UI

### 7.1 데이터 모델

`WidgetRegistry` 에 ordering + persistence:

```swift
@Observable
@MainActor
final class WidgetRegistry {
    static let shared = WidgetRegistry()

    private(set) var widgets: [AnyNotchWidget] = []   // 순서 의미 있음

    /// Persisted via Defaults["widgetOrder"] = ["music-player", "kbo", "timer"]
    /// + Defaults["widgetEnabled.<id>"] = Bool
    func register(_ widget: some NotchWidget) { ... }
    func setEnabled(_ id: String, _ enabled: Bool) { ... }
    func reorder(from: IndexSet, to: Int) { ... }

    var enabledWidgets: [AnyNotchWidget] {
        widgets.filter { $0.isEnabled }
    }

    /// Restore ordering + enabled state from Defaults at app launch.
    func loadPersistedConfig() { ... }
}
```

`Defaults` 키:
```swift
extension Defaults.Keys {
    static let widgetOrder = Key<[String]>("widgetOrder", default: ["music-player", "kbo", "timer"])
    // per-widget enabled 는 dynamic key — Defaults["widgetEnabled.\(id)"]
}
```

### 7.2 Settings 섹션

`SettingsView` 에 새 섹션 "Widgets":

```swift
struct WidgetsSettings: View {
    @State private var registry = WidgetRegistry.shared

    var body: some View {
        Form {
            Section("Active Widgets") {
                List {
                    ForEach(registry.widgets, id: \.id) { widget in
                        WidgetRow(widget: widget)
                    }
                    .onMove { from, to in
                        registry.reorder(from: from, to: to)
                    }
                }
            }
        }
    }
}

struct WidgetRow: View {
    @Bindable var widget: AnyNotchWidget

    var body: some View {
        HStack {
            Image(systemName: widget.icon)
            Text(widget.displayName)
            Spacer()
            Toggle("", isOn: $widget.isEnabled)
                .toggleStyle(.switch)
        }
    }
}
```

### 7.3 ContentView/WidgetSwitcherBar 영향

- `widgetRegistry.enabledWidgets` 가 이미 ordered 라 변경 거의 없음
- `currentExpandedWidgetID` 가 disabled 된 위젯 가리키면 첫 enabled 로 fallback

### 7.4 검증

수동:
- Settings → Widgets → KBO disable → 패널 펼쳤을 때 KBO tab 사라짐
- Music 만 enabled 면 WidgetSwitcherBar 가 단일 항목 또는 hide
- 위젯 순서 drag → WidgetSwitcherBar 순서 변경
- 앱 재시작 → 순서/enabled 보존

엣지:
- 모든 위젯 disable → 패널이 "No widgets enabled" placeholder (이미 ContentView 에 있음)
- 활성 위젯 disable 시 다음 enabled 로 자동 전환

### 7.5 커밋 (6d)

```
feat(mangtch-new): user-controlled widget ordering and enable/disable

Adds a Widgets section to Settings — toggle each widget on/off,
drag-reorder the WidgetSwitcherBar tab order. State persists via
Defaults across launches. WidgetRegistry now exposes ordered
widgets[] (instead of an unordered map) and broadcasts changes
via @Observable so chrome reacts without manual wiring.
```

---

## 8. 단계 6e (선택) — BoringNotchXPCHelper target 제거

빌드 산출물 (`BoringNotchXPCHelper.xpc`) 만 만드는 dead target. pbxproj 에서 수동 제거:
- `PBXNativeTarget` "BoringNotchXPCHelper"
- `PBXTargetDependency` 메인 target 의 dependency
- `PBXContainerItemProxy`
- 관련 `XCBuildConfiguration` 4개 (Debug/Release × Target/Project)
- Embed Frameworks build phase 의 `PBXBuildFile` (메인 앱이 .xpc 임베드)

검증: `xcodebuild -list` 에서 target 1개만 (`boringNotch`).

위험도 낮지만 pbxproj 변경이 큼 → 별 PR.

### 커밋 (6e)

```
chore(mangtch-new): drop empty BoringNotchXPCHelper target

The XPC helper was stripped during Phase 2 of the boring.notch fork.
The pbxproj target shell remained, producing an empty .xpc bundle on
every build. No app code referenced it after Phase 2 cleanup.
```

---

## 9. 검토 게이트 (각 PR)

### 6a
- [ ] `xcodebuild` SUCCEEDED
- [ ] `git status` 에 `Mangtch/Mangtch-*.zip`, `boring.notch/` 안 보임
- [ ] HANDOFF.md "Known issues" 가 현재 상태와 일치

### 6b
- [ ] `xcodebuild` SUCCEEDED
- [ ] `grep -rn "XPCHelperClient" mangtch-new` 결과 0
- [ ] `grep -rn "BrightnessManager\|VolumeManager" mangtch-new --include="*.swift"` 결과 0
- [ ] Settings 시각: Accessibility 섹션 사라짐, 다른 섹션 정상
- [ ] 앱 실행 시 충돌 X

### 6c
- [ ] `xcodebuild` SUCCEEDED
- [ ] Settings 메뉴에 Calendar 안 보임
- [ ] `grep -rn "CalendarSettings" mangtch-new --include="*.swift"` 결과 0

### 6d
- [ ] `xcodebuild` SUCCEEDED
- [ ] Settings → Widgets 섹션 표시
- [ ] 토글 / 순서 변경 동작 + 재시작 보존
- [ ] 활성 위젯 disable 시 다음 enabled 로 자동 전환 (스크린샷)
- [ ] 모든 위젯 disable 시 placeholder 표시

### 6e
- [ ] `xcodebuild` SUCCEEDED
- [ ] `xcodebuild -list` 결과 target 1개
- [ ] `.app` 안에 `XPCServices/BoringNotchXPCHelper.xpc` 없음

---

## 10. 자가검증 grep

```bash
# 6b 후
grep -rn "XPCHelperClient\|BrightnessManager\|VolumeManager" \
  mangtch-new/boringNotch --include="*.swift" | wc -l
# 결과: 0

# 6c 후
grep -rn "CalendarSettings\|case .calendar" \
  mangtch-new/boringNotch/components/Settings --include="*.swift" | wc -l
# 결과: 0

# 6d 후 — Defaults persistence
grep -rn "widgetOrder\|widgetEnabled" mangtch-new/boringNotch --include="*.swift"
# 결과: WidgetRegistry 1, Defaults.Keys 1, 그 외 0
```

---

## 11. 함정

1. **`@Observable` ↔ `@Bindable`** — 단계 5d 이후 `WidgetRegistry` / `AnyNotchWidget` 는 `@Observable`. SwiftUI 에서 Toggle binding 하려면 `@Bindable var widget: AnyNotchWidget`. `@ObservedObject` X.
2. **위젯 순서 변경 시 wing 식별 churn** — 단계 5d stable-mount 가 위젯 인스턴스 ID 기반으로 mount. 순서 변경은 WidgetSwitcherBar 만 영향, wing 마운트는 영향 없음. **동작 확인 필요**.
3. **활성 위젯 disable** — `vm.currentExpandedWidgetID` 가 invalid 한 ID 가리키게 됨. ContentView 에서 자동 fallback (`enabledWidgets.first`) 하게 처리. 이미 `expandedContent` 에 비슷한 fallback 있음.
4. **pbxproj 수동 편집 (6b 파일 삭제, 6e target 삭제)** — Xcode GUI 가 안전. CLI 편집 시 백업 + diff 검토.
5. **HANDOFF.md `boringNotchDidOpen` 정보** — HANDOFF 가 outdated. KBOViewModel.swift:183 이 subscribe 중. "dead post" 라는 이전 기재는 잘못. 정정 필수.
6. **`mediaremote-adapter/` 폴더** — 삭제 X. NowPlayingController + MediaChecker 가 사용 중. HANDOFF 도 정정.

---

## 12. 단계 7+ 로 넘기는 작업 (참고)

- **Width 동적화** — NSAnimation ↔ SwiftUI ease sync. 4-6h
- **Theme/컬러 토큰** — 현재 `Color(white: 0.14)`, `Color.white.opacity(0.04)` 등 산재. 단계 1-4 와 동일 패턴
- **Dynamic Type / 폰트 토큰**
- **좌우 wing 동시 위젯** — `currentExpandedWidgetID` 단일 → leftActiveID/rightActiveID 분리
- **외부 위젯 (sandbox / plugin bundle)**
- **KBO ScrollView fallback 재시도** — 단계 5c 폐기, 10경기 mock 케이스 안전망 필요 시

---

**검토자**: Claude
**예상 시간**: 6a ≈ 1h, 6b ≈ 1.5h, 6c ≈ 0.5h, 6d ≈ 3-4h, 6e ≈ 1h. **총 7-8h**.
**총 PR**: 4 (6a/b/c/d) 또는 5 (6e 포함)
