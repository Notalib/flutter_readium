// ignore_for_file: use_build_context_synchronously

import 'package:flutter/foundation.dart';
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

  Future<void> _deferWebGoToAfterRoutePop() async {
    if (!kIsWeb) {
      return;
    }

    // Let the route pop settle before issuing goToLocator on web.
    // Navigating before it is ready means the chapter will not render.
    await Future<void>.delayed(Duration(milliseconds: 1));
  }

  @override
  Widget build(
    final BuildContext context,
  ) => BlocBuilder<PublicationBloc, PublicationState>(
    builder: (final context, final pubState) {
      final isAudioBook = pubState.publication?.conformsToReadiumAudiobook ?? false;

      return PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          // When Player page is popped, make sure to close current publication.
          context.read<PlayerControlsBloc>().add(Stop());
          // Capture the bloc reference now, while this context is still valid.
          // By the time the delay below elapses, the page has been popped and
          // its element deactivated — reading the context then would throw
          // "Looking up a deactivated widget's ancestor is unsafe". The bloc is
          // app-scoped (provided in main.dart), so it outlives this page.
          final publicationBloc = context.read<PublicationBloc>();
          // Put some delay to ensure that the closePublication is called after navigating back visually.
          const delay = Duration(milliseconds: 400);
          Future.delayed(delay, () {
            publicationBloc.add(ClosePublication());
          });
        },
        child: Scaffold(
          restorationId: 'player_page',
          appBar: AppBar(
            backgroundColor: _appBarColor,
            title: Semantics(
              header: true,
              child: Text(
                pubState.error != null ? 'Error' : pubState.publication?.metadata.title ?? 'Unknown',
              ),
            ),
            actions: _buildActionButtons(),
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: isAudioBook
                    ? Container(
                        padding: EdgeInsets.all(12.0),
                        child: TimebasedStateWidget(),
                      )
                    : ReaderWidget(shouldShowControls: _shouldShowControls),
              ),
              if (!isAudioBook)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: SafeArea(
                    minimum: const EdgeInsets.only(right: 8, bottom: 8),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _shouldShowControls,
                      builder: (context, controlsVisible, _) {
                        final extraBottom = controlsVisible ? 108.0 : 0.0;
                        return Padding(
                          padding: EdgeInsets.only(bottom: extraBottom),
                          child: BlocBuilder<PlayerControlsBloc, PlayerControlsState>(
                            buildWhen: (prev, next) => prev.narrationSyncEnabled != next.narrationSyncEnabled,
                            builder: (context, playerState) {
                              if (playerState.narrationSyncEnabled != false) {
                                return const SizedBox.shrink();
                              }
                              return FilledButton.icon(
                                onPressed: () => FlutterReadium().setNarrationSyncEnabled(true),
                                icon: const Icon(Icons.sync),
                                label: const Text('Re-sync'),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (pubState.publication != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _controls(pubState.publication!),
                ),
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
        final publication = context.read<PublicationBloc>().state.publication;
        final isPDF = publication?.conformsToReadiumPDF ?? false;

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (final context) => PointerInterceptor(
            child: isPDF ? const PDFSettingsWidget() : const TextSettingsWidget(),
          ),
        );
      },
      tooltip: 'Open reader settings',
    ),
    IconButton(
      icon: const Icon(Icons.search),
      onPressed: () async {
        final tappedSearchResult = await Navigator.pushNamed<dynamic>(
          context,
          '/search',
        );
        if (!context.mounted) return;
        final publication = context.read<PublicationBloc>().state.publication;
        if (publication != null && tappedSearchResult != null && tappedSearchResult is TextSearchResult) {
          if (context.mounted) {
            context.read<PlayerControlsBloc>().add(
              GoToLocator(tappedSearchResult.locator),
            );
          }
        }
      },
      tooltip: 'Search in publication contents',
    ),
    IconButton(
      icon: const Icon(Icons.toc),
      onPressed: () async {
        final publication = context.read<PublicationBloc>().state.publication;
        final isPdfWithoutToc =
            publication != null && publication.conformsToReadiumPDF && publication.tableOfContents.isEmpty;
        final route = isPdfWithoutToc ? '/pagelist' : '/toc';
        final result = await Navigator.pushNamed<dynamic>(context, route);
        if (!context.mounted) return;
        if (publication != null && result != null && result is Link) {
          final tocLink = result;
          final locator = publication.locatorFromLink(tocLink);
          if (locator != null) {
            await _deferWebGoToAfterRoutePop();
            context.read<PlayerControlsBloc>().add(GoToLocator(locator));
          }
        }
      },
      tooltip: 'Open table of contents',
    ),
  ];

  Widget _controls(final Publication publication) {
    return AnimatedSlideOutWidget(
      visible: _shouldShowControls,
      hiddenOffset: const Offset(0, 1),
      duration: _slideDuration,
      child: Container(
        color: _playerControlsColor,
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          child: PlayerControls(publication: publication),
        ),
      ),
    );
  }

  @override
  String? get restorationId => 'player_page_state';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    // TODO: implement restoreState
    ReadiumLog.d("restoreState called in PlayerPage");
    ReadiumLog.d("RestorationBucket: $oldBucket");
    ReadiumLog.d("Initial restore: $initialRestore");
  }
}
