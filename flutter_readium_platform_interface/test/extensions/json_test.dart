// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:flutter_readium_platform_interface/src/extensions/strings.dart';
import 'package:flutter_readium_platform_interface/src/utils/jsonable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unpack an empty JSONObject', () {
    final sut = '{}'.toJsonOrNull();
    expect(sut, {});
  });

  test('unpack a JSONObject', () {
    final sut =
        '''{
            "a": 1,
            "b": "hello",
            "c": true
        }'''
            .toJsonOrNull();
    expect(sut, {'a': 1, 'b': 'hello', 'c': true});
  });

  test('unpack a nested JSONObject', () {
    final sut =
        '''{
            "a": 1,
            "b": { "b.1": "hello" },
            "c": [true, 42, "world"]
        }'''
            .toJsonOrNull();
    expect(sut, {
      'a': 1,
      'b': {'b.1': 'hello'},
      'c': [true, 42, 'world'],
    });
  });

  test('unpack an empty JSONArray', () {
    final sut = '[]'.toJsonArrayOrNull();
    expect(sut, []);
  });

  test('unpack a JSONArray', () {
    final sut = '[1, "hello", true]'.toJsonArrayOrNull();
    expect(sut, [1, 'hello', true]);
  });

  test('unpack a nested JSONArray', () {
    final sut =
        '''[
            1,
            { "b.1": "hello" },
            [true, 42, "world"]
        ]'''
            .toJsonArrayOrNull();
    expect(sut!.toList(), [
      1,
      {'b.1': 'hello'},
      [true, 42, 'world'],
    ]);
  });

  test('optNullableString() handles null values', () {
    // optString() returns "null" if the key exists but contains the `null` value.
    // https://stackoverflow.com/questions/18226288/json-jsonobject-optstring-returns-string-null
    final sut = '''{ "key": null }'''.toJsonOrNull();
    expect(sut.optNullableString('key'), isNull);
  });
}
