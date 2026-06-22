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
  try {
    // On web, rejected JS promises arrive as JSObject. Avoid `is JSObject`
    // (invalid_runtime_check_with_js_interop_types); use a try-cast instead.
    final jsObj = e as js_interop.JSObject;
    final msg = (jsObj.getProperty<js_interop.JSAny?>('message'.toJS) as js_interop.JSString?)?.toDart;
    final stack = (jsObj.getProperty<js_interop.JSAny?>('stack'.toJS) as js_interop.JSString?)?.toDart;
    if (msg != null || stack != null) {
      return [?msg, ?stack].join('\n');
    }
  } on Object {
    // Not a JS interop object; fall through to toString.
  }
  return e.toString();
}
