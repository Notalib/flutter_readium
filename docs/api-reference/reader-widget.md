# ReadiumReaderWidget

`ReadiumReaderWidget` embeds the native Readium navigator view. It requires an open `Publication`.

## Constructor

```dart
ReadiumReaderWidget(
  publication: pub,           // required — from openPublication()
  initialLocator: saved,      // optional — restores reading position
  loadingWidget: mySpinner,   // shown while the native view initialises
  shouldShowControls: true,   // whether built-in nav controls are shown
  verticalScroll: false,      // overrides scroll mode preference
  onExternalLinkActivated: (uri) { /* handle external URLs */ },
  goBackwardSemanticLabel: 'Previous page',
  goForwardSemanticLabel: 'Next page',
  toggleShowControlsSemanticLabel: 'Toggle controls',
)
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `publication` | `Publication` | required | The open publication to display |
| `initialLocator` | `Locator?` | `null` | Position to restore on open |
| `loadingWidget` | `Widget?` | `CircularProgressIndicator` | Shown while native view loads |
| `shouldShowControls` | `bool` | `true` | Show built-in navigation controls |
| `verticalScroll` | `bool?` | from preferences | Override scroll/paginated mode |
| `onExternalLinkActivated` | `void Function(Uri)?` | `null` | Called when the reader activates an external link |
| `goBackwardSemanticLabel` | `String?` | `null` | Accessibility label for the backward control |
| `goForwardSemanticLabel` | `String?` | `null` | Accessibility label for the forward control |
| `toggleShowControlsSemanticLabel` | `String?` | `null` | Accessibility label for the controls toggle |

## Platform implementations

| Platform | Implementation |
|----------|---------------|
| iOS | `UiKitView` wrapping a native `UIView` |
| macOS | Not implemented — the plugin registers on macOS but no reader view is available yet. See the README's [macOS setup section](https://github.com/notalib/flutter_readium#macos). |
| Android | `PlatformViewLink` with `AndroidViewSurface` |
| Web | JavaScript interop via `ReadiumWebView` |

## Lifecycle notes

- The widget registers itself with `FlutterReadiumPlatform.instance` on creation and deregisters on disposal.
- Screen wakelock is managed automatically while the widget is mounted.
- Dispose the owning widget (and call `closePublication()`) when navigation leaves the reader screen.
