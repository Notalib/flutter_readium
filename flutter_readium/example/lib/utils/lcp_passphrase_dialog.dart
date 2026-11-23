import 'package:material_ui/material_ui.dart';
import 'package:flutter_readium_lcp/flutter_readium_lcp.dart';

/// Shows a modal passphrase prompt for [request] and returns what the user typed, or null on cancel.
Future<String?> showLcpPassphraseDialog(
  final BuildContext context,
  final LcpPassphraseRequest request,
) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (final _) => _LcpPassphraseDialog(request: request),
);

class _LcpPassphraseDialog extends StatefulWidget {
  const _LcpPassphraseDialog({required this.request});

  final LcpPassphraseRequest request;

  @override
  State<_LcpPassphraseDialog> createState() => _LcpPassphraseDialogState();
}

class _LcpPassphraseDialogState extends State<_LcpPassphraseDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final request = widget.request;
    final wrong = request.reason == LcpPassphraseReason.invalid;
    return AlertDialog(
      key: const ValueKey('lcp_passphrase_dialog'),
      title: const Text('Passphrase required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wrong)
            Text(
              'Wrong passphrase, try again.',
              key: const ValueKey('lcp_passphrase_invalid'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Text('Hint: ${request.hint}', key: const ValueKey('lcp_passphrase_hint')),
          TextField(
            key: const ValueKey('lcp_passphrase_field'),
            controller: _controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Passphrase'),
            onSubmitted: (final value) => Navigator.of(context).pop(value),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('lcp_passphrase_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('lcp_passphrase_submit'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Open'),
        ),
      ],
    );
  }
}
