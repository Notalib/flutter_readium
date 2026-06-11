import 'dart:js_interop' as js_interop;
import 'dart:js_interop_unsafe';

/// Extracts a human-readable description from a throwable that crossed the
/// JS↔Dart boundary.
///
/// When Dart awaits a rejected JS `Promise`, the rejection value arrives as a
/// raw [js_interop.JSObject] (not a Dart `Exception` or `Error`). The default
/// `.toString()` only yields the JS `Error.message`; the call site in
/// `.stack` — which identifies the failing TypeScript file and line — is
/// silently dropped.
///
/// This helper reads both `.message` and `.stack` directly off the JS object
/// so they survive into [PlatformException.message] and ultimately appear in
/// `flutter logs` and crash reports. Falls back to [Object.toString] for
/// non-JS-object throwables (e.g. Dart-native exceptions re-thrown through
/// the same catch block).
String describeJsError(Object e) {
  if (e is js_interop.JSObject) {
    final msg = (e.getProperty<js_interop.JSAny?>('message'.toJS) as js_interop.JSString?)?.toDart;
    final stack = (e.getProperty<js_interop.JSAny?>('stack'.toJS) as js_interop.JSString?)?.toDart;
    if (msg != null || stack != null) {
      return [if (msg != null) msg, if (stack != null) stack].join('\n');
    }
  }
  return e.toString();
}
