import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../state/index.dart';

class TimebasedStateWidget extends StatefulWidget {
  const TimebasedStateWidget({super.key});

  @override
  State<TimebasedStateWidget> createState() => _TimebasedStateWidgetState();
}

class _TimebasedStateWidgetState extends State<TimebasedStateWidget> {
  double? isDraggingSliderValue;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: context.read<PlayerControlsBloc>().timebasedStateStream,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: [
              Text('State: ${snapshot.data?.state.name.toUpperCase()}'),
              Text(
                'Offset: ${snapshot.data?.currentOffset?.inSeconds} of ${snapshot.data?.currentDuration?.inSeconds} seconds',
              ),
              // Text('Buffered: ${snapshot.data?.currentBuffered}'),
              Text('Href: ${snapshot.data?.currentLocator?.hrefPath}'),
              // Text('Progression: ${snapshot.data?.currentLocator?.locations?.progression}'),
              // Text('TotalProgression: ${snapshot.data?.currentLocator?.locations?.totalProgression}'),
              SizedBox(height: 22),
              Text('Chapter progress:'),
              LinearProgressIndicator(
                value:
                    snapshot.data?.currentLocator?.locations?.progression ??
                    0.0,
              ),
              Text('Total book progress:'),
              LinearProgressIndicator(
                value:
                    snapshot
                        .data
                        ?.currentLocator
                        ?.locations
                        ?.totalProgression ??
                    0,
              ),
            ],
          );
        } else {
          return SizedBox.shrink();
        }
      },
    );
  }

  void onPositionSliderChangedByUser(double value) {}
}
