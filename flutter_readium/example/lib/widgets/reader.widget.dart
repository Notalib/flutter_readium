import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_readium/reader_widget.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

import '../state/index.dart';
import '../extensions/index.dart';

class ReaderWidget extends StatelessWidget {
  ReaderWidget({super.key});

  final ValueNotifier<bool> loadingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<NativeDeviceOrientation> orientationNotifier =
      ValueNotifier<NativeDeviceOrientation>(NativeDeviceOrientation.portraitUp);

  @override
  Widget build(final BuildContext context) => BlocBuilder<TextSettingsBloc, TextSettingsState>(
        builder: (final context, final state) => Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              right: state.verticalScroll ? 0 : null,
              bottom: state.verticalScroll ? null : 0,
              child: _buildSemanticsPrevPage(verticalScroll: state.verticalScroll),
            ),
            Positioned(
              top: state.verticalScroll ? null : 0,
              right: 0,
              left: state.verticalScroll ? 0 : null,
              bottom: 0,
              child: _buildSemanticsNextPage(verticalScroll: state.verticalScroll),
            ),
            _buildReader(),
          ],
        ),
      );

  Widget _buildReader() => BlocBuilder<PublicationBloc, PublicationState>(
        builder: (final context, final state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state.error != null) {
            R2Log.e('Error loading publication: ${state.error}');
            return ColoredBox(
              color: Colors.yellow.shade400,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Loading publication failed.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 10),
                      Text(state.error.toString()),
                    ],
                  ),
                ),
              ),
            );
          } else if (state.publication != null) {
            context.read<TextSettingsBloc>().add(OpenPubSuccess());
            return Semantics(
              container: true,
              explicitChildNodes: true,
              child: ExcludeSemantics(
                child: ReadiumReaderWidget(
                  publication: state.publication!,
                  initialLocator: state.initialLocator,
                ),
              ),
            );
          }
          // Return a fallback widget in case none of the conditions above are met
          return const ColoredBox(
            color: Color(0xffffff00),
            child: Center(
              child: Text('Something went wrong.'),
            ),
          );
        },
      );

  Widget _buildOnReady(final Widget child) => ValueListenableBuilder<bool>(
        valueListenable: loadingNotifier,
        builder: (final _, final isLoading, final __) => isLoading ? const CircularProgressIndicator() : child,
      );

  Widget _buildReaderSafeArea(final Widget child) => SafeArea(
        top: true,
        bottom: true,
        child: child,
      );

  Widget _buildSemanticsNextPage({required final bool verticalScroll}) => _buildSemanticsNextPrevPage(
        label: 'To next page',
        toNextPage: true,
        verticalScroll: verticalScroll,
      );

  Widget _buildSemanticsPrevPage({required final bool verticalScroll}) => _buildSemanticsNextPrevPage(
        label: 'To previous page',
        toNextPage: false,
        verticalScroll: verticalScroll,
      );

  Widget _buildSemanticsNextPrevPage({
    required final String label,
    required final bool toNextPage,
    required final bool verticalScroll,
  }) =>
      _buildOnReady(
        _buildReaderSafeArea(
          ValueListenableBuilder<NativeDeviceOrientation>(
            valueListenable: orientationNotifier,
            builder: (final context, final orientation, final _) {
              final isPortrait = orientation == NativeDeviceOrientation.portraitUp ||
                  orientation == NativeDeviceOrientation.portraitDown;
              final width = context.isSmallDownScreen && isPortrait ? 70.0 : 100.0;
              final height = context.isSmallDownScreen && !isPortrait ? 70.0 : 50.0;
              //TODO: find out why on iPhone the height is not the actual height, it is smaller.
              return SizedBox(
                width: verticalScroll ? null : width,
                height: verticalScroll ? height : null,
                child: Semantics(
                  button: true,
                  container: true,
                  label: label,
                  onTap: () => toNextPage
                      ? context.read<PlayerControlsBloc>().add(SkipToNextPage())
                      : context.read<PlayerControlsBloc>().add(SkipToPreviousPage()),
                ),
              );
            },
          ),
        ),
      );
}
