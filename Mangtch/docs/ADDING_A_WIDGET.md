# Adding a Widget

> Audience: anyone adding a new widget to Mangtch (KBO/Music/Timer-class
> chrome). The contract is enforced by `NotchWidget` (see protocol docstring
> in `boringNotch/Widgets/NotchWidget.swift`); this guide is the procedural
> companion.

## TL;DR — 5 steps

1. Create `boringNotch/components/<Widget>/` with 3 files: `<Widget>Widget.swift`,
   `<Widget>LayoutTokens.swift`, `<Widget>ThemeTokens.swift` (+ `<Widget>ViewModel.swift`
   if you have state).
2. Conform a `final class <Widget>: NotchWidget` — declare `wingPriority`,
   `claimsWings`, `widthRange`, `heightRange`, plus the three view factories.
3. Build both wing views (mandatory pair) and one expanded view. Route every
   color through `<Widget>ThemeTokens` and every font through `TypographyTokens`.
4. Register in `WidgetRegistry.registerDefaults()` — pick a unique
   `wingPriority` (the registry asserts).
5. Build, run, and walk the verification scenarios in §6.

`TimerWidget` is the smallest reference — read it before you start.

---

## 1. Directory layout

```
boringNotch/components/<Widget>/
├── <Widget>Widget.swift          // NotchWidget conformer + wing/expanded view structs
├── <Widget>LayoutTokens.swift    // sizing/spacing magic numbers
├── <Widget>ThemeTokens.swift     // domain-specific colors
└── <Widget>ViewModel.swift       // optional, @Observable
```

Add the new files to the Xcode project (`boringNotch.xcodeproj`) — drag into
the matching group in the navigator. The `pbxproj` will pick them up.

> ⚠ Do **not** add files under `boringNotch/Lib/`, `boringNotch/Components/Notch/`,
> or other paths owned by upstream boring.notch. Mangtch features live only in
> `components/<Widget>/`, `Widgets/`, `models/`, `sizing/`. (See repo-root
> `CLAUDE.md` and `MEMORY.md` for the boring.notch scope rule.)

---

## 2. Conform to `NotchWidget`

Minimal skeleton:

```swift
@MainActor
final class HelloWidget: NotchWidget {
    let id = "hello"
    let displayName = "Hello"
    let icon = "hand.wave"
    var isEnabled = true

    // Pick an unused integer. Existing widgets:
    //   Timer = 20  (highest — explicit user countdown)
    //   KBO   = 10
    //   Music = 1   (floor — always claims when nothing else does)
    let wingPriority: Int = 5

    @MainActor
    var claimsWings: Bool { /* state-driven boolean */ true }

    var widthRange: WidthRange {
        WidthRange(min: 360, ideal: 480, max: LayoutTokens.panelMaxWidth)
    }
    var heightRange: HeightRange {
        HeightRange(min: 120, ideal: 160, max: 220)
    }

    @MainActor func makeLeftWingView() -> AnyView  { AnyView(HelloLeftWing())  }
    @MainActor func makeRightWingView() -> AnyView { AnyView(HelloRightWing()) }
    @MainActor func makeExpandedView() -> AnyView  { AnyView(HelloExpandedView()) }

    func activate()   {}
    func deactivate() {}
}
```

### `claimsWings` — the priority chain

`claimsWings` is read on every observation tick. It must depend only on state
exposed via `@Observable`/`@Published` — otherwise the wing-owner won't
recompute when your answer changes. Pattern:

```swift
@MainActor
var claimsWings: Bool {
    viewModel.isActive            // observed
    || viewModel.state == .alert  // observed
}
```

If it should never claim (e.g. Settings-style chrome), set `wingPriority = 0`
and return `false`.

### `widthRange` — state-aware

The chrome consults `widthRange` two different ways:

- **Closed panel** → wing-owner's `widthRange`
- **Open panel** → panel-selected widget's `widthRange`

So your widget's `widthRange` must produce a sensible result both as wing
owner (closed) and as the user's panel selection (open). When in doubt,
`.fixed(LayoutTokens.panelMaxWidth)` keeps wing geometry stable across
widget swaps.

### `heightRange` — formula fallback only

This is **not** the source of truth for panel height. Real height comes from
`GeometryReader` measurement of `makeExpandedView()` (see `BoringViewModel.measuredExpandedContentHeight`).
`heightRange` is used:

- on the very first frame (before measurement settles)
- as a safety floor when measurement hasn't arrived

→ Make your expanded view's intrinsic height honest (see §3).

---

## 3. Building the views

### Wing pair (mandatory)

Both wings are built once at registration and stable-mounted by the chrome.
Owner swaps are opacity toggles, not remounts — internal state survives.
Implication: your wing views' `init` runs **once**, before `activate()`.

Don't put expensive work in the wing view body. Subscribe to your view model
inside `body` via `@ObservedObject`/`@Bindable` so updates flow through.

```swift
struct HelloLeftWing: View {
    @ObservedObject var viewModel: HelloViewModel
    var body: some View {
        Image(systemName: "hand.wave")
            .font(TypographyTokens.compactGlyph)
            .foregroundStyle(HelloThemeTokens.accent)
            .padding(.horizontal, HelloLayoutTokens.compactPadding)
    }
}
```

### Expanded view — sizing rules

The expanded view's intrinsic height drives the NSPanel resize. Therefore:

- **Do not** wrap the body in a greedy `.frame(maxHeight:)` ceiling. SwiftUI
  flex-frames absorb the parent's proposal up to that ceiling, the GR reads
  the absorbed (oversized) value, and the panel locks at the ceiling instead
  of the actual content height.
- **Do** use `.frame(minHeight:)` to give variable layouts (empty state,
  loading state) a visually-decent floor — the bottom corner radius needs
  breathing room.
- For scrolling content (>5 rows expected), wrap the inner stack in a
  `ScrollView` clamped by `.frame(maxHeight: m.contentHeight - chrome)` and
  apply `.fixedSize(horizontal: false, vertical: true)` to the inner stack
  so it reports its true height when shorter than the cap. (KBO's
  `gamesScroller` is the reference.)

### Tokens

| Use case | Token source |
|---|---|
| Color (chrome) | `ThemeTokens` (`sizing/ThemeTokens.swift`) |
| Color (your widget) | `<Widget>ThemeTokens` |
| Font (any) | `TypographyTokens` (`sizing/TypographyTokens.swift`) |
| Sizing/spacing | `<Widget>LayoutTokens` (or `LayoutTokens` for chrome) |

No raw `Color.white`, `Color(white: 0.X)`, or `.font(.system(size: N))` in
your widget files.

### Animation

Use `.easeInOut(duration: 0.22)` for state-driven reflows in the expanded
view. The NSPanel resize uses bezier `(0.42, 0, 0.58, 1.0)` which matches
SwiftUI `easeInOut` exactly, so wings, panel chrome, and your content stay
in lockstep.

---

## 4. Register

Add to `WidgetRegistry.registerDefaults()`:

```swift
func registerDefaults() {
    register(MusicPlayerWidget())
    register(TimerWidget())
    register(KBOWidget())
    register(HelloWidget())   // ← here
    applyPersistedOrder()
}
```

`register(_:)` asserts `wingPriority` uniqueness — duplicates trigger an
assertion in dev builds. If you hit it, pick a different number.

---

## 5. Verify

```bash
cd Mangtch
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Then `cp -R build/Build/Products/Release/Mangtch.app /Applications/` and
relaunch.

---

## 6. Verification scenarios

Walk all of these before marking done:

- [ ] Widget appears in `WidgetSwitcherBar` (Settings → Widgets toggle on)
- [ ] User picks your widget in the picker → panel opens with your expanded view
- [ ] State that flips `claimsWings` to true → wings swap to your widget (no flicker — phase 5d stable-mount handles this for free)
- [ ] State that flips `claimsWings` back to false → wings hand off to next-priority widget
- [ ] Higher-priority widget claims while yours is active → yours yields wings, panel selection (if user picked you) stays
- [ ] Resize the expanded view (state change that grows/shrinks intrinsic) → panel resizes single-step (no two-step jitter — phase 9c-tail)
- [ ] Empty/loading state in expanded view doesn't clip the bottom corner radius

---

## 7. Pitfalls

1. **boring.notch files are off-limits.** Don't edit `NotchHomeView`,
   `MusicPlayerView`, `MusicControlsView`, `MusicVisualizer`, `AnimatedFace`,
   `Button+Bouncing`, or anything under `Settings/`/`Shelf/` for color/font
   token migration. Those are upstream-tracked.
2. **Greedy `.frame(maxHeight:)` in the expanded view.** Locks the panel at
   the formula's pessimistic budget. Use `.frame(minHeight:)` instead.
3. **`Color.clear` height bloat.** A `Color.clear` cell without an explicit
   `.frame(height:)` is height-greedy and inflates row heights. Always
   `Color.clear.frame(height: 0)` or give it a fixed dimension.
4. **`claimsWings` reading non-observed state.** If your boolean depends on
   a plain `var` or a derived value, the chain won't recompute. Move the
   dependency under `@Observable` or `@Published`.
5. **Single-wing widget.** Both wings are required. If you genuinely only
   have content for one side, mirror it (Music's right wing is title/artist;
   Timer's right wing is digits — both are real).
6. **Wing view side effects in `init`.** Wings are built once at registration,
   before `activate()`. Lifecycle setup belongs in `activate()`/`deactivate()`
   on the widget class, not in the view.

---

## 8. References

- `boringNotch/Widgets/NotchWidget.swift` — protocol contract docstring
- `boringNotch/components/Timer/TimerWidget.swift` — smallest reference
- `boringNotch/components/KBO/KBOWidget.swift` — content-driven width example
- `boringNotch/components/Music/MusicPlayerWidget.swift` — fixed-canvas example
