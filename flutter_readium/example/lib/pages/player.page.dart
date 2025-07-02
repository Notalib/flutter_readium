import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../state/index.dart';
import '../widgets/index.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with RestorationMixin {
  @override
  Widget build(final BuildContext context) => BlocBuilder<PublicationBloc, PublicationState>(
        builder: (final context, final pubState) => Scaffold(
          restorationId: 'player_page',
          appBar: AppBar(
            backgroundColor: Colors.deepPurple[200],
            title: Semantics(
              header: true,
              child: Text(
                pubState.error != null ? 'Error' : pubState.publication?.metadata.title.values.first ?? 'Unknown',
              ),
            ),
            actions: _buildActionButtons(context),
          ),
          body: Container(
            color: Colors.pinkAccent[100],
            child: Column(
              children: [
                Expanded(
                  child: ReaderWidget(),
                ),
                _controls(),
              ],
            ),
          ),
        ),
      );

  List<Widget> _buildActionButtons(final BuildContext context) => <Widget>[
        // IconButton(
        //   icon: const Icon(Icons.headphones),
        //   onPressed: () {
        //     context.read<TtsSettingsBloc>().add(GetTtsVoicesEvent());

        //     final pubLang =
        //         context.read<PublicationBloc>().state.publication?.metadata.language ?? ['en'];

        //     showModalBottomSheet(
        //       context: context,
        //       isScrollControlled: true,
        //       builder: (final context) => TtsSettingsWidget(
        //         pubLang: pubLang,
        //       ),
        //     );
        //   },
        //   tooltip: 'Open tts settings',
        // ),
        IconButton(
          icon: const Icon(Icons.format_paint),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (final context) => const TextSettingsWidget(),
            );
          },
          tooltip: 'Open text style settings',
        ),
      ];

  Widget _controls() => const SafeArea(
        top: false,
        left: false,
        right: false,
        child: PlayerControls(),
      );

  @override
  String? get restorationId => 'player_page_state';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    // TODO: implement restoreState
    R2Log.d("restoreState called in PlayerPage");
    R2Log.d("RestorationBucket: $oldBucket");
    R2Log.d("Initial restore: $initialRestore");
  }
}
