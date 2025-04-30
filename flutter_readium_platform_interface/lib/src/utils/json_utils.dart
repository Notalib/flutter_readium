class JsonUtils {
  static Map<String, dynamic> trimStringsInMap(final Map<String, dynamic> map) {
    map.forEach((final key, final value) {
      if (value is String) {
        map[key] = value.trim();
      } else if (value is Map<String, dynamic>) {
        trimStringsInMap(value);
      } else if (value is List) {
        trimStringsInList(value);
      }
    });
    return map;
  }

  static void trimStringsInList(final List list) {
    for (var i = 0; i < list.length; i++) {
      final value = list[i];
      if (value is String) {
        list[i] = value.trim();
      } else if (value is Map<String, dynamic>) {
        trimStringsInMap(value);
      } else if (value is List) {
        trimStringsInList(value);
      }
    }
  }
}
