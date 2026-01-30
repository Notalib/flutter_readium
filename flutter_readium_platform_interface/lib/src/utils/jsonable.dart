// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// Originally from https://github.com/Mantano/iridium/blob/main/components/commons/lib/utils/jsonable.dart

import 'package:dartx/dartx.dart';
import '../extensions/strings.dart';
import 'take.dart';

/// An interface for classes that can be serialized to JSON.
/// Subclasses must implement [toJson] and a static [fromJSON] method.
/// As well as a JsonConverter.
abstract interface class JSONable {
  /// Serializes the object to its JSON representation.
  Map<String, dynamic> toJson();
}

extension IterableJSONableExtension on Iterable<JSONable> {
  /// Serializes a list of [JSONable] into a [List<Map<String, dynamic>>].
  List<Map<String, dynamic>> toJson() => map((it) => it.toJson()).whereNotNull().toList();
}

extension MapExtension on Map<String, dynamic>? {
  static const String _null = 'null';

  dynamic _wrapJSON(dynamic value) {
    if (value is JSONable) {
      return value.toJson().takeIf((it) => it.isNotEmpty);
    } else if (value is Map) {
      return (value)
          .takeIf((it) => it.isNotEmpty)
          ?.map((key, value) => MapEntry<dynamic, dynamic>(key, _wrapJSON(value)));
    } else if (value is List) {
      return (value).takeIf((it) => it.isNotEmpty)?.mapNotNull(_wrapJSON).toList();
    }
    return value;
  }

  String? __toString(dynamic value) {
    if (value is String) {
      return value;
    } else if (value != null) {
      return value.toString();
    }
    return null;
  }

  bool? _toBoolean(dynamic value) {
    if (value is bool) {
      return value;
    } else if (value is String) {
      return value.toBooleanOrNull();
    }
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value is double) {
      return value;
    } else if (value is num) {
      return value.toDouble();
    } else if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  int? _toInteger(dynamic value) {
    if (value is int) {
      return value;
    } else if (value is num) {
      return value.toInt();
    } else if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  DateTime? _toDateTime(dynamic value) {
    if (value is DateTime) {
      return value;
    } else if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// Returns true if this object has no mapping for {@code name} or if it has
  /// a mapping whose value is {@link #NULL}.
  bool isNull(String name) {
    final dynamic value = opt(name);
    return value == null || value == _null;
  }

  /// Removes the mapping for [name] if it exists and is of type [T], and returns the value.
  /// Returns null if no such mapping exists.
  T? safeRemove<T>(String name) {
    final dynamic value = opt(name, remove: true);
    if (value is T) {
      return value;
    }

    return null;
  }

  /// Returns the value mapped by {@code name}, or null if no such mapping
  /// exists.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  dynamic opt(String name, {bool remove = false}) {
    if (this == null) {
      return null;
    }

    if (remove && this!.containsKey(name)) {
      return this!.remove(name);
    }

    return this![name];
  }

  void put(String name, dynamic object) {
    if (this != null) {
      this![name] = object;
    }
  }

  void putOpt(String? name, Object? value) {
    if (name == null || value == null) {
      return;
    }
    put(name, value);
  }

  /// Maps [name] to [jsonObject], clobbering any existing name/value mapping with the same name. If
  /// the [Map] is empty, any existing mapping for [name] is removed.
  void putObjectIfNotEmpty(String name, Map<String, dynamic>? jsonObject) {
    if (jsonObject == null || jsonObject.isEmpty) {
      this?.remove(name);
      return;
    }
    put(name, jsonObject);
  }

  /// Maps [name] to [jsonable] after converting it to a [Map], clobbering any existing
  /// name/value mapping with the same name. If the [Map] argument is empty, any existing mapping
  /// for [name] is removed.
  void putJSONableIfNotEmpty(String name, JSONable? jsonable) {
    final json = jsonable?.toJson();
    if (json == null || json.isEmpty) {
      this?.remove(name);
      return;
    }
    put(name, json);
  }

  /// Maps [name] to [collection] after wrapping it in a [List], clobbering any existing
  /// name/value mapping with the same name. If the collection is empty, any existing mapping
  /// for [name] is removed.
  /// If the objects in [collection] are [JSONable], then they are converted to [Map] first.
  void putIterableIfNotEmpty(String name, Iterable<dynamic>? collection) {
    final list = collection?.whereNotNull().mapNotNull(_wrapJSON).toList() ?? [];
    if (list.isEmpty) {
      this?.remove(name);
      return;
    }
    put(name, list);
  }

  /// Maps [name] to [map] after wrapping it in a [Map], clobbering any existing name/value
  /// mapping with the same name. If the map is empty, any existing mapping for [name] is removed.
  /// If the objects in [map] are [JSONable], then they are converted to [Map] first.
  void putMapIfNotEmpty(String name, Map<String, dynamic> map) {
    final map2 = map.map((key, value) => MapEntry(key, _wrapJSON(value)));
    if (map2.isEmpty) {
      this?.remove(name);
      return;
    }
    put(name, map2);
  }

  /// Returns the value mapped by [name] if it exists and is a positive integer or can be coerced to a
  /// positive integer, or [fallback] otherwise.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  int? optPositiveInt(String name, {int fallback = -1, bool remove = false}) {
    final i = optInt(name, fallback: fallback, remove: remove);
    final value = (i >= 0) ? i : null;
    return value;
  }

  /// Returns the value mapped by [name] if it exists and is a positive double or can be coerced to a
  /// positive double, or [fallback] otherwise.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  double? optPositiveDouble(String name, {double fallback = -1.0, bool remove = false}) {
    final d = optDouble(name, fallback: fallback, remove: remove);
    final value = (d >= 0) ? d : null;
    return value;
  }

  /// Returns the value mapped by [name] if it exists, coercing it if necessary, or `null` if no such
  /// mapping exists.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  String? optNullableString(String name, {bool remove = false}) {
    // optString() returns "null" if the key exists but contains the `null` value.
    // https://stackoverflow.com/questions/18226288/json-jsonobject-optstring-returns-string-null
    if (isNull(name)) {
      return null;
    }

    final s = optString(name, remove: remove);
    return (s != '') ? s : null;
  }

  /// Returns the value mapped by {@code name} if it exists, coercing it if
  /// necessary, or {@code fallback} if no such mapping exists.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  String optString(String name, {String fallback = '', bool remove = false}) {
    final dynamic object = opt(name, remove: remove);

    return __toString(object) ?? fallback;
  }

  /// Returns the value mapped by {@code name} if it exists and is a boolean or
  /// can be coerced to a boolean, or {@code fallback} otherwise.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  bool optBoolean(String name, {bool fallback = false, bool remove = false}) {
    final dynamic object = opt(name, remove: remove);
    return _toBoolean(object) ?? fallback;
  }

  /// Returns the value mapped by {@code name} if it exists and is an int or
  /// can be coerced to an int, or {@code fallback} otherwise.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  int optInt(String name, {int fallback = 0, bool remove = false}) {
    final dynamic object = opt(name, remove: remove);
    return _toInteger(object) ?? fallback;
  }

  /// Returns the value mapped by {@code name} if it exists and is a double or
  /// can be coerced to a double, or {@code fallback} otherwise.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  double optDouble(String name, {double fallback = double.nan, bool remove = false}) {
    final dynamic object = opt(name, remove: remove);
    return _toDouble(object) ?? fallback;
  }

  /// Returns the value mapped by {@code name} if it exists and is a {@code
  /// Map}, or null otherwise.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  Map<String, dynamic>? optJsonObject(String name, {bool remove = false}) {
    final dynamic object = opt(name, remove: remove);
    return object is Map<String, dynamic> ? object : null;
  }

  /// Returns the value mapped by {@code name} if it exists and is a {@code
  /// JSONArray}, or null otherwise.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  List<dynamic>? optJsonArray(String name, {bool remove = false}) {
    final dynamic object = opt(name, remove: remove);
    return object is Iterable ? object.toList() : null;
  }

  /// Returns the value mapped by [name] if it exists, coercing it if necessary, or `null` if no such
  /// mapping exists.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  bool? optNullableBoolean(String name, {bool remove = false}) {
    if (this?.containsKey(name) == false) {
      return null;
    }
    return optBoolean(name, remove: remove);
  }

  /// Returns the value mapped by [name] if it exists, coercing it if necessary, or `null` if no such
  /// mapping exists.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  int? optNullableInt(String name, {bool remove = false}) {
    if (this?.containsKey(name) == false) {
      return null;
    }
    return optInt(name, remove: remove);
  }

  /// Returns the value mapped by [name] if it exists, coercing it if necessary, or `null` if no such
  /// mapping exists.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  double? optNullableDouble(String name, {bool remove = false}) {
    if (this?.containsKey(name) == false) {
      return null;
    }
    return optDouble(name, remove: remove);
  }

  /// Returns the value mapped by [name] if it exists and is a DateTime or can be coerced to a
  /// DateTime, or `null` if no such mapping exists.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  DateTime? optNullableDateTime(String name, {bool remove = false}) {
    final dynamic object = opt(name, remove: remove);
    return _toDateTime(object);
  }

  /// Returns the value mapped by [name] if it exists and is a Map<String, dynamic>, or `null` if no
  /// such mapping exists.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  Map<String, dynamic>? optNullableMap(String name, {bool remove = false}) {
    final dynamic object = opt(name, remove: remove);
    if (object is Map<String, dynamic>) {
      return object;
    }
    return null;
  }

  /// Returns a list containing the results of applying the given transform function to each element
  /// in the original [Map].
  /// If the tranform returns `null`, it is not included in the output list.
  List<T> mapNotNull<T>(T Function(String, dynamic) transform) {
    final result = <T>[];
    if (this != null) {
      for (final key in this!.keys) {
        final transformedValue = transform(key, this![key]);
        if (transformedValue != null) {
          result.add(transformedValue);
        }
      }
    }
    return result;
  }

  /// Returns the value mapped by [name] if it exists and is either a [List] of [String] or a
  /// single [String] value, or an empty list otherwise.
  /// If [remove] is true, then the mapping will be removed from the [Map].
  ///
  /// E.g. ["a", "b"] or "a"
  List<String> optStringsFromArrayOrSingle(String name, {bool remove = false}) {
    final dynamic value = opt(name, remove: remove);
    if (value is Map) {
      return (value).values.whereType<String>().toList();
    } else if (value is List) {
      return value.whereType<String>().toList();
    } else if (value is String) {
      return [value];
    } else {
      return [];
    }
  }
}

extension ListExtension on List<dynamic>? {
  /// Parses a JSONArray of JSONObject into a [List] of models using the given [transform].
  List<T> parseObjects<T>(T? Function(dynamic) transform) {
    if (this == null || this!.isEmpty) {
      return [];
    }
    final models = <T>[];
    for (final dynamic element in this!) {
      final model = transform(element);
      if (model != null) {
        models.add(model);
      }
    }
    return models;
  }
}
