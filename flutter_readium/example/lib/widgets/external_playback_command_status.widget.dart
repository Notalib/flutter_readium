import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

class ExternalPlaybackCommandStatus extends StatefulWidget {
  const ExternalPlaybackCommandStatus({
    required this.commands,
    super.key,
  });

  final Stream<ReadiumExternalPlaybackCommand> commands;

  @override
  State<ExternalPlaybackCommandStatus> createState() => _ExternalPlaybackCommandStatusState();
}

class _ExternalPlaybackCommandStatusState extends State<ExternalPlaybackCommandStatus> {
  late StreamSubscription<ReadiumExternalPlaybackCommand> _subscription;
  Timer? _clearTimer;
  ReadiumExternalPlaybackCommand? _command;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant ExternalPlaybackCommandStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commands != widget.commands) {
      unawaited(_subscription.cancel());
      _subscribe();
    }
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('External playback command: '),
        _command == null
            ? Text('-')
            : Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _actionColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(_label),
              ),
      ],
    );
  }

  Color? get _actionColor {
    return switch (_command?.action) {
      ExternalPlaybackCommandAction.pause => Colors.yellow[600],
      ExternalPlaybackCommandAction.play => Colors.lightGreen,
      ExternalPlaybackCommandAction.togglePlayPause => Colors.orange,

      ExternalPlaybackCommandAction.previous => Colors.blue[300],
      ExternalPlaybackCommandAction.next => Colors.blue[300],
      ExternalPlaybackCommandAction.seekBackward => Colors.blue[300],
      ExternalPlaybackCommandAction.seekForward => Colors.blue[300],
      ExternalPlaybackCommandAction.seekTo => Colors.blue[300],

      ExternalPlaybackCommandAction.unknown => Colors.red[300],
      _ => null,
    };
  }

  String get _label {
    final command = _command;
    if (command == null) {
      return '';
    }

    final position = command.position;
    final positionLabel = position == null ? '' : ' (position: ${position.inMilliseconds} ms)';
    return '${command.action.name}$positionLabel';
  }

  void _subscribe() {
    _subscription = widget.commands.listen(_showCommand);
  }

  void _showCommand(ReadiumExternalPlaybackCommand command) {
    if (!mounted) {
      return;
    }
    _clearTimer?.cancel();
    setState(() => _command = command);
    _clearTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _command = null);
      }
    });
  }
}
