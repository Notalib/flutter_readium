/// Extension on the List class to add the `insertIfNotExists` method.
extension ReadiumListExtension<T> on List<T> {
  /// Inserts an item into the list if it does not already exist, based on a given test function.
  ///
  /// This method takes an item and a test function as parameters. It checks if the
  /// test function returns `true` for any existing item in the list. If the test
  /// function returns `false` for all items, the provided item is added to the list.
  ///
  /// Example usage:
  ///
  /// ```dart
  /// List<String> fruits = ['apple', 'banana', 'cherry'];
  /// fruits.insertIfNotExists('banana', (fruit) => fruit == 'banana'); // No insertion
  /// fruits.insertIfNotExists('date', (fruit) => fruit == 'date'); // Inserted
  /// print(fruits); // Output: [apple, banana, cherry, date]
  /// ```
  List<T> addOrUpdateIfNotExists(final T item, final bool Function(T) test) {
    if (!any(test)) {
      return [
        ...this,
        item,
      ];
    }

    return map((final i) {
      if (test(i)) {
        return item;
      }

      return i;
    }).toList();

    // !any(test) ? add(item) : map((final i) => test(i) ? item : i);
  }
}
