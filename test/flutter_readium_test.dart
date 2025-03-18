import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_readium/flutter_readium_platform_interface.dart';
import 'package:flutter_readium/flutter_readium_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterReadiumPlatform
    with MockPlatformInterfaceMixin
    implements FlutterReadiumPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterReadiumPlatform initialPlatform = FlutterReadiumPlatform.instance;

  test('$MethodChannelFlutterReadium is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterReadium>());
  });

  test('getPlatformVersion', () async {
    FlutterReadium flutterReadiumPlugin = FlutterReadium();
    MockFlutterReadiumPlatform fakePlatform = MockFlutterReadiumPlatform();
    FlutterReadiumPlatform.instance = fakePlatform;

    expect(await flutterReadiumPlugin.getPlatformVersion(), '42');
  });
}
