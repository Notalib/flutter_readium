# Readium LCP

The optional `flutter_readium_lcp` package adds [Readium LCP](https://www.edrlab.org/projects/readium-lcp/) support to `flutter_readium` on iOS and Android. It opens LCP-protected EPUB, audiobook (`.lcpa`) and PDF (`.lcpdf`) publications, asks your Dart code for the passphrase, acquires a publication from a license document (`.lcpl`), and reads license facts. `flutter_readium` itself has no LCP dependency.

## What is covered

- Opening LCP publications through the normal `openPublication`, with a passphrase prompt driven from Dart.
- Typed errors for a missing or wrong passphrase, an invalid license, a license status failure (expired, revoked, returned, cancelled, not started) and network failures.
- Acquiring a publication from a `.lcpl` file, with download progress.
- License info: provider, dates, rights, remaining copy and print allowance, status, and whether the loan can be renewed or returned.
- Renewing and returning a loan through the license status server, with typed errors.

## What is not covered

- Renewing a loan through a web page. The plugin always asks the toolkit for a programmatic renewal, and fails with `LcpRenewWebPageException` (carrying the URL) if the provider only offers a web page.
- Web. The plugin has no web implementation. `FlutterReadiumLcp.isAvailable()` returns false there, and the other calls throw `UnsupportedError`.
- Production use out of the box. LCP needs EDRLab's private client library, which this repository never contains or depends on (see below).
- The embedded outline of an LCP PDF as table of contents on iOS. The plugin reads the table of contents from the publication manifest only (`getFlattenedToC` in `utils/ReadiumExtensions.swift`, which notes that it does not support LCP PDFs). Whether Android exposes it was not checked.
- Passphrase UI. The plugin ships no dialog; your app supplies one.

## The private library

LCP decryption runs inside a closed-source client library that EDRLab gives to registered reading apps: `R2LCPClient` on iOS and `liblcp` on Android. Request access from [EDRLab](https://www.edrlab.org/projects/readium-lcp/). Do not commit the library to a public repository.

The plugin never ships it. Your app adds it, and without it LCP stays disabled: `isAvailable()` returns false, and the native side logs that LCP is disabled.

The example app uses test clients instead, which only handle the LCP basic profile (see [Run the example](#run-the-example)). They are not a substitute for EDRLab's library.

## Setup

Add the package next to `flutter_readium`:

```yaml
dependencies:
  flutter_readium: ^0.9.1
  flutter_readium_lcp: ^0.9.1
```

### iOS

The app needs `use_frameworks!` and `use_modular_headers!` as for `flutter_readium` (see the [README](../../README.md)). Add EDRLab's `R2LCPClient` framework following their instructions.

Implement the toolkit's `LCPClient` protocol (`createContext`, `decrypt`, `findOneValidPassphrase`) on top of EDRLab's framework, following the [swift-toolkit LCP guide](https://github.com/readium/swift-toolkit/blob/main/docs/Guides/Readium%20LCP.md). The example's `BasicProfileLCPClient.swift` shows the protocol shape.

Hand it to the plugin before plugin registration. The plugin reads `lcpClient` once, while it registers. If you set it later, it logs a warning and LCP stays disabled.

```swift
// AppDelegate.swift, before GeneratedPluginRegistrant.register(...)
FlutterReadiumLcpPlugin.lcpClient = MyLCPClient()
```

The toolkit downloads the certificate revocation list (CRL) from `http://crl.edrlab.telesec.de/rl/EDRLab_CA.crl` over plain HTTP. App Transport Security blocks that by default, so add an exception for that host in `Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSExceptionDomains</key>
  <dict>
    <key>crl.edrlab.telesec.de</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key>
      <true/>
    </dict>
  </dict>
</dict>
```

The example app's `Info.plist` sets `NSAllowsArbitraryLoads` for everything. That predates the LCP work and is too broad for a production app.

### Android

Add EDRLab's `liblcp` library to the app following their instructions. The toolkit finds it by reflection as `org.readium.lcp.sdk.Lcp` (with `DRMContext`, `DRMException` and `DRMError` in the same package), so there is nothing to register in code. The plugin builds the toolkit's `LcpService` once per process, and returns "unavailable" if the class is missing.

The app manifest needs `INTERNET` permission (debug builds of Flutter apps already have it). The toolkit fetches the CRL from the same cleartext URL as on iOS, which Android blocks by default. Allow cleartext for that host only, with a network security config referenced from `<application android:networkSecurityConfig="@xml/network_security_config">`:

```xml
<network-security-config>
  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="false">crl.edrlab.telesec.de</domain>
  </domain-config>
</network-security-config>
```

Release builds that shrink code with R8 need a keep rule, because the toolkit loads the library by reflection and R8 cannot see that:

```
-keep class org.readium.lcp.sdk.** { *; }
```

Check EDRLab's instructions for any further rules their library needs. The example's `proguard-rules.pro` holds this rule for its test client. A release build of the example was not run.

## Dart API

```dart
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_readium_lcp/flutter_readium_lcp.dart';

final lcp = FlutterReadiumLcp();

// Once at startup. Return null when the user cancels.
lcp.setPassphraseProvider((request) async {
  // request.reason is notFound on the first ask and invalid after a wrong passphrase.
  // request.hint and request.hintUrl help the user remember it.
  return showPassphraseDialog(hint: request.hint, wasWrong: request.reason == LcpPassphraseReason.invalid);
});

try {
  final pub = await FlutterReadium().openPublication(path);
} on ReadiumException catch (e) {
  switch (LcpException.fromReadiumException(e)) {
    case LcpPassphraseRequiredException():
      // The user cancelled the prompt, or no provider is set.
    case LcpLicenseStatusException(:final status, :final end):
      // expired, revoked, returned, cancelled or notStarted.
    case LcpLicenseInvalidException(:final reason):
      // integrity, signature, profileNotSupported or malformed.
    case LcpNetworkException(:final isCrl):
      // The CRL or another license request failed.
    case LcpLoanNotAvailableException():
    case LcpLoanFailedException():
    case LcpRenewPeriodException():
    case LcpAlreadyReturnedException():
    case LcpRenewWebPageException():
      // Loan failures: only renewLoan and returnPublication throw these (see below).
    case LcpUnexpectedException():
    case null:
      // Not an LCP failure: handle e as usual.
  }
}

// Download the publication a license document points to.
final acquired = await lcp.acquirePublication(lcplPath, onProgress: (p) => print('${(p * 100).round()}%'));
await FlutterReadium().openPublication(acquired.path);

// Read license facts.
final info = await lcp.getLicenseInfo(acquired.path);
print('${info.provider} ${info.state} ${info.rightsEnd} ${info.charactersToCopyLeft}');

// Renew or return a loan. renewLoan without an end date asks for the longest period the server allows.
if (info.canRenewLoan) {
  final renewed = await lcp.renewLoan(acquired.path, end: info.maxRenewDate);
  print(renewed.rightsEnd);
}
if (info.canReturnPublication) {
  await lcp.returnPublication(acquired.path);
}
```

Notes:

- The toolkit stores a passphrase that worked (iOS Keychain, Android Room database), so the prompt only appears on the first open of a license, or when the stored passphrase no longer fits.
- The toolkit asks again with `LcpPassphraseReason.invalid` until the passphrase is right or the provider returns null. A provider that throws counts as cancelled.
- `acquirePublication` stores the file in `flutter_readium_lcp/acquired/` inside the app's private storage (iOS Application Support, Android `filesDir`) and replaces an existing file for the same license. Move it if your library lives elsewhere.
- `getLicenseInfo` works on the file whether or not the publication is open. It can ask for the passphrase and can contact the license status server. It throws the matching `LcpLicenseStatusException` when the license is restricted (for example returned or expired), on both platforms.
- `renewLoan(path, {end})` returns the updated `LcpLicenseInfo`. The end date is clamped to `maxRenewDate`; without `end` the provider's default period applies. `rightsEnd` can show the new date only if the toolkit can fetch the updated license from the `license` link of the status document (see [Loans](#loans)).
- `returnPublication(path)` returns nothing. After it, the license is restricted: `getLicenseInfo` and a fresh `openPublication` throw `LcpLicenseStatusException` with status `returned`.
- `isAvailable()` tells whether the native side registered LCP.

### Errors

LCP failures reach Dart as a `ReadiumException` whose `code` is one of `lcpPassphraseRequired`, `lcpLicenseInvalid`, `lcpLicenseStatus`, `lcpNetwork` or `lcpError`. These are not in `ReadiumErrorCode`, so `codeEnum` is `unknown`; use `LcpException.fromReadiumException(e)`, which returns null for anything else.

Which fields a `LcpLicenseStatusException` carries:

| Status | `date` | `start` | `end` | `devicesCount` |
|---|---|---|---|---|
| `cancelled`, `returned` | both | none | none | none |
| `revoked` | both | none | none | both |
| `expired` | none | iOS only | both | none |
| `notStarted` | none | both | none | none |

The iOS toolkit reports a license that has not started yet as expired; the plugin maps it to `notStarted` when the start date is in the future.

### Loans

`renewLoan` and `returnPublication` use the license status server (LSD) the license points to. Their failures use these codes, identical on iOS and Android:

| Code | Dart type | Meaning |
|---|---|---|
| `lcpLoanNotAvailable` | `LcpLoanNotAvailableException` | The license has no renew or return interaction (no status document or link). |
| `lcpLoanFailed` | `LcpLoanFailedException(isServerError)` | The server rejected the request, or it failed. `isServerError` is true for server, network and unexpected-response failures. |
| `lcpRenewPeriod` | `LcpRenewPeriodException(maxRenewDate)` | The requested end date is not allowed. |
| `lcpAlreadyReturned` | `LcpAlreadyReturnedException` | The license was already returned or has expired. |
| `lcpRenewWebPage` | `LcpRenewWebPageException(url)` | The provider only offers renewal on a web page, which the plugin does not open. |

Both toolkits report an unreachable server as an unexpected server error, so connectivity failures also arrive as `LcpLoanFailedException` with `isServerError` true.

After a successful renew or return, both toolkits try to fetch the updated license from the status document's `license` link. When the fetch works, `renewLoan` returns the new end date, and it is still there after reopening the book. When the link is unreachable, the renew still succeeds on the server, but the toolkit ignores the failed fetch and the app keeps the old end date. A fetched license without a `publication` link is rejected as malformed: the renew and later opens fail with `LcpLicenseInvalidException`.

## `loadPublication` and `openPublication`

Upstream opens a publication whose protection failed (no passphrase, expired license, no LCP client) as restricted instead of failing the open. The plugin treats the two entry points differently:

- `loadPublication(url)` is metadata only. It never prompts and never fails because of restrictions: a protected book returns its metadata, so a bookshelf can list LCP books without asking for any passphrase.
- `openPublication(url)` is for reading. It may prompt through the provider, and it throws when the publication stays restricted: with the add-on's typed error when it explains the restriction, otherwise with `forbidden`.

This also applies without the add-on. Upstream's fallback protection opens Adobe ADEPT books, and LCP books when no LCP client is present, as restricted. `loadPublication` lists them as before, and `openPublication` throws `forbidden`. This fallback behaviour comes from upstream and was not run here.

## Run the example

The example app uses test clients that only handle the LCP basic profile, the profile the LCP specification defines for testing: a SHA-256 user key and AES-256-CBC. They do not check signatures or the CRL, so they cannot open real publications from a store, and they do not reflect how EDRLab's library behaves. The iOS client is `BasicProfileLCPClient.swift` in the Runner target. The Android client is `org.readium.lcp.sdk.Lcp` (Java) in the example's own source set. Neither is part of any published package.

1. Run `bin/fetch_test_resources` (once), then `bin/build_lcp_test_fixtures`. The second needs [uv](https://docs.astral.sh/uv/). It protects existing fixtures with a throwaway certificate and verifies its own output.
2. Run the example (`fvm flutter run` in `flutter_readium/example`). The bookshelf has four LCP buttons: open the test book, open the audiobook, open the PDF, and acquire a book. LCP fixtures are bundled as assets, so rebuild the app after generating them.
3. The passphrase is `flutter-readium-lcp-test`. It is public, and also printed by the script.

For acquisition, the generated `.lcpl` points at `http://127.0.0.1:8765/lcp_acquire_peter_rabbit.epub`. Serve the fixtures folder first:

```bash
cd flutter_readium/example/assets/pubs && python3 -m http.server 8765 --bind 127.0.0.1
```

On an Android device, `127.0.0.1` is the phone itself: run `adb reverse tcp:8765 tcp:8765`. Debug builds of the example allow cleartext to `127.0.0.1` and `localhost` for this; release builds only allow the CRL host. To serve from another address, pass `--base-url` to the script.

To try renew and return you need your own Readium `lcpserver` and `lsdserver`. `bin/build_lcp_test_fixtures --lcp-server http://127.0.0.1:8989` (with `LCP_SERVER_USER` and `LCP_SERVER_PASSWORD` in the environment) registers a throwaway publication on that server and writes `lcp_loan_peter_rabbit.epub` and `.lcpl`, a 3-day loan. The bookshelf button "Open LCP loan" opens it, and the license sheet in the player has the renew and return buttons. The license must also exist on the `lsdserver`; if your `lcpserver` does not notify it, register the license there yourself. The `lsdserver` must reach the `lcpserver` at the URL it has configured, or renew and return fail with a server error. The script is opt-in and not used by the normal run or by CI.

The fixtures are generated and gitignored. They are also missing in CI, so the LCP integration test is not part of the aggregated CI entrypoint. Run it on its own, after resetting stored passphrases (iOS: `xcrun simctl keychain booted reset`; Android: `adb shell pm clear com.example.flutter_readium_example`):

```bash
cd flutter_readium/example
fvm flutter test integration_test/groups/lcp_test.dart -d <device>
```

It checks that `loadPublication` returns metadata without a prompt, that a cancelled prompt gives `LcpPassphraseRequiredException`, and that a wrong passphrase is asked for again before the right one opens the book.

## Known limitations

- No web support and no web-page renewal (see above).
- Renew and return were tested against a local Readium `lcpserver` and `lsdserver` only, with a local stand-in for the license gateway, not against a production provider (see [docs/plans/lcp-support.md](../plans/lcp-support.md)).
- iOS does not show the embedded outline of an LCP PDF as table of contents (see above).
- The iOS audio navigator ignores LCP navigator errors (`presentError` in `navigator/FlutterAudioNavigator.swift`), so a license that becomes unusable during audio playback is not reported to Dart.
- Headers set with `setCustomHeaders` are not sent on LCP traffic in these places: on Android, on all LCP requests (CRL, license status server, license-linked downloads), and on iOS, on `acquirePublication` and `getLicenseInfo`, which use the add-on's own `DefaultHTTPClient`.
