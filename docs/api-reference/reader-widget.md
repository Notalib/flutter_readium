# ReadiumReaderWidget

`ReadiumReaderWidget` embeds the native Readium navigator view. It requires an open `Publication`.

## Constructor

```dart
ReadiumReaderWidget(
  publication: pub,           // required — from openPublication()
  initialLocator: saved,      // optional — restores reading position
  loadingWidget: mySpinner,   // shown while the native view initialises
  fontFamilyDeclarations: [
    ReaderFontFamily(
      name: 'Atkinson Hyperlegible',
      fallbacks: ['sans-serif'],
      faces: [
        ReaderFontFace(asset: 'assets/fonts/Atkinson-Regular.ttf'),
        ReaderFontFace(
          asset: 'assets/fonts/Atkinson-Bold.ttf',
          weight: 700,
        ),
      ],
    ),
  ],
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
| `fontFamilyDeclarations` | `List<ReaderFontFamily>` | `[]` | Static Flutter font assets available to EPUB/WebPub font-family preferences |
| `shouldShowControls` | `bool` | `true` | Show built-in navigation controls |
| `verticalScroll` | `bool?` | from preferences | Override scroll/paginated mode |
| `onExternalLinkActivated` | `void Function(Uri)?` | `null` | Called when the reader activates an external link |
| `goBackwardSemanticLabel` | `String?` | `null` | Accessibility label for the backward control |
| `goForwardSemanticLabel` | `String?` | `null` | Accessibility label for the forward control |
| `toggleShowControlsSemanticLabel` | `String?` | `null` | Accessibility label for the controls toggle |

## Platform implementations

| Platform | Implementation |
|----------|---------------|
| Android | `PlatformViewLink` with `AndroidViewSurface` |
| iOS | `UiKitView` wrapping a native `UIView` |
| macOS (desktop) | Not supported — stub registered on `flutter run -d macos`; for Mac users, ship the iOS build via "Designed for iPad" |
| Web | JavaScript interop via `ReadiumWebView` |

## Custom fonts

Declare font assets in the app's `pubspec.yaml`, pass matching
`ReaderFontFamily` values when creating the widget, then use the family's
`name` in `EPUBPreferences.fontFamily`. Declarations are fixed for the lifetime
of the reader widget; recreate the widget to change them.

Only static Flutter assets are supported. Network/downloadable fonts and
runtime mutation of declarations are not supported.

## Lifecycle notes

- The widget registers itself with `FlutterReadiumPlatform.instance` on creation and deregisters on disposal.
- Screen wakelock is managed automatically while the widget is mounted.
- Dispose the owning widget (and call `closePublication()`) when navigation leaves the reader screen.
