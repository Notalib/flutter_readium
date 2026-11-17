import 'package:material_ui/material_ui.dart';
import 'package:flutter_readium_lcp/flutter_readium_lcp.dart';

/// Shows the LCP license of the publication at [publicationPath] in a bottom sheet.
Future<void> showLcpLicenseSheet(final BuildContext context, final String publicationPath) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (final _) => _LcpLicenseSheet(publicationPath: publicationPath),
    );

class _LcpLicenseSheet extends StatefulWidget {
  const _LcpLicenseSheet({required this.publicationPath});

  final String publicationPath;

  @override
  State<_LcpLicenseSheet> createState() => _LcpLicenseSheetState();
}

class _LcpLicenseSheetState extends State<_LcpLicenseSheet> {
  late Future<LcpLicenseInfo> _info = FlutterReadiumLcp().getLicenseInfo(widget.publicationPath);
  var _busy = false;
  String? _failure;

  @override
  Widget build(final BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<LcpLicenseInfo>(
        future: _info,
        builder: (final context, final snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
          }
          final error = snapshot.error;
          if (error != null) {
            return Text('License unavailable: $error', key: const ValueKey('lcp_license_error'));
          }
          return _details(context, snapshot.requireData);
        },
      ),
    ),
  );

  Widget _details(final BuildContext context, final LcpLicenseInfo info) => Column(
    key: const ValueKey('lcp_license_info_sheet'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('LCP license', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      _row('lcp_license_id', 'Id', info.licenseId),
      _row('lcp_license_provider', 'Provider', info.provider),
      _row('lcp_license_issued', 'Issued', info.issued.toIso8601String()),
      _row('lcp_license_updated', 'Updated', info.updated.toIso8601String()),
      _row('lcp_license_rights_start', 'Rights start', info.rightsStart?.toIso8601String() ?? 'none'),
      _row('lcp_license_rights_end', 'Rights end', info.rightsEnd?.toIso8601String() ?? 'none'),
      _row('lcp_license_copy', 'Copy left', _allowance(info.charactersToCopyLeft, info.copyLimit)),
      _row('lcp_license_print', 'Print left', _allowance(info.pagesToPrintLeft, info.printLimit)),
      _row('lcp_license_state', 'Status', info.state?.name ?? 'no status document'),
      _row('lcp_license_can_renew', 'Can renew', info.canRenewLoan ? 'yes' : 'no'),
      _row('lcp_license_max_renew', 'Max renew date', info.maxRenewDate?.toIso8601String() ?? 'none'),
      _row('lcp_license_can_return', 'Can return', info.canReturnPublication ? 'yes' : 'no'),
      const SizedBox(height: 8),
      Row(
        children: [
          ElevatedButton(
            key: const ValueKey('lcp_renew_button'),
            onPressed: info.canRenewLoan && !_busy ? _renew : null,
            child: const Text('Renew loan'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            key: const ValueKey('lcp_return_button'),
            onPressed: info.canReturnPublication && !_busy ? _return : null,
            child: const Text('Return loan'),
          ),
        ],
      ),
      // The snackbar can sit behind the sheet, so the failure is also shown here.
      if (_failure != null) Text(_failure!, key: const ValueKey('lcp_loan_error')),
    ],
  );

  String get _path => widget.publicationPath;

  Future<void> _renew() => _run(() async {
    final info = await FlutterReadiumLcp().renewLoan(_path);
    if (!mounted) return;
    // A block body: setState rejects a callback that returns a Future.
    setState(() {
      _info = Future.value(info);
    });
  });

  /// A returned license cannot be read any more, so the sheet closes and reports the return instead.
  Future<void> _return() {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    return _run(() async {
      await FlutterReadiumLcp().returnPublication(_path);
      messenger.showSnackBar(const SnackBar(content: Text('LCP loan returned')));
      navigator.pop();
    });
  }

  /// Runs a loan action. Failures show up as a snackbar and under the buttons.
  Future<void> _run(final Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await action();
    } on LcpException catch (e) {
      final text = 'LCP failure: ${e.runtimeType}';
      messenger.showSnackBar(SnackBar(content: Text(text)));
      if (mounted) setState(() => _failure = text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _allowance(final int? left, final int? limit) =>
      limit == null ? 'no limit' : '${left ?? limit} of $limit';

  Widget _row(final String key, final String label, final String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text('$label: $value', key: ValueKey(key)),
  );
}
