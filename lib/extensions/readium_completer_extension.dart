import 'dart:async';

extension ReadiumCompleterExtension on Completer {
  void safeComplete() {
    if (!isCompleted) {
      complete();
    }
  }
}
