import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';

import 'extensions/text_settings_theme.dart' show themes;
import 'pages/index.dart';
import 'state/index.dart';

Future<void> main() async {
  // FlutterReadium.init(
  //   androidNotificationChannelId: 'r2.navigator.flutter.audio',
  //   androidNotificationChannelName: 'Audio playback',
  //   downloadDebug: true,
  // );
  WidgetsFlutterBinding.ensureInitialized();

  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory:
        kIsWeb ? HydratedStorageDirectory.web : HydratedStorageDirectory((await getTemporaryDirectory()).path),
  );

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (final _) => PublicationBloc(),
          lazy: false,
        ),
        BlocProvider(
          create: (final _) => TextSettingsBloc()..add(ChangeTheme(themes[0])),
        ),
        // BlocProvider(
        //   create: (final _) => TtsSettingsBloc(),
        //   lazy: false,
        // ),
        BlocProvider(create: (final _) => PlayerControlsBloc()),
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
      },
    );
  }
}
