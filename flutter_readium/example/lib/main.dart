import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_logging/marionette_logging.dart';
import 'package:path_provider/path_provider.dart';

import 'pages/index.dart';
import 'state/index.dart';

Future<void> main() async {
  // Initialize Marionette only in debug mode
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized(MarionetteConfiguration(logCollector: LoggingLogCollector()));
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint(ReadiumLog.format(record, colored: !kIsWeb));
  });

  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: kIsWeb
        ? HydratedStorageDirectory.web
        : HydratedStorageDirectory((await getTemporaryDirectory()).path),
  );

  // Modify log level for the entire plugin here. The default is LogLevel.info.
  FlutterReadium().setLogLevel(LogLevel.debug);

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (final _) => PublicationBloc(), lazy: false),
        BlocProvider(
          create: (final _) {
            final bloc = TextSettingsBloc();
            bloc.setDefaultPreferences();
            return bloc;
          },
        ),
        // BlocProvider(
        //   create: (final _) => TtsSettingsBloc(),
        //   lazy: false,
        // ),
        BlocProvider(create: (final _) => PlayerControlsBloc()),
        BlocProvider(create: (final _) => PDFSettingsBloc()),
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with RestorationMixin {
  @override
  String? get restorationId => 'root';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    // Register any restorable properties here if needed
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      restorationScopeId: 'app',
      routes: {
        '/': (context) => BookshelfPage(),
        '/player': (context) => PlayerPage(),
        '/toc': (context) => TableOfContentsPage(),
        '/pagelist': (context) => PageListPage(),
        '/search': (context) => SearchPage(),
      },
    );
  }
}
