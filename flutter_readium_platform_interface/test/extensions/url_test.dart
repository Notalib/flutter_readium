// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:flutter_readium_platform_interface/src/extensions/uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remove last component', () {
    expect(Uri.parse('http://domain.com/two/'), Uri.parse('http://domain.com/two/paths').removeLastComponent());
    expect(Uri.parse('http://domain.com/two/'), Uri.parse('http://domain.com/two/paths/').removeLastComponent());
    expect(Uri.parse('http://domain.com/'), Uri.parse('http://domain.com/path').removeLastComponent());
    expect(Uri.parse('http://domain.com/'), Uri.parse('http://domain.com/path/').removeLastComponent());
    expect(Uri.parse('http://domain.com/'), Uri.parse('http://domain.com/').removeLastComponent());
    expect(Uri.parse('http://domain.com'), Uri.parse('http://domain.com').removeLastComponent());
  });
}
