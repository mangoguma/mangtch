# mangtch-new — Handoff

> Status: builds + runs as a `.nonactivatingPanel` accessory app.
> Wing layout currently mis-sized (see **Known issues**). The fold/expand state machine works; click dispatch reaches `MusicManager`.

`mangtch-new/` is a fork of `boring.notch/` (open-source upstream) with non-product features stripped and Mangtch's widget machinery + KBO/Timer/Music widgets grafted in.

The original `Mangtch/` SPM project is **not** modified — read-only reference for porting.

---

## 1. Architectural rules (do not violate)

These came directly from the user. They override anything the plan or earlier code suggests.

- **boring.notch is the architectural base.** Keep its Xcode project (`boringNotch.xcodeproj`), `boringNotchApp.swift` + `AppDelegate`, `BoringViewCoordinator`, per-screen `BoringViewModel`, multi-display window/positioning logic, settings shell, `MediaControllerProtocol` + 4 controllers, Sparkle, sindresorhus/Defaults.
- **Mangtch contributes feature code only.** Whitelisted ports: KBO widget, Timer widget, dynamic-width `WidgetRegistry`, wing hit-zone system (`WingHitZone` + `FirstMouseHostingView`), Mangtch's `GestureHandler`. **Nothing else** from Mangtch.
- **Out of scope (do not port without asking):** Spotify PKCE OAuth, LRCLIB/NetEase lyrics, album-art theme extraction, Mangtch's onboarding flow, Mangtch's `NotchViewModel`/`NotchWindow`/`NotchWindowManager` app-level wiring (we keep boring.notch's class names).
- **Build system:** Xcode project. Not SPM.
- **No fallback shims.** If something is referenced by removed code, remove the call site rather than stub the dependency. The Phase 2 `XPCHelperClient.swift` no-op stub is technical debt — clean up when touching SettingsView.

A copy of these rules also lives in user memory: `/Users/sarang/.claude/projects/-Users-sarang-Projects-mangtch/memory/feedback_mangtch_new_scope.md`.

---

## 2. What's in `mangtch-new/`

### Layout (boring.notch's layout, lightly augmented)

```
mangtch-new/
  boringNotch.xcodeproj/                # main Xcode project (single scheme: boringNotch)
  BoringNotchXPCHelper/                 # stripped target — XPC helper sources gone, the
                                        #   target shell remains in pbxproj. Safe to delete
                                        #   the target outright; nothing in the main app
                                        #   references it after Phase 2.
  Configuration/, mediaremote-adapter/, updater/,
  LICENSE, THIRD_PARTY_LICENSES, SECURITY.md, CONTRIBUTING.md, README.md
  HANDOFF.md  ← this file
  boringNotch/                          # main app sources
    boringNotchApp.swift                # @main + AppDelegate
    BoringViewCoordinator.swift         # global nav (trimmed: HUD/MediaKey logic gone)
    ContentView.swift                   # REWRITTEN: Mangtch wings + WidgetSwitcherBar
    components/
      Notch/
        BoringNotchWindow.swift         # NSPanel — absorbed SkyLight panel config
        BoringHeader.swift              # trimmed (battery/calendar gone)
        BoringExtrasMenu.swift
        NotchHomeView.swift             # trimmed — only renders MusicPlayerView now
        NotchShape.swift                # boring.notch's shape (used by NotchHomeView)
        WingHitZone.swift               # PORTED from Mangtch
        FirstMouseHostingView.swift     # PORTED — accepts first-mouse for nonactivating panel
        WingShapes.swift                # PORTED — WingShape, ExpandedPanelShape, NotchGeometry
      Music/
        MusicPlayerWidget.swift         # NEW — thin NotchWidget over MusicManager
        MusicVisualizer.swift, LottieAnimationView.swift  # boring.notch
      Shelf/                            # boring.notch (kept fully — drag-drop tray)
      Settings/                         # boring.notch (Calendar section is a stub)
      Tabs/
        TabButton.swift, TabSelectionView.swift            # boring.notch
        WidgetSwitcherBar.swift         # PORTED from Mangtch
      KBO/                              # PORTED — 9 files
      Timer/                            # PORTED — 4 files
      Live activities/                  # only LiveActivityModifier.swift + MarqueeTextView.swift left
      AnimatedFace.swift, BottomRoundedRectangle.swift, EmptyState.swift,
      HoverButton.swift, LottieView.swift, ProgressIndicator.swift
    Widgets/                            # NEW — Mangtch widget protocol layer
      NotchWidget.swift
      WidgetRegistry.swift              # @Observable singleton; registerDefaults() registers Music+Timer+KBO
    SystemBridge/
      KBOService.swift                  # PORTED — Naver KBO API client
    managers/                           # boring.notch — kept: MusicManager, ImageService,
                                        #   NotchSpaceManager, BrightnessManager, VolumeManager
                                        # plus XPCHelperClient.swift (no-op stub — see "Cleanup needed")
    MediaControllers/                   # boring.notch — all 4 (NowPlaying, Apple Music, Spotify, YT Music)
    helpers/, extensions/, observers/, models/, sizing/, animations/,
      menu/, utils/, enums/, Shortcuts/  # mostly boring.notch; observers/GestureHandler.swift is PORTED
    Resources, Info.plist, boringNotch.entitlements, Localizable.xcstrings,
    boring.m4a, Assets.xcassets, Preview Content
```

### What was deleted from boring.notch

Calendar, Webcam, Battery (UI + manager + view models), Downloads UI, HUD-replacement (`OpenNotchHUD`, `InlineHUD`, `SystemEventIndicatorModifier`), `MediaKeyInterceptor`, boring.notch's Onboarding, Tips, SkyLight lock-screen window subclass (`BoringNotchSkyLightWindow.swift` + `private/CGSSpace.swift`), `XPCHelperClient/` directory (replaced by stub — see Cleanup), `Providers/CalendarServiceProviding.swift`, `TestView.swift`, `WhatsNewView.swift`, plus repo housekeeping (`.github/`, `.devcontainer/`, `crowdin.yml`).

### Identity

- Bundle id: `kr.yojeong.mangtch.new`
- Display name: `Mangtch-new`
- Sparkle: `SUFeedURL` removed from Info.plist + `SUEnableAutomaticChecks=false` (won't auto-update into stock boringNotch)
- Internal target name: `boringNotch` (unchanged — only product display name renamed; binary at `…/MacOS/boringNotch`)
- The `kr.yojeong.mangtch.new.XPCHelper` bundle id is set on the still-existing `BoringNotchXPCHelper` target shell, but the helper has no purpose now (MediaKeyInterceptor is gone). Safe to delete the target.

---

## 3. How to build / install / run

```bash
cd /Users/sarang/Projects/mangtch/mangtch-new

# Build (Release; Debug works too)
xcodebuild -project boringNotch.xcodeproj \
  -scheme boringNotch -configuration Release \
  -derivedDataPath ./build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build

# Install + run (matches the workflow in Mangtch/CLAUDE.md)
pkill -9 -x boringNotch 2>/dev/null; sleep 0.3
rm -rf /Applications/Mangtch-new.app
cp -R ./build/Build/Products/Release/boringNotch.app /Applications/Mangtch-new.app
open /Applications/Mangtch-new.app
```

The released binary runs accessory (no Dock icon). Menu-bar icon hosts Settings + Quit. Quit via `pkill -9 -x boringNotch`.

**SourceKit (Xcode indexer / IDE diagnostics) often shows false errors** like `No such module 'Defaults'` or `Cannot find type 'XYZ' in scope` for newly added files until you open the project in Xcode and let SwiftPM resolve packages. The authoritative check is `xcodebuild` — trust the actual build, not LSP red squigglies.

---

## 4. Phase log (what was done, in order)

1. **Phase 1 — Bootstrap** — copied `boring.notch/` → `mangtch-new/`, removed `.git/.github/.devcontainer/crowdin.yml`, edited `boringNotch.xcodeproj/project.pbxproj` to rename bundle ids + display name (sed against `theboringteam.boringnotch` and `INFOPLIST_KEY_CFBundleDisplayName`), pruned Sparkle SUFeedURL.
2. **Phase 2 — Strip** — deleted feature directories listed above. Fixed dangling references in 11 files. Stub-replaced `ContentView.swift` body so build compiled before Phase 3 rewrote it. Merged `BoringNotchSkyLightWindow`'s panel config (dark appearance, sharingType update) into `BoringNotchWindow`. **Slop note:** the agent created `boringNotch/managers/XPCHelperClient.swift` as a no-op stub instead of cleanly removing the references in `SettingsView`/`BoringViewCoordinator`. See "Cleanup needed".
3. **Phase 3 — Widget machinery** — added `Widgets/{NotchWidget,WidgetRegistry}.swift`, `components/Notch/{WingHitZone,FirstMouseHostingView,WingShapes}.swift`, `observers/GestureHandler.swift`, `animations/AnimationTokens.swift`, `components/Tabs/WidgetSwitcherBar.swift`. Extended `BoringViewModel` with `wingHitZones`, `hoveredWing`, `currentExpandedWidgetID`, `compactWingWidth`, `wingWidth`/`panelModeWingWidth`/`wingsFlat`/`panelWidth`. Rewrote `ContentView` with Mangtch wings + WidgetSwitcherBar. `BoringNotchWindow` content now hosted via `FirstMouseHostingView`.
4. **Phase 4 — Widget port** — copied Timer (4 files), KBO (9 files + `KBOService.swift`), and wrote thin `MusicPlayerWidget` over `MusicManager`. Registered all three in `WidgetRegistry.registerDefaults()`. Added `WingButton.kboTickerToggle/.kboTTSToggle` cases + `GestureHandler` dispatch. **The Phase 4 agent timed out partway** — the file copies happened but pbxproj registrations were missing. A follow-up executor pass added the 15 missing pbxproj entries (`MusicPlayerWidget`, 4 Timer files, 9 KBO files, `KBOService.swift`) plus the `Notification.Name.boringNotchDidOpen` declaration. **Important:** the main `boringNotch/` Xcode group is **NOT** a `PBXFileSystemSynchronizedRootGroup` — only `private/` and `BoringNotchXPCHelper/` are. New files in `boringNotch/` must be explicitly registered in the pbxproj (`PBXFileReference` + `PBXBuildFile` + Sources build phase entry).
5. **Phase 5+6 — Build, install, smoke** — Release build passes, app installs and launches. Manual UI verification surfaced the wing-sizing bug (see below).

The full original plan lives at `/Users/sarang/.claude/plans/boring-notch-dreamy-dragonfly.md`.

---

## 5. Known issues

### 🔴 Wing layout is mis-sized

Visually, opening the panel produces wings that span much wider than the configured `panelModeWingWidth`. After lowering the clamp from `min(max(half, 130), 480)` → `min(max(half, 130), 240)` (matching Mangtch's `maxWingWidth`), the wings are still wider than expected on the user's display. Last user feedback: "접히긴하는데 크기가 이상해" with a screenshot showing the top wing bar wider than the expanded panel below it.

Hypotheses to investigate:
- The wing **content** (right wing's title + 3 transport buttons) overflows the `.frame(width: vm.wingWidth, alignment: .trailing)` and `.clipped()` doesn't actually clip in this layout because the children are rendered before the frame constrains. Worth wrapping the content in a fixed-size container with `.fixedSize(horizontal: false, vertical: true)` and confirming the parent frame is honored.
- `panelWidth` (= `notchSize.width + wingWidth*2`) computes as expected but the `wingsRow` HStack doesn't actually constrain to that width because `Color.black` in the notch bar uses `.padding(.horizontal, -1)` to extend by 2px — should be cosmetically harmless but worth eliminating as a variable.
- Mangtch uses `WidgetRegistry.recomputeMaxWingWidth()` to re-derive `maxWingWidth` per-VM whenever a widget's `preferredPanelWidth` changes (KBO does this dynamically based on cached pitcher names). This logic was **not** ported. The current code uses a static `min(_, 240)` cap. KBO when active may want >240; Music wants ~130. Port `recomputeMaxWingWidth` from Mangtch's `WidgetRegistry.swift` (~line 51) and store `maxWingWidth` per-VM (currently a single `min(_, 240)`).
- ContentView's hidden measurement pass writes `vm.compactWingWidth = width` from the union of left+right wing measured widths via `MeasuredWingWidthKey` (uses `max`). If one wing is much wider than the other, `compactWingWidth` ends up too big and the closed-state wing (when `notchState == .closed`) renders too wide. Mangtch separates left/right widths.

Quickest A/B test: print `vm.wingWidth`, `vm.panelWidth`, `vm.compactWingWidth`, `vm.notchSize.width` in `BoringViewModel.open()` and `close()` to confirm the runtime values match the math; then compare to the visible bar width.

### 🟡 SettingsView still has a stub Calendar section

Phase 5 of the original plan was "trim SettingsView to remove Calendar/Battery/Webcam/HUD/Downloads sections" but only Calendar was stubbed (with `EmptyView()` ish). Other sections were already removed during Phase 2 strip. Settings opens, persists values, and the UI works — it's just visually noisy with empty sections. Low priority.

### 🟡 `XPCHelperClient.swift` is a no-op stub

`boringNotch/managers/XPCHelperClient.swift` was created during Phase 2 to satisfy lingering references in `SettingsView` (and possibly elsewhere). When you next touch SettingsView, find every `XPCHelperClient.shared.*` call site, delete it (they were all related to accessibility-authorization prompts for the deleted MediaKeyInterceptor), then delete the stub file.

### 🟡 `Notification.Name.boringNotchDidOpen` post is dead

`BoringViewModel.open()` posts `.boringNotchDidOpen`. Currently no observers — KBO's open-time refresh hooks were not wired. KBO refreshes via its own polling (via `KBOService`). Either delete the post or wire `KBOViewModel` to observe it (Mangtch parallel is `EventBus.notchDidOpen`).

### 🟡 Sparkle `SUPublicEDKey` was also removed

When `SUFeedURL` was deleted from Info.plist, `SUPublicEDKey` went with it. If we ever re-enable updates, both need to come back (with our own values, not boring.notch's).

### 🟢 SourceKit indexer false positives

`No such module 'Defaults'`, `Cannot find type 'NotchWidget'` etc. appear in IDE diagnostics for newly added files until SwiftPM resolves. Ignore unless `xcodebuild` agrees.

---

## 6. Where the design decisions live

- **`BoringViewModel.swift`** — extended in-place (per user rule "keep boring.notch class names"). Mangtch's intermediate `.hovering` state is not modelled; `notchState` stays `.closed`/`.open`. `open()` deliberately does **not** swap `notchSize` to `openNotchSize` (that was the original bug that ballooned wings to 640×190 and trapped the panel open) — `notchSize` always equals `closedNotchSize`.
- **`GestureHandler.swift`** — global `NSEvent` monitor for mouseMoved/leftMouseDown/keyDown. Hover dwell auto-opens (per `Defaults[.openNotchOnHover]` + `.minimumHoverDuration`); leaving the hover zone calls `vm.close()`. Wing clicks dispatched via `vm.wingHitZones` hit-test in screen coordinates.
- **`WingHitZone.swift`** — PreferenceKey-based; needs `\.notchHostWindow` Environment to convert SwiftUI-global coords → screen coords. AppDelegate must inject the `NSWindow` reference into the SwiftUI tree (`ContentView(hostWindow: window)` then `.environment(\.notchHostWindow, hostWindow)`). Confirm this wiring in `boringNotchApp.swift::createBoringNotchWindow` — if the env value is nil, hit-zones won't be reported correctly.
- **`WidgetRegistry.swift`** — `@Observable` singleton. Registers `MusicPlayerWidget`, `TimerWidget`, `KBOWidget` in `registerDefaults()`. Missing the `recomputeMaxWingWidth` propagation (see Known issues #1).
- **`ContentView.swift`** — the layout. Wings + notch bar + expanded panel + WidgetSwitcherBar. Hidden measurement pass for `compactWingWidth`. Pan-down opens, pan-up closes.
- **`MusicPlayerWidget.swift`** — thin SwiftUI wrapper exposing `MusicManager.shared` content for compact wings + reusing boring.notch's existing music player UI for the expanded view.

---

## 7. Reference paths

- Reference for porting: `Mangtch/Sources/components/{KBO,Timer,Music}/`, `Mangtch/Sources/Widgets/`, `Mangtch/Sources/components/Notch/`, `Mangtch/Sources/observers/`, `Mangtch/Sources/models/NotchViewModel.swift`. **Read-only** — never edit `Mangtch/`.
- Plan: `/Users/sarang/.claude/plans/boring-notch-dreamy-dragonfly.md`
- Architectural-rule memory: `/Users/sarang/.claude/projects/-Users-sarang-Projects-mangtch/memory/feedback_mangtch_new_scope.md`
- Project conventions / build workflow: `/Users/sarang/Projects/mangtch/CLAUDE.md` (the "After every code change" section's `pkill → cp → open` workflow applies here too — substitute `Mangtch.app` → `Mangtch-new.app`).

---

## 8. Recommended next steps (priority order)

1. **Fix the wing layout sizing.** Most likely culprit: port `WidgetRegistry.recomputeMaxWingWidth()` from Mangtch and convert `BoringViewModel.maxWingWidth` from a static `240` cap into a per-VM property the registry updates. Verify by printing widths at runtime.
2. **Manual smoke test the rest of the user checklist** (from `/Users/sarang/.claude/plans/boring-notch-dreamy-dragonfly.md` § Verification): hover-expand timing, music wing-button click, widget switching, KBO data fetch (Korean baseball season; service may return "no games" off-season), Timer countdown + numpad, file drag → Shelf, multi-display, fullscreen-hide.
3. **Clean up the `XPCHelperClient.swift` stub** along with the Calendar Settings stub when next touching SettingsView.
4. **Decide on the `BoringNotchXPCHelper` target.** Either delete it from pbxproj or restore the helper sources if you ever bring back media-key interception. Currently it's dead weight.
5. **Decide on `mediaremote-adapter/`.** Verify whether `MusicManager` actually loads `mediaremote-adapter.pl` / `MediaRemoteAdapter.framework` at runtime; if not, drop the directory and remove the build-phase reference.

When in doubt about scope, re-read § 1 of this document and the architectural-rule memory file.
