# LCP support

Status: implemented, pending review. Branch `feat/lcp-support`, local commits only until reviewed. User-facing documentation is in [docs/guides/lcp.md](../guides/lcp.md).

## Goal

Open Readium LCP-protected publications (EPUB, `.lcpa` audiobook, `.lcpdf` PDF) on iOS and Android through the upstream toolkits, acquire a publication from a `.lcpl` license, and expose license info to Dart, and renew or return a loan through the license status server. Web is out of scope for this pass.

Production LCP needs the private client library from EDRLab (`R2LCPClient` on iOS, `liblcp` on Android), which only registered reading apps receive. The plugin must never ship or depend on it. The consuming app supplies it.

## Decisions

| Topic | Decision |
|---|---|
| Packaging | New add-on package `flutter_readium_lcp`.<br>Core gets no LCP dependency and no build flag. |
| Test client | Basic-profile-only client written by us.<br>Lives in the example app, never published. |
| Passphrase | Supplied from Dart. No native dialog. |
| Scope | Open, acquire from `.lcpl`, license info, loan renew and return. |
| Verification | iOS simulator and the attached Galaxy S23. |
| Git | Local commits only. No push, no PR. |

## Upstream facts (swift-toolkit 3.11.0, kotlin-toolkit 3.4.0)

- iOS: `LCPService(client:licenseRepository:passphraseRepository:assetRetriever:httpClient:)`, then `lcpService.contentProtection(with: authentication)` goes into `PublicationOpener(contentProtections:)`. The app implements the `LCPClient` protocol (`createContext`, `decrypt`, `findOneValidPassphrase`). Guide: `docs/Guides/Readium LCP.md`.
- iOS dependencies: `ReadiumLCP` (pulls CryptoSwift, ReadiumZIPFoundation). Keychain license and passphrase repositories are built in, so `ReadiumAdapterLCPSQLite` is not needed. Both CocoaPods and SwiftPM are supported.
- Android: `LcpService(context, assetRetriever)` returns null when `org.readium.lcp.sdk.Lcp` is not on the classpath. The toolkit finds the client by reflection: `Lcp.createContext(String, String, String)`, `Lcp.decrypt(DRMContext, byte[])`, `Lcp.findOneValidPassphrase(String, String[])`, plus `DRMContext`, `DRMException`, `DRMError` in the same package. Guide: `docs/guides/lcp.md`.
- Android dependencies: `org.readium.kotlin-toolkit:readium-lcp` (Room, KSP are internal to the artifact).
- No public test build of the private library exists, and no public repository of basic-profile test publications was found.
- Basic profile (`http://readium.org/lcp/basic-profile`, "for test only" in the spec): user key is SHA-256 of the passphrase, content key and resources use AES-256-CBC, `key_check` is the license id encrypted with the user key, signature is RSA-SHA256.

Unverified, to confirm from toolkit source before relying on it: exact `LCPAuthenticating` / `LcpAuthenticating` signatures, the IV and padding convention for resources, whether license validation tolerates an unreachable CRL and status server, and whether a Flutter SwiftPM plugin can depend on another plugin's Swift module.

## Design

- **Core hook.** `flutter_readium` exposes a small public native API to register extra `ContentProtection` instances, and rebuilds its `PublicationOpener` when one is added. iOS: on `Readium`. Android: on `ReadiumReader`. Remove the dead `#if LCP` blocks and the commented-out dependencies.
- **Add-on native side.** Builds the `LCPService`, registers its content protection with core, and implements authentication by asking Dart for a passphrase. iOS needs the app to hand over its `LCPClient` at startup (`FlutterReadiumLcpPlugin.lcpClient = …` in `AppDelegate`). Android needs nothing: the client is found on the classpath.
- **Add-on Dart API.** `setPassphraseProvider(callback)`, `acquirePublication(lcplPath)` returning the local file path, `getLicenseInfo(...)`, and typed errors for "passphrase required", "passphrase incorrect", and license status failures (expired, revoked, returned). Hand-written models, no codegen.
- **Example app.** Test client in Swift (Runner target) and Kotlin (`org.readium.lcp.sdk.*` in the example app module). A minimal screen to open an LCP fixture and enter a passphrase.
- **Fixtures.** A script under `bin/` generates basic-profile fixtures from existing unprotected fixtures with a throwaway certificate and a documented passphrase. Output is gitignored like the other fixtures.

## Phases

Each phase is one or more commits and ends with its gates green. A Sonnet agent implements from this plan, an Opus agent reviews the diff, the orchestrator verifies claims against the code and the run output.

1. **Fixtures.** Generator script for a protected EPUB, `.lcpa`, `.lcpdf` and a standalone `.lcpl`. Self-check: the script decrypts its own output and compares bytes.
2. **Core hook.** Registration API on both platforms, dead LCP scaffold removed. Gates: iOS build, Android `compileDebugKotlin`, `bin/readium_versions --check`.
3. **Add-on scaffold and open.** Package, native wiring, Dart passphrase provider, typed errors. Example test clients. Done when a protected EPUB opens and renders on the iOS simulator and the S23, and a wrong passphrase yields the typed error.
4. **Audiobook and PDF.** Open `.lcpa` and `.lcpdf` on both platforms.
5. **Acquire and license info.** `.lcpl` acquisition against a local HTTP server serving the fixture; license info read back in Dart.
6. **Tests and docs.** Integration tests, a guide under `docs/guides/` on building with LCP and supplying the EDRLab library, README updates, changelog fragments, `docs/plans/README.md` entry moved out of "deferred".
7. **Loan renew and return.** `renewLoan` and `returnPublication` on both platforms with typed errors (`lcpLoanNotAvailable`, `lcpLoanFailed`, `lcpRenewPeriod`, `lcpAlreadyReturned`, `lcpRenewWebPage`). License info gains `canRenewLoan`, `maxRenewDate`, `canReturnPublication`. `getLicenseInfo` fails for a restricted license on both platforms. The example license sheet has renew and return buttons. An opt-in fixture mode (`--lcp-server`) creates a loan on a Readium `lcpserver`.

## Overnight rules

- Build and test commands run outside the Bash sandbox. Nothing else does.
- Never push, open a PR, or write to another repository.
- Never download or look for a copy of the EDRLab private library.
- Three failed attempts on the same blocker: record it under "Open issues" below, move to the next phase that does not depend on it.
- `android-keep-awake` runs only while Android device tests run. If the phone is on the lock screen, report it and skip Android runtime checks.
- Report what ran and what did not. A phase that only compiled is reported as compiled, not verified.

## Verified

- **Gates.** `bin/format`, `bin/analyze`, `bin/unit_tests`, `bin/changelog check`, `bin/readium_versions --check`, `ktlint`, Android `compileDebugKotlin` and `testDebugUnitTest`, and `flutter build ios --simulator --debug` pass.
- **iOS simulator (iPhone 16) and Galaxy S23.** The bookshelf loads without a passphrase prompt. `lcp_peter_rabbit.epub` re-asks after a wrong passphrase, fails with `LcpPassphraseRequiredException` on cancel, and renders its text with the right passphrase. A non-LCP EPUB opens. `integration_test/groups/lcp_test.dart` passes on both (4 of 4).
- **Not run.** LCP audiobook, PDF and acquisition were not re-run in the final pass.
- **Loans, against a local `lcpserver` and `lsdserver` (iOS simulator and S23).** A fresh loan opens on both, the license sheet shows status `active`, the rights end, `Can renew: yes`, the max renew date and `Can return: yes`, and the server records a register event per device. Renew reaches the server from both: it records a `renew` event per device. Return succeeds on both: the server status becomes `returned`, the sheet closes and the snackbar shows. Opening the returned license again fails with `LcpLicenseStatusException` on both. On Android the sheet of a still-open returned book shows `License unavailable: LcpLicenseStatusException`. A license without a status document shows `Status: no status document` on Android, and renew and return fail with `LcpLoanNotAvailableException`. A status document without a `renew` link gives `Can renew: no` and `LcpLoanNotAvailableException`.
- **Renew end to end (iOS simulator and S23).** With the status document's `license` link served by a local stand-in for the gateway, renew moves the rights end by the server's `renew_days` (7 days), the sheet shows the new end date and `Updated` at once without an error, and the new date is still there after leaving and reopening the book. On the S23 a first open of the original fixture already showed the end date renewed from iOS: the toolkit refetched the license on open. With the link unreachable (`https://localhost:5001/lcp/{id}`, connection refused), the renew still succeeds on the server but the toolkit ignores the failed refetch and the app keeps the old end date. A refetched license without a `publication` link is rejected as malformed: renew and later opens fail with `LcpLicenseInvalidException`.

## Open issues

- **Path dependencies.** `flutter_readium_lcp/pubspec.yaml` depends on `flutter_readium` by path and overrides `flutter_readium_platform_interface` by path. Both must become hosted constraints before release. The published `flutter_readium` example also path-depends on the add-on. `bin/release_prep`, `bin/publish` and the CI workflows do not know the add-on yet; only `bin/changelog` lists it.
- **Status paths not exercised at runtime.** Expired, revoked and cancelled licenses were not run. Their error mapping is covered by unit tests only.
- **SwiftPM.** The add-on's SwiftPM manifest built earlier but was never run on a device, and the final iOS build used CocoaPods.
- **Android release build.** Only debug builds were run. The R8 keep rule for `org.readium.lcp.sdk.*` in the example is untested under a release build.
- **iOS audio navigator.** `FlutterAudioNavigator.swift` still ignores LCP navigator errors (`presentError`), so a license that fails mid-playback is not reported to Dart.
- **Android: fast re-open of an EPUB crashes (core, not LCP).** Pressing back from the player and opening an EPUB again within about a second throws `Can't change container ID of fragment` in `EpubNavigator.attachNavigator`. The second open creates two reader platform views in a row. The first one's `epubEnable` creates the navigator, and the second one takes the "Already enabled" branch and re-adds the same fragment to its own container. It reproduces with Moby Dick opened twice (no LCP), and with an LCP book followed by Moby Dick. With about 3 s between back and the next open there is one view per open and no crash. The LCP changes do not touch this path, but it was not run on a `main` build. Needs a separate issue.
- **Loan server setup.** `lsdserver` 1.12.0 adds the `renew` link only when `license_status.renew_expired` is true (`makeLinks` in `lsdserver/api/license_status.go`): with the flag off, `renewableLicense` stays false even for an active loan. The two servers also call each other at `127.0.0.1`, so in Docker they must share a network namespace (`network_mode: "service:lcpserver"`). Without that the `lsdserver` answers return with 500 and never learns of new licenses. A client only sees the renewed end date when the `license_link_url` target is reachable.
- **iOS: "Something went wrong" on a fast re-open (seen once).** Leaving the player and opening the loan again right away showed the reader fallback screen with title `Unknown` and no error in the log. It did not reproduce. Possibly the same close/open race as the Android item above.
- **Fixtures not in CI.** The LCP integration test needs generated fixtures and a clean passphrase store, so it is not part of the CI entrypoint.
