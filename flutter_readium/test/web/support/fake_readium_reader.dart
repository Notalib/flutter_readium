// Browser-only test support: a fake of the `ReadiumReader` JS class that `js_publication_channel.dart`
// constructs. The Dart interop layer is the real code under test; only the JS bundle behind it is faked.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// One call the Dart side made into the fake `ReadiumReader`.
class FakeCall {
  FakeCall(this.method, this.args);

  final String method;

  /// Arguments as JSON-decoded by the fake, so strings stay strings and `null`/`undefined` become `null`.
  final List<Object?> args;

  @override
  String toString() => '$method($args)';
}

/// A scriptable stand-in for the JS `ReadiumReader` class.
///
/// Every method call is recorded. Promise-returning methods resolve with the configured value, or reject
/// when an error is configured; other methods return it or throw it synchronously. The fake is installed on
/// `globalThis` once per test page, because `JsPublicationChannel` constructs its `ReadiumReader` lazily
/// and only once. Call [reset] between tests.
class FakeReadiumReader {
  static const _promiseMethods = [
    'openPublication',
    'getPublication',
    'loadAsCurrentPublication',
    'goTo',
    'ttsGetAvailableVoices',
    'ttsEnable',
    'audioEnable',
    'getResourceUrl',
  ];

  static final _source =
      '''
(function () {
  const promiseMethods = new Set(${jsonEncode(_promiseMethods)});
  const state = {
    calls: [],
    returns: {},
    errors: {},
    props: {},
    defaults: { goToProgression: true, ttsGetAvailableVoices: '[]', getResourceUrl: '' },
    reset() {
      this.calls = [];
      this.returns = {};
      this.errors = {};
      this.props = { isNavigatorReady: true };
    },
    setReturn(name, json) { this.returns[name] = JSON.parse(json); },
    setProp(name, json) { this.props[name] = JSON.parse(json); },
    // Rejects/throws an Error with the given message. A non-null [code] makes it a typed ReadiumWebError.
    failWith(name, message, code, detailsJson) {
      const error = new Error(message);
      if (code != null) {
        error.code = code;
        if (detailsJson != null) error.details = JSON.parse(detailsJson);
      }
      this.errors[name] = error;
    },
    callsJson() { return JSON.stringify(this.calls); },
  };
  state.reset();
  globalThis.__readiumFake = state;
  globalThis.ReadiumReader = class ReadiumReader {
    constructor() {
      return new Proxy(this, {
        get(_target, name) {
          if (typeof name !== 'string') return undefined;
          if (Object.hasOwn(state.props, name)) return state.props[name];
          return (...args) => {
            state.calls.push({ method: name, args });
            const error = state.errors[name];
            const value = Object.hasOwn(state.returns, name) ? state.returns[name] : state.defaults[name];
            if (promiseMethods.has(name)) return error ? Promise.reject(error) : Promise.resolve(value);
            if (error) throw error;
            return value;
          };
        },
      });
    }
  };
})();
''';

  static bool _installed = false;

  static JSObject get _state => globalContext['__readiumFake']! as JSObject;

  /// Installs the fake on `globalThis`. Must run before the first use of `JsPublicationChannel`.
  static void install() {
    if (!_installed) {
      globalContext.callMethod<JSAny?>('eval'.toJS, _source.toJS);
      _installed = true;
    }
    reset();
  }

  /// Clears recorded calls, configured results and errors. The navigator is ready again.
  static void reset() => _state.callMethod<JSAny?>('reset'.toJS);

  /// Makes [method] return (or resolve with) [value], which must be JSON-encodable.
  static void returns(String method, Object? value) =>
      _state.callMethod<JSAny?>('setReturn'.toJS, method.toJS, jsonEncode(value).toJS);

  /// Sets a plain property such as `isNavigatorReady`.
  static void setProperty(String name, Object? value) =>
      _state.callMethod<JSAny?>('setProp'.toJS, name.toJS, jsonEncode(value).toJS);

  /// Makes [method] fail with a JS `Error`. With [code] it carries the typed `code`/`details` fields that
  /// the web bundle's `ReadiumWebError` has; without it, it is an untyped throw like a raw toolkit error.
  static void failWith(String method, String message, {String? code, Map<String, Object?>? details}) =>
      _state.callMethod<JSAny?>(
        'failWith'.toJS,
        method.toJS,
        message.toJS,
        code?.toJS,
        details == null ? null : jsonEncode(details).toJS,
      );

  /// Every call recorded so far, oldest first.
  static List<FakeCall> get calls {
    final json = (_state.callMethod<JSString>('callsJson'.toJS)).toDart;
    return (jsonDecode(json) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((c) => FakeCall(c['method'] as String, (c['args'] as List<dynamic>).cast<Object?>()))
        .toList();
  }

  static List<FakeCall> callsTo(String method) => calls.where((c) => c.method == method).toList();

  /// Calls a function the plugin registered on `globalThis` (for example `updateReaderStatus`), the way the
  /// JS bundle does.
  static void invokeGlobalCallback(String name, String argument) =>
      globalContext.callMethod<JSAny?>(name.toJS, argument.toJS);
}
