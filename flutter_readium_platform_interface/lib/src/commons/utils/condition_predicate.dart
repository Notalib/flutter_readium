// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'condition_type.dart';

class ConditionPredicate {
  ConditionPredicate(this.type, this.field, this.value);
  final ConditionType type;
  final String field;
  final Object value;

  static String fullTextField = 'keywords';

  bool get isFullTextField => field == fullTextField;

  bool get mustSplit {
    if (type.maxListItems == 1) {
      return false;
    }
    return (value is Iterable) && (value as Iterable).length > type.maxListItems;
  }

  String get orderByField => isFullTextField ? 'title' : field;

  @override
  String toString() => 'ConditionPredicate{type: $type, field: $field, value: $value}';
}
