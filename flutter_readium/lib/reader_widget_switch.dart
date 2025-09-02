export 'reader_widget_unsupported.dart'
    if (dart.library.js_interop) 'reader_widget_web.dart'
    if (dart.library.io) 'reader_widget.dart';
