import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../state/pdf_settings_bloc.dart';
import 'index.dart';

class PDFSettingsWidget extends StatelessWidget {
  const PDFSettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = context.watch<PDFSettingsBloc>();
    final state = bloc.state;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.7,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Semantics(
                header: true,
                child: const Align(
                  alignment: Alignment.center,
                  child: Text('PDF Settings', style: TextStyle(fontSize: 25)),
                ),
              ),
            ),
            const Divider(),
            ListItemWidget(
              label: 'Layout',
              child: SegmentedButton<PDFLayout>(
                key: const ValueKey('pdf_layout_selector'),
                segments: const [
                  ButtonSegment(
                    value: PDFLayout.paginated,
                    label: Text('Paginated'),
                  ),
                  ButtonSegment(
                    value: PDFLayout.scrollVertical,
                    label: Text('Scroll V'),
                  ),
                  ButtonSegment(
                    value: PDFLayout.scrollHorizontal,
                    label: Text('Scroll H'),
                  ),
                ],
                selected: {state.layout},
                onSelectionChanged: (values) {
                  bloc.add(ChangePDFLayout(values.first));
                },
              ),
            ),
            const Divider(),
            ListItemWidget(
              label: 'Fit',
              child: SegmentedButton<PDFFit>(
                key: const ValueKey('pdf_fit_selector'),
                segments: const [
                  ButtonSegment(value: PDFFit.auto, label: Text('Auto')),
                  ButtonSegment(value: PDFFit.page, label: Text('Page')),
                  ButtonSegment(value: PDFFit.width, label: Text('Width')),
                ],
                selected: {state.fit},
                onSelectionChanged: (values) {
                  bloc.add(ChangePDFFit(values.first));
                },
              ),
            ),
            const Divider(),
            ListItemWidget(
              label: 'Reading Direction',
              child: SegmentedButton<PDFReadingProgression>(
                key: const ValueKey('pdf_reading_progression_selector'),
                segments: const [
                  ButtonSegment(
                    value: PDFReadingProgression.ltr,
                    label: Text('LTR'),
                  ),
                  ButtonSegment(
                    value: PDFReadingProgression.rtl,
                    label: Text('RTL'),
                  ),
                ],
                selected: {state.readingProgression},
                onSelectionChanged: (values) {
                  bloc.add(ChangePDFReadingProgression(values.first));
                },
              ),
            ),
            const Divider(),
            ListItemWidget(
              label: 'Page Spacing',
              child: Slider(
                key: const ValueKey('pdf_page_spacing_slider'),
                value: state.pageSpacing,
                min: 0.0,
                max: 50.0,
                divisions: 10,
                label: state.pageSpacing.toStringAsFixed(0),
                onChanged: (value) {
                  bloc.add(ChangePDFPageSpacing(value));
                },
              ),
            ),
            const Divider(),
            TextButton(
              key: const ValueKey('pdf_settings_close_button'),
              onPressed: () => Navigator.of(context).pop(),
              style: ButtonStyle(
                padding: WidgetStateProperty.all<EdgeInsets>(
                  const EdgeInsets.symmetric(vertical: 16.0),
                ),
                shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(0.0),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 8.0,
                children: [
                  Icon(Icons.close, size: 20),
                  Text('Close', style: TextStyle(fontSize: 20)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
