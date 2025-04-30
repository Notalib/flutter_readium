import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_readium/flutter_readium.dart';

import 'pub_utils.dart';
import 'readium_storage.dart';

const platform = MethodChannel('flutter_readium');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ensure all test publications have been copied to App documents storage.
  await PublicationUtils.moveTestPublicationsToReadiumStorage();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _flutterReadiumPlugin = FlutterReadium();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion = await _flutterReadiumPlugin.platformVersion;
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(
            children: [
              Text('Running on: $_platformVersion\n'),
              IconButton(
                iconSize: 72,
                icon: const Icon(Icons.open_in_browser),
                onPressed: _openBook,
              ),
              Text('Click above to open book')
            ],
          ),
        ),
      ),
    );
  }

  _openBook() async {
    try {
      final publicationsDirPath = await ReadiumStorage.publicationsDirPath;
      final dir = Directory(publicationsDirPath);

      // final pubs = <OPDSPublication>[];
      final entities = dir.listSync().where((f) => f.path.endsWith('.epub'));

      for (final entity in entities) {
        debugPrint('Entity exists ? ${await entity.exists()}');
        final result = await _flutterReadiumPlugin.openPublication(entity.path);
        debugPrint('Result: $result');
      }
    } on PlatformException catch (ex) {
      debugPrint('Failed to open publication: ${ex.message}');
    }
  }
}
