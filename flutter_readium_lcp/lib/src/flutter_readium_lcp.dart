import 'package:flutter/services.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:meta/meta.dart';

import 'lcp_exceptions.dart';
import 'lcp_models.dart';
import 'lcp_passphrase_request.dart';

/// Returns the passphrase the user entered, or null when they cancelled.
typedef LcpPassphraseProvider = Future<String?> Function(LcpPassphraseRequest request);

/// Entry point of the LCP add-on.
///
/// Native setup: on iOS the app sets `FlutterReadiumLcpPlugin.lcpClient` in its `AppDelegate`
/// before plugin registration. On Android the app only needs EDRLab's LCP library on its classpath.
class FlutterReadiumLcp {
  factory FlutterReadiumLcp() => _instance;

  /// For tests: use a channel other than the plugin's own.
  @visibleForTesting
  FlutterReadiumLcp.forTesting(final MethodChannel channel) : _channel = channel {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  FlutterReadiumLcp._() : _channel = const MethodChannel('dk.nota/flutter_readium_lcp') {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static final _instance = FlutterReadiumLcp._();

  static final _log = ReadiumLog.tag('FlutterReadiumLcp');

  final MethodChannel _channel;
  LcpPassphraseProvider? _provider;
  final _progressCallbacks = <int, void Function(double)>{};
  var _nextProgressId = 0;

  /// Sets the callback that asks the user for a passphrase while a publication is being opened.
  ///
  /// The toolkit asks again, with [LcpPassphraseReason.invalid], until the passphrase is right
  /// or the callback returns null. Without a provider, opening a protected publication fails with
  /// [LcpPassphraseRequiredException] unless the toolkit already stored a working passphrase.
  void setPassphraseProvider(final LcpPassphraseProvider? provider) {
    _provider = provider;
  }

  /// Downloads the publication a license document (`.lcpl`) points to and injects the license.
  ///
  /// The file ends up in `flutter_readium_lcp/acquired/` inside the app's private storage
  /// (iOS: Application Support, Android: `filesDir`). An existing file for the same license is
  /// replaced. Move it if the app keeps its library elsewhere.
  ///
  /// [onProgress] gets values from 0 to 1 while downloading.
  /// Throws an [LcpException] when the license or the download fails, and an [UnsupportedError] on
  /// platforms without the plugin (web).
  Future<LcpAcquiredPublication> acquirePublication(
    final String lcplPath, {
    final void Function(double progress)? onProgress,
  }) async {
    int? progressId;
    if (onProgress != null) {
      progressId = _nextProgressId++;
      _progressCallbacks[progressId] = onProgress;
    }
    try {
      final json = await _invoke<Map<Object?, Object?>>('acquirePublication', {
        'lcplPath': lcplPath,
        'progressId': progressId,
      });
      return LcpAcquiredPublication.fromJson(json);
    } finally {
      if (progressId != null) _progressCallbacks.remove(progressId);
    }
  }

  /// Reads the license of the LCP publication (or license document) at [publicationPath].
  ///
  /// Keyed by file, so it works whether or not the publication is open. The toolkit may ask for
  /// the passphrase through the provider, and may contact the license status server.
  /// Throws an [LcpException] when the license cannot be read or is unusable, including a license that is
  /// expired, returned, revoked or cancelled ([LcpLicenseStatusException]), and an [UnsupportedError] on
  /// platforms without the plugin (web).
  Future<LcpLicenseInfo> getLicenseInfo(final String publicationPath) async {
    final json = await _invoke<Map<Object?, Object?>>('getLicenseInfo', {'path': publicationPath});
    return LcpLicenseInfo.fromJson(json);
  }

  /// Renews the loan of the LCP publication at [publicationPath] and returns the refreshed license info.
  ///
  /// [end] is the preferred new end date. The toolkit clamps it to [LcpLicenseInfo.maxRenewDate], and
  /// ignores it when the server's renew link takes no end date. Null lets the server decide.
  /// Renewing through a web page is not supported: the call throws [LcpRenewWebPageException] with the URL.
  ///
  /// The toolkit refetches the license after a renewal, so [LcpLicenseInfo.rightsEnd] shows the new end date
  /// only when the license server's `license` link is reachable (see docs/guides/lcp.md).
  /// Throws an [LcpException] when the loan cannot be renewed, and an [UnsupportedError] on platforms
  /// without the plugin (web).
  Future<LcpLicenseInfo> renewLoan(final String publicationPath, {final DateTime? end}) async {
    final json = await _invoke<Map<Object?, Object?>>('renewLoan', {
      'path': publicationPath,
      'endMillis': end?.millisecondsSinceEpoch,
    });
    return LcpLicenseInfo.fromJson(json);
  }

  /// Returns the loan of the LCP publication at [publicationPath] to its provider.
  ///
  /// Afterwards the license is returned: the toolkit refuses to open the publication with an
  /// [LcpLicenseStatusException], and [getLicenseInfo] fails the same way, so there is no refreshed info.
  /// Throws an [LcpException] when the loan cannot be returned, and an [UnsupportedError] on platforms
  /// without the plugin (web).
  Future<void> returnPublication(final String publicationPath) async {
    await _invoke<bool>('returnPublication', {'path': publicationPath});
  }

  /// Whether the native LCP content protection is registered: the iOS app set its LCP client, or
  /// the Android app has EDRLab's LCP library on its classpath. False on platforms without the plugin (web).
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<T> _invoke<T>(final String method, final Object? arguments) async {
    try {
      return (await _channel.invokeMethod<T>(method, arguments))!;
    } on MissingPluginException {
      throw UnsupportedError('flutter_readium_lcp is not supported on this platform.');
    } on PlatformException catch (err) {
      final exception = ReadiumException.fromPlatformException(err);
      throw LcpException.fromReadiumException(exception) ?? exception;
    }
  }

  Future<Object?> _onNativeCall(final MethodCall call) async {
    if (call.method == 'acquisitionProgress') {
      final args = call.arguments as Map<Object?, Object?>;
      _progressCallbacks[args['id'] as int]?.call((args['progress'] as num).toDouble());
      return null;
    }
    if (call.method != 'requestPassphrase') throw MissingPluginException(call.method);
    final provider = _provider;
    if (provider == null) return null;
    try {
      return await provider(LcpPassphraseRequest.fromMap(call.arguments as Map<Object?, Object?>));
    } on Exception catch (err) {
      // A failing prompt must not hang the open: treat it as cancelled.
      _log.e('Passphrase provider threw: $err');
      return null;
    }
  }
}
