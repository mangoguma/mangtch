# mangtch-new — Handoff

> Status (2026-05-08, branch `mangtch-new-wip`, tip `6ce8f7b`): phases 1–7 complete. Builds + runs as a `.nonactivatingPanel` accessory app. Wing/panel sizing on widget-declared `widthRange`/`heightRange` contract (§6). Visual token system (`ThemeTokens` / `TypographyTokens` / per-widget `*ThemeTokens`) covers chrome + Music/KBO/Timer. Adaptive panel shading + `Defaults[.panelAppearance]` setting. Phase 8 (Width contract closure) and 9 (multi-slot wing) are next; see `PLAN-roadmap-7-to-10.md`.

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
      NotchWidget.swift                 # NotchWidget protocol; declares widthRange / heightRange
      WidgetRegistry.swift              # @Observable singleton; registerDefaults() registers Music+Timer+KBO
    SystemBridge/
      KBOService.swift                  # PORTED — Naver KBO API client
    managers/                           # boring.notch — kept: MusicManager, ImageService,
                                        #   NotchSpaceManager, BrightnessManager, VolumeManager
                                        # plus XPCHelperClient.swift (no-op stub — see "Cleanup needed")
    MediaControllers/                   # boring.notch — all 4 (NowPlaying, Apple Music, Spotify, YT Music)
    sizing/
      matters.swift                     # boring.notch — closed/open notch size helpers, windowSize
      PanelLayoutMetrics.swift          # NEW — pure resolver: (widget, notchSize, state) → wingWidth/panelWidth/expandedHeight
      LayoutTokens.swift                # NEW — shared layout constants (corner radii, paddings, etc.)
    helpers/, extensions/, observers/, models/, animations/,
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

### ✅ Wing/panel sizing — resolved (Phase 5d)

Wing sizing is content-driven via `PanelLayoutMetrics.resolve(widget:notchSize:state:)`. The original mis-sizing (open() swapping notchSize, GestureHandler using ballooned notchSize for hover math) was fixed in Phase 5a; wing-swap flicker was killed by stable-mount of wing trees in Phase 5d. Width is currently fixed at 640 — see PLAN-content-driven-sizing.md retrospective. Dynamic width re-attempt is Phase 7+.

Architecture summary:
- `Widgets/NotchWidget.swift` — protocol declares `widthRange` / `heightRange` triples.
- `sizing/PanelLayoutMetrics.swift` — single resolver. Pure function, no measurement pass.
- `models/BoringViewModel.swift` — exposes `metrics` (computed) + `publishedMetrics` (Combine mirror via `recomputeMetrics()` + `withObservationTracking` so `@Observable` widget state re-fires).
- `ContentView.swift` — reads `vm.metrics.{wingWidth, panelWidth}` directly; animations drive off `panelWidth` value change.
- Wing tree stability: ContentView mounts wing subtrees with stable identity so widget swaps don't churn AppKit views.

### 🟡 SettingsView still has a stub Calendar section

Phase 5 of the original plan was "trim SettingsView to remove Calendar/Battery/Webcam/HUD/Downloads sections" but only Calendar was stubbed (with `EmptyView()` ish). Other sections were already removed during Phase 2 strip. Settings opens, persists values, and the UI works — it's just visually noisy with empty sections. Low priority.

### 🟡 `XPCHelperClient.swift` is a no-op stub

`boringNotch/managers/XPCHelperClient.swift` was created during Phase 2 to satisfy lingering references in `SettingsView` (and possibly elsewhere). When you next touch SettingsView, find every `XPCHelperClient.shared.*` call site, delete it (they were all related to accessibility-authorization prompts for the deleted MediaKeyInterceptor), then delete the stub file.

### ✅ `Notification.Name.boringNotchDidOpen` — wired

`BoringViewModel.open()` posts `.boringNotchDidOpen`; `KBOViewModel.swift:183` subscribes for open-time refresh. (Earlier handoff incorrectly described the post as dead.)

### 🟡 Sparkle `SUPublicEDKey` was also removed

When `SUFeedURL` was deleted from Info.plist, `SUPublicEDKey` went with it. If we ever re-enable updates, both need to come back (with our own values, not boring.notch's).

### 🟢 SourceKit indexer false positives

`No such module 'Defaults'`, `Cannot find type 'NotchWidget'` etc. appear in IDE diagnostics for newly added files until SwiftPM resolves. Ignore unless `xcodebuild` agrees.

---

## 6. Where the design decisions live

- **`BoringViewModel.swift`** — extended in-place (per user rule "keep boring.notch class names"). Mangtch's intermediate `.hovering` state is not modelled; `notchState` stays `.closed`/`.open`. `open()` deliberately does **not** swap `notchSize` to `openNotchSize` — `notchSize` always equals `closedNotchSize`. Sizing is exposed via `metrics: PanelLayoutMetrics` (computed) + `publishedMetrics: PanelLayoutMetrics?` (Combine-published mirror). `recomputeMetrics()` uses `withObservationTracking` so `@Observable` widget state (KBO games/linescore) also re-fires resolution.
- **`sizing/PanelLayoutMetrics.swift`** — **the single resolver for layout sizing.** Pure function `resolve(widget:notchSize:state:) -> PanelLayoutMetrics` clamps the active widget's `widthRange.ideal` into `[min, max]` and returns `wingWidth` / `panelWidth` / `expandedHeight`. There is **no** measurement pass and **no** static clamp constant. Widgets are the single source of truth for their size.
- **`Widgets/NotchWidget.swift`** — `NotchWidget` protocol declares `widthRange: WidthRange` and `heightRange: HeightRange` (both `(min, ideal, max)` triples). Use `WidthRange.fixed(_)` for pixel-design canvases (Music = 380), or `WidthRange(min: 320, ideal: 480, max: 640)` defaults for flex widgets. KBO computes its range dynamically from cached pitcher-name widths + inning grid.
- **`Widgets/WidgetRegistry.swift`** — `@Observable` singleton. Registers `MusicPlayerWidget`, `TimerWidget`, `KBOWidget` in `registerDefaults()`. Pure registry — does **not** propagate sizing. Sizing is read by `BoringViewModel.metrics` from the active widget directly.
- **`GestureHandler.swift`** — global `NSEvent` monitor for mouseMoved/leftMouseDown/keyDown. Hover dwell auto-opens (per `Defaults[.openNotchOnHover]` + `.minimumHoverDuration`); leaving the hover zone calls `vm.close()`. **Hover zone extends downward by `extraOpenHeight = 260` when open** so cursor moves into the expanded panel don't trigger close. Uses `vm.closedNotchSize` (not `notchSize`) for hover-zone math. Wing clicks dispatched via `vm.wingHitZones` hit-test in screen coordinates.
- **`WingHitZone.swift`** — PreferenceKey-based; needs `\.notchHostWindow` Environment to convert SwiftUI-global coords → screen coords. AppDelegate must inject the `NSWindow` reference into the SwiftUI tree (`ContentView(hostWindow: window)` then `.environment(\.notchHostWindow, hostWindow)`). Confirm this wiring in `boringNotchApp.swift::createBoringNotchWindow` — if the env value is nil, hit-zones won't be reported correctly.
- **`ContentView.swift`** — the layout. Wings + notch bar + expanded panel + WidgetSwitcherBar. Reads `vm.metrics.{wingWidth, panelWidth}` directly. Animation driven off `m.panelWidth` value change. Pan-down opens, pan-up closes.
- **`MusicPlayerWidget.swift`** — thin SwiftUI wrapper exposing `MusicManager.shared` content for compact wings + reusing boring.notch's existing music player UI for the expanded view. Uses `WidthRange.fixed(380)` since the player UI is pixel-designed.

---

## 7. Reference paths

- Reference for porting: `Mangtch/Sources/components/{KBO,Timer,Music}/`, `Mangtch/Sources/Widgets/`, `Mangtch/Sources/components/Notch/`, `Mangtch/Sources/observers/`, `Mangtch/Sources/models/NotchViewModel.swift`. **Read-only** — never edit `Mangtch/`.
- Plan: `/Users/sarang/.claude/plans/boring-notch-dreamy-dragonfly.md`
- Architectural-rule memory: `/Users/sarang/.claude/projects/-Users-sarang-Projects-mangtch/memory/feedback_mangtch_new_scope.md`
- Project conventions / build workflow: `/Users/sarang/Projects/mangtch/CLAUDE.md` (the "After every code change" section's `pkill → cp → open` workflow applies here too — substitute `Mangtch.app` → `Mangtch-new.app`).

---

## 8. Recommended next steps (priority order)

Phases 1–7 complete (base `89b188a` → tip `6ce8f7b`, all on `mangtch-new-wip`). See `PLAN-roadmap-7-to-10.md §12` for the phase 7 retrospective and `§4–§5` for the phase 8/9 specs that are still in scope.

1. **Phase 8 — Width contract closure** (~6-8h). NSAnimation ↔ SwiftUI ease sync (or option B: window jumps instant, SwiftUI eases content). Restore content-driven widthRange for KBO + Music. See roadmap §4.
2. **Phase 9 — Multi-slot wing** (~6-8h). Independent left/right active widget per `BoringViewModel.{leftActiveWidgetID, rightActiveWidgetID}`. **Blocked on three user decisions** (roadmap §5.2): per-wing active widget UI location, default behaviour, conflict resolution. Don't start without these.
3. **Phase 10a — Widget contributor guide** (docs only, ~1-2h). `docs/ADDING_A_WIDGET.md` + Widget template. Cheapest sub-PR.
4. Visually reverify wing/panel sizing per user's display setup.
5. Smoke test the user checklist (`/Users/sarang/.claude/plans/boring-notch-dreamy-dragonfly.md` § Verification).
6. **`mediaremote-adapter/` is in use** — `NowPlayingController.swift:193` and `MediaChecker.swift:20` reference it at runtime. Do not delete.

### Phase 7 deliverables already in tree (don't re-do)

- `sizing/ThemeTokens.swift` — chrome colours, light/dark variants, `panelBackground(systemDark:)` / `wingFill(systemDark:)` selectors
- `sizing/TypographyTokens.swift` — ~25 semantic fonts
- `components/{Music,KBO,Timer}/*ThemeTokens.swift` — widget-scoped colour tokens (KBO has `rowBaselineTint` for row composition under jet-black panel)
- `BoringViewModel.systemIsDark` (@Published) + `AppleInterfaceThemeChangedNotification` observer + `Defaults[.panelAppearance]` override
- Settings → Appearance → Panel section (system / light / dark picker)
- ContentView `.dynamicTypeSize(...DynamicTypeSize.large)` clamp

### Conventions for new view code (post-phase 7)

- Never write `Color(white: …)`, `.foregroundStyle(.secondary.opacity(N))`, `font(.system(size: N))` inline. Add to the relevant `*Tokens.swift` first, then use the token. Plan §3.10.1 still applies — leave boring.notch upstream files (`NotchHomeView`, `MusicPlayerView`, `MusicControlsView`, `MusicVisualizer`, `AnimatedFace`, `Button+Bouncing`) alone.
- KBO/Music/Timer-specific colours go in their respective `*ThemeTokens.swift`, not in global `ThemeTokens`.
- Panel-shade-aware colour decisions read `vm.systemIsDark` (already injected as @EnvironmentObject in widget views).

When in doubt about scope, re-read § 1 of this document and the architectural-rule memory file.
