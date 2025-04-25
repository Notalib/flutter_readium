import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_readium/flutter_readium.dart';

void main() {
  const MethodChannel channel = MethodChannel('flutter_readium');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((methodCall) async => '42');
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });
}
