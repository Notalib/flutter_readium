import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../state/index.dart';

class ReaderWidget extends StatelessWidget {
  ReaderWidget({this.shouldShowControls, super.key});

  final ValueNotifier<bool>? shouldShowControls;

  final ValueNotifier<bool> loadingNotifier = ValueNotifier<bool>(false);

  @override
  Widget build(final BuildContext context) => BlocBuilder<PublicationBloc, PublicationState>(
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
                  Text('Loading publication failed.', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 10),
                  Text(state.errorDebugDescription()),
                ],
              ),
            ),
          ),
        );
      } else if (state.publication != null) {
        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: BlocSelector<TextSettingsBloc, TextSettingsState, bool>(
            selector: (textState) => textState.verticalScroll,
            builder: (context, verticalScroll) => ReadiumReaderWidget(
              publication: state.publication!,
              initialLocator: state.initialLocator,
              shouldShowControls: shouldShowControls,
              verticalScroll: verticalScroll,
            ),
          ),
        );
      }
      // Return a fallback widget in case none of the conditions above are met
      return const ColoredBox(
        color: Color(0xffffff00),
        child: Center(child: Text('Something went wrong.')),
      );
    },
  );
}
