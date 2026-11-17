# flutter_readium_lcp

Readium LCP add-on for [`flutter_readium`](https://pub.dev/packages/flutter_readium) on iOS and Android. It opens LCP-protected EPUB, audiobook and PDF publications, asks your Dart code for the passphrase, acquires a publication from a `.lcpl` license, and reads license info.

LCP decryption needs EDRLab's private client library (`R2LCPClient` on iOS, `liblcp` on Android). It is only available to registered reading apps, this package never contains it, and your app must supply it. Without it, `FlutterReadiumLcp.isAvailable()` returns false.

Not covered: web, and renewing a loan through a web page.

```dart
final lcp = FlutterReadiumLcp();
lcp.setPassphraseProvider((request) async => askUserForPassphrase(request));
final publication = await FlutterReadium().openPublication(path);
```

Setup per platform, error handling, how `loadPublication` differs from `openPublication`, and how to run the example with the test client are in the [LCP guide](https://github.com/Notalib/flutter_readium/blob/main/docs/guides/lcp.md).
