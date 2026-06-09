/// Log verbosity levels for the Readium plugin.
///
/// The **numeric index** of each value (0–4) is used directly as the bridge
/// payload when propagating the level to native (iOS / Android) and web (JS
/// bundle) sides. The TypeScript `LogLevel` enum in `logger.ts` declares the
/// same values explicitly (`none=0, error=1, warn=2, info=3, debug=4`) so that
/// `level.index.toJS` passes correctly without any translation layer.
///
/// Do not reorder or insert values — that would silently break the bridge.
enum LogLevel { none, error, warn, info, debug }
