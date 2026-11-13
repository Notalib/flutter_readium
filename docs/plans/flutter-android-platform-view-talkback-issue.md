# Flutter engine issue draft: TalkBack skips platform views with a plain root

Status: filed as [flutter/flutter#196560](https://github.com/flutter/flutter/issues/196560), with the engine fix proposed in [flutter/flutter#196567](https://github.com/flutter/flutter/pull/196567) and a minimal repro at [ddfreiling/flutter-platform-view-a11y-repro](https://github.com/ddfreiling/flutter-platform-view-a11y-repro). The filed issue supersedes the text below where they differ. Found while adding `ReadiumReaderWidget.allowScreenReaderNavigation`; the plugin works around it with `ReaderLayout` in `ReadiumReaderWidget.kt`. Remove the workaround when the engine fix has reached the minimum supported Flutter version.

## Title

[Android] TalkBack swipe navigation skips a platform view whose root is a plain ViewGroup

## Summary

With hybrid composition or texture-layer hybrid composition, `AccessibilityBridge` links the platform view into Flutter's virtual node tree with `result.addChild(embeddedView)` and sets `embeddedView.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_AUTO)`.

Under `AUTO`, `View.isImportantForAccessibility()` is true only for a view that is actionable, has accessibility listeners, has a node provider, is a live region or is a pane. A plain container such as a `LinearLayout` or `FrameLayout` is none of these.

An accessibility service that does not set `FLAG_INCLUDE_NOT_IMPORTANT_VIEWS` (TalkBack) gets no node for an unimportant view. In a normal view hierarchy the framework skips the container and reports its important descendants instead. Here the child link points at the container itself, so the link is dead and the whole platform view subtree is missing from the service's tree.

## Observed

- Device: Samsung S23, Android 17, TalkBack 17.1. Flutter 3.47.2.
- Platform view root: `LinearLayout` containing a fragment with a `WebView`.
- `uiautomator dump` (includes unimportant views): the WebView and its text nodes are present, 36 nodes.
- `uiautomator dump --compressed` (important views only): no WebView, 17 nodes.
- TalkBack swipe next/previous skips the platform view in both directions.
- TalkBack touch exploration does focus the text, because hover events reach the real views directly. From there swipe navigation works inside the WebView and can leave it, but cannot re-enter.

A platform view whose root is itself important under `AUTO` (for example a `WebView`, which has a node provider) is not affected.

## Where

`shell/platform/android/io/flutter/view/AccessibilityBridge.java`, both places that set the embedded view to `IMPORTANT_FOR_ACCESSIBILITY_AUTO`: in `createAccessibilityNodeInfo` before `result.addChild(embeddedView)`, and in `updateSemantics` for nodes with a `platformViewId`.

## Proposed fix

Use `View.IMPORTANT_FOR_ACCESSIBILITY_YES` in both places. Flutter has already decided the view belongs in the tree by adding it as a child, so the link target must resolve for every service. `removeSemanticsNode` already sets `NO_HIDE_DESCENDANTS` when the node goes away, so hiding is unaffected.

Risk to check in review: a container forced to `YES` becomes a node TalkBack may consider for focus. A container without text or actions is not focusable by TalkBack's own rules, and this matched what we saw with the workaround below.

## Workaround for plugin authors

Return a root view that stores `YES` whenever the bridge sets `AUTO`. A value set once on the view is overwritten by the bridge.

```kotlin
class Root(context: Context) : FrameLayout(context) {
    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_AUTO
    }

    override fun setImportantForAccessibility(mode: Int) =
        super.setImportantForAccessibility(
            if (mode == IMPORTANT_FOR_ACCESSIBILITY_AUTO) IMPORTANT_FOR_ACCESSIBILITY_YES else mode,
        )
}
```

## Not verified

- The device run used an earlier workaround that overrode `getImportantForAccessibility()` and `isImportantForAccessibility()`. The setter variant above is covered by unit tests only.
- No minimal Flutter repro app yet; evidence is from flutter_readium's example app only.
- Other Android versions and other screen readers.
- Whether an existing flutter/flutter issue already covers this. Search before filing.
