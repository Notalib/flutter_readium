extension ReadiumIterableExtension<T> on Iterable<T> {
  int indexWhere(final bool Function(T) test) {
    var index = 0;
    for (final item in this) {
      if (test.call(item)) {
        return index;
      }
      index++;
    }

    return -1;
  }
}
