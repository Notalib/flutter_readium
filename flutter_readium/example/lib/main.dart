import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import 'pages/index.dart';
import 'state/index.dart';

Future<void> main() async {
  // FlutterReadium.init(
  //   androidNotificationChannelId: 'r2.navigator.flutter.audio',
  //   androidNotificationChannelName: 'Audio playback',
  //   downloadDebug: true,
  // );

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (final _) => PublicationBloc(),
          lazy: false,
        ),
        BlocProvider(
          create: (final _) => TextSettingsBloc(),
        ),
        // BlocProvider(
        //   create: (final _) => TtsSettingsBloc(),
        //   lazy: false,
        // ),
        BlocProvider(create: (final _) => PlayerControlsBloc()),
      ],
      child: MaterialApp(
        routes: {
          '/': (final context) => BookshelfPage(),
          '/player': (final context) => PlayerPage(),
        },
      ),
    ),
  );
}
