import '_index.dart';

extension ConnectivityResultExtension on List<ConnectivityResult> {
  bool get isWifi => contains(ConnectivityResult.wifi);
  bool get isEthernet => contains(ConnectivityResult.ethernet);
  bool get isMobile => contains(ConnectivityResult.mobile);
  bool get isNone => contains(ConnectivityResult.none);
}

final _connectivity = Connectivity();

Stream<List<ConnectivityResult>> connectivityStatus = _connectivity.onConnectivityChanged;

// Is there a better name for this?
Stream<bool> nonMobileStream = connectivityStatus.map(_nonMobile);

Future<bool> isNonMobile() => _connectivity.checkConnectivity().then(_nonMobile);

Future<bool> get isMobileConnectivity async => (await _connectivity.checkConnectivity()).isMobile;

Stream<bool> nonMobileStreamInit() => nonMobileStream.startWithStream(isNonMobile().asStream());

Stream<bool> isOnlineStream = connectivityStatus.map((final state) => !state.isNone);

Future<bool> hasInternetConnection() =>
    _connectivity.checkConnectivity().then((final state) => !state.isNone);

Future<bool> haveNonMobileInternetConnection() async =>
    await isNonMobile() && await hasInternetConnection();

bool _nonMobile(final List<ConnectivityResult> results) => results.any((final result) {
      switch (result) {
        case ConnectivityResult.wifi:
        case ConnectivityResult.ethernet:
          return true;
        case ConnectivityResult.mobile:
        case ConnectivityResult.none:
        default:
          return false;
      }
    });
