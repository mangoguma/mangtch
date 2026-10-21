//
//  MenuBarHider.swift
//  boringNotch
//
//  Hidden Bar–style menu bar decluttering. Items the user ⌘-drags to the
//  left of the hider's boundary are hidden when collapsed.
//
//  Two mechanisms, picked at runtime:
//  - macOS 27+: macOS ejects an over-wide status item instead of letting it
//    push its neighbours off-screen, so length inflation no longer hides
//    anything. Instead, the menu-bar visibility restriction behind assessment
//    mode (private MenuBarClientCore) is asked to show only the apps right of
//    the arrow. Needs Accessibility to read where each app's items sit.
//    Ported from Hidden Bar v1.11.1 (MIT, dwarvesf/hidden).
//  - Earlier macOS: a separator item stretched to a huge length pushes the
//    items left of it off-screen.
//

import AppKit
import ApplicationServices
import Combine
import Defaults

@MainActor
final class MenuBarHider {
    static let shared = MenuBarHider()

    private static let collapsedLength: CGFloat = 10_000
    private static let separatorLength: CGFloat = 8
    private static let autoCollapseDelay: TimeInterval = 10

    private var toggleItem: NSStatusItem?
    /// Legacy mechanism only; on macOS 27 the arrow itself is the boundary.
    private var separatorItem: NSStatusItem?
    private var autoCollapseTimer: Timer?
    private var observers: Set<AnyCancellable> = []
    private var assertion: NativeMenuBarVisibility.Assertion?
    /// Bumped by every collapse/expand so a slow Accessibility walk or
    /// activation that finishes after the user changed their mind is dropped.
    private var generation = 0
    private var hasRequestedAccessibility = false
    private let usesNativeVisibility = NativeMenuBarVisibility.isAvailable
    private(set) var isCollapsed = false

    private init() {}

    func start() {
        Defaults.publisher(.menuBarHiderEnabled)
            .sink { [weak self] change in
                Task { @MainActor in
                    change.newValue ? self?.install() : self?.uninstall()
                }
            }
            .store(in: &observers)
    }

    func toggle() {
        guard toggleItem != nil else { return }
        isCollapsed ? expand() : collapse()
    }

    private func install() {
        guard toggleItem == nil else { return }

        // New status items are inserted to the left of existing ones, so
        // creating the toggle first lands the separator on its left. The
        // autosave names keep whatever order the user ⌘-drags them into.
        let toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggle.autosaveName = "MangtchMenuBarHiderToggle"
        if let button = toggle.button {
            button.target = self
            button.action = #selector(toggleClicked)
        }
        toggleItem = toggle

        if !usesNativeVisibility {
            let separator = NSStatusBar.system.statusItem(withLength: Self.separatorLength)
            separator.autosaveName = "MangtchMenuBarHiderSeparator"
            separator.button?.image = Self.separatorImage()
            separator.button?.toolTip = String(localized: "Menu bar items left of this line are hidden")
            separatorItem = separator
        }

        expand()
        // Status item windows have no on-screen frame until the menu bar
        // lays them out, and both mechanisms need the arrow's real position.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.collapse()
        }
    }

    private func uninstall() {
        expand()
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
        if let separatorItem { NSStatusBar.system.removeStatusItem(separatorItem) }
        if let toggleItem { NSStatusBar.system.removeStatusItem(toggleItem) }
        separatorItem = nil
        toggleItem = nil
    }

    @objc private func toggleClicked() {
        toggle()
    }

    private func collapse() {
        guard toggleItem != nil else { return }
        generation += 1
        if usesNativeVisibility {
            collapseNatively(generation: generation)
        } else {
            // If the user dragged the separator right of the toggle, stretching
            // it would push the toggle itself off-screen with no way back.
            guard separatorIsLeftOfToggle() else { return }
            separatorItem?.length = Self.collapsedLength
            separatorItem?.button?.image = nil
            setCollapsedPresentation(true)
        }
    }

    private func expand() {
        generation += 1
        assertion?.invalidate()
        assertion = nil
        separatorItem?.length = Self.separatorLength
        separatorItem?.button?.image = Self.separatorImage()
        setCollapsedPresentation(false)
    }

    private func collapseNatively(generation: Int) {
        guard AXIsProcessTrusted() else {
            // Without Accessibility the sections can't be read, and guessing
            // would hide icons the user kept visible. Prompt once per launch so
            // we don't nag while they're still in System Settings.
            if !hasRequestedAccessibility {
                hasRequestedAccessibility = true
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            return
        }
        guard let boundary = toggleItem?.button?.window?.frame else { return }

        // Only app bundles own status items; skipping helpers keeps the walk short.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && $0.bundleURL?.pathExtension == "app" }
            .compactMap { app in app.bundleIdentifier.map { (pid: app.processIdentifier, bundleID: $0) } }

        Task.detached(priority: .userInitiated) {
            let visible = Self.bundlesRightOf(boundary.midX, apps: apps)
            await MainActor.run {
                guard generation == self.generation else { return }
                let allowed = [Bundle.main.bundleIdentifier].compactMap { $0 } + visible
                NativeMenuBarVisibility.activate(allowedBundleIdentifiers: allowed) { assertion in
                    guard generation == self.generation else {
                        assertion?.invalidate()
                        return
                    }
                    // Fail open: never leave the arrow claiming "collapsed"
                    // while nothing is actually hidden.
                    guard let assertion else { return }
                    self.assertion?.invalidate()
                    self.assertion = assertion
                    self.setCollapsedPresentation(true)
                }
            }
        }
    }

    /// Bundles with at least one status item right of `boundaryX`. Hiding is
    /// per bundle, so the most visible item wins — an icon the user kept
    /// visible is never hidden because a sibling sits in the hidden section.
    /// macOS's own items (clock, Wi-Fi…) are kept separately via system item IDs.
    nonisolated private static func bundlesRightOf(
        _ boundaryX: CGFloat, apps: [(pid: pid_t, bundleID: String)]
    ) -> [String] {
        var visible: Set<String> = []
        for app in apps {
            let element = AXUIElementCreateApplication(app.pid)
            // The default timeout is seconds per app; one hung app would stall
            // the collapse for a long time.
            AXUIElementSetMessagingTimeout(element, 0.1)
            var barValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &barValue) == .success,
                  let bar = barValue else { continue }
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else { continue }
            for child in children {
                var positionValue: CFTypeRef?
                var sizeValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &positionValue) == .success,
                      AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeValue) == .success
                else { continue }
                var position = CGPoint.zero
                var size = CGSize.zero
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                // AX uses a top-left origin and AppKit bottom-left, but x is
                // the same in both, and only x decides the section.
                if position.x + size.width / 2 > boundaryX {
                    visible.insert(app.bundleID)
                }
            }
        }
        return visible.sorted()
    }

    private func setCollapsedPresentation(_ collapsed: Bool) {
        isCollapsed = collapsed
        toggleItem?.button?.image = NSImage(
            systemSymbolName: collapsed ? "chevron.left" : "chevron.right",
            accessibilityDescription: collapsed
                ? String(localized: "Show hidden menu bar items")
                : String(localized: "Hide menu bar items")
        )

        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
        if !collapsed && toggleItem != nil && Defaults[.menuBarHiderAutoCollapse] {
            autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: Self.autoCollapseDelay, repeats: false) { _ in
                Task { @MainActor in MenuBarHider.shared.collapse() }
            }
        }
    }

    private func separatorIsLeftOfToggle() -> Bool {
        guard let separatorX = separatorItem?.button?.window?.frame.minX,
              let toggleX = toggleItem?.button?.window?.frame.minX
        else { return false }
        return separatorX < toggleX
    }

    private static func separatorImage() -> NSImage {
        let size = NSSize(width: 2, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            return true
        }
        // Template so the line follows the menu bar's light/dark tint.
        image.isTemplate = true
        return image
    }
}

/// Runtime bridge to MenuBarClientCore's assessment-mode restriction, which
/// limits the menu bar to an allow-list. Resolved dynamically so a macOS
/// release that changes or removes it degrades to "unavailable" instead of
/// failing at launch.
enum NativeMenuBarVisibility {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configurationInit = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")
    /// Unknown system item IDs are ignored, so the range covers items a given
    /// Mac doesn't have (Hidden Bar checked 0–63 on 27.0).
    private static let systemItemsToKeep: [NSNumber] = (0..<64).map { NSNumber(value: $0) }

    final class Assertion {
        private var raw: NSObject?

        fileprivate init(raw: NSObject) {
            self.raw = raw
        }

        func invalidate() {
            guard let raw else { return }
            self.raw = nil
            _ = raw.perform(NativeMenuBarVisibility.invalidateSelector)
        }

        deinit {
            invalidate()
        }
    }

    static let isAvailable: Bool = {
        guard dlopen(frameworkPath, RTLD_NOW | RTLD_LOCAL) != nil,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type
        else { return false }
        return configuration.instancesRespond(to: configurationInit)
            && assertion.instancesRespond(to: activateSelector)
            && assertion.instancesRespond(to: invalidateSelector)
    }()

    /// Hides every app's status items except `allowedBundleIdentifiers` and
    /// macOS's own items. The restriction lasts until the returned assertion
    /// is invalidated or this process exits. `completion` runs on the main
    /// actor with nil on failure.
    @MainActor
    static func activate(
        allowedBundleIdentifiers: [String],
        completion: @escaping @MainActor (Assertion?) -> Void
    ) {
        guard isAvailable,
              let configurationClass = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              let assertionClass = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type
        else { return completion(nil) }

        // `alloc` hands back +1 that `init…` consumes, and `init…` returns +1:
        // leave the first unretained and take the second retained to balance.
        // Both arguments must be NSArrays — the framework indexes into them.
        let allocated = configurationClass.perform(NSSelectorFromString("alloc")).takeUnretainedValue()
        guard let configuration = allocated.perform(
            configurationInit,
            with: systemItemsToKeep as NSArray,
            with: allowedBundleIdentifiers as NSArray
        )?.takeRetainedValue() else { return completion(nil) }

        let raw = assertionClass.init()
        let handler: @convention(block) (NSError?) -> Void = { error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let error {
                        NSLog("MenuBarHider: activation failed: \(error.localizedDescription)")
                        completion(nil)
                    } else {
                        completion(Assertion(raw: raw))
                    }
                }
            }
        }
        _ = raw.perform(activateSelector, with: configuration, with: handler)
    }
}
