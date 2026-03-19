// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../state/index.dart';
import '../widgets/index.dart';

const Color _appBarColor = Colors.amber;
const Color _playerControlsColor = Color.fromARGB(255, 240, 240, 240);

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with RestorationMixin {
  final _slideDuration = const Duration(milliseconds: 350);
  final _shouldShowControls = ValueNotifier(true);

  @override
  Widget build(final BuildContext context) => BlocBuilder<PublicationBloc, PublicationState>(
    builder: (final context, final pubState) {
      final isAudioBook = pubState.publication?.conformsToReadiumAudiobook ?? false;
      final hasMediaOverlays = pubState.publication?.containsMediaOverlays == true;

      return PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          // When Player page is popped, make sure to close current publication.
          context.read<PlayerControlsBloc>().add(Stop());
          // Put some delay to ensure that the closePublication is called after navigating back visually.
          Duration delay = const Duration(milliseconds: 450);
          Future.delayed(delay, () {
            context.read<PublicationBloc>().add(ClosePublication());
          });
        },
        child: Scaffold(
          restorationId: 'player_page',
          appBar: AppBar(
            backgroundColor: _appBarColor,
            title: Semantics(
              header: true,
              child: Text(pubState.error != null ? 'Error' : pubState.publication?.metadata.title ?? 'Unknown'),
            ),
            actions: _buildActionButtons(),
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: isAudioBook
                    ? Container(padding: EdgeInsets.all(12.0), child: TimebasedStateWidget())
                    : ReaderWidget(shouldShowControls: _shouldShowControls),
              ),
              Positioned(left: 0, right: 0, bottom: 0, child: _controls(isAudioBook || hasMediaOverlays)),
            ],
          ),
        ),
      );
    },
  );

  List<Widget> _buildActionButtons() => <Widget>[
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
          builder: (final context) => PointerInterceptor(child: const TextSettingsWidget()),
        );
      },
      tooltip: 'Open text style settings',
    ),
    IconButton(
      icon: const Icon(Icons.toc),
      onPressed: () async {
        final result = await Navigator.pushNamed<dynamic>(context, '/toc');
        if (!context.mounted) return;
        final publication = context.read<PublicationBloc>().state.publication;
        if (publication != null && result != null && result is Link) {
          final tocLink = result;
          final locator = publication.locatorFromLink(tocLink);
          if (locator != null && context.mounted) {
            context.read<PlayerControlsBloc>().add(GoToLocator(locator));
          }
        }
      },
      tooltip: 'Open table of contents',
    ),
  ];

  Widget _controls(final bool isAudioBook) => AnimatedSlideOutWidget(
    visible: _shouldShowControls,
    hiddenOffset: const Offset(0, 1),
    duration: _slideDuration,
    child: Container(
      color: _playerControlsColor,
      child: SafeArea(top: false, left: false, right: false, child: PlayerControls(isAudioBook: isAudioBook)),
    ),
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
