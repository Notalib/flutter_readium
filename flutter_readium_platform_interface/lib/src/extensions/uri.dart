// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// Originally from https://github.com/Mantano/iridium/blob/main/components/commons/lib/extensions/uri.dart

import 'package:dartx/dartx.dart';
import 'package:path/path.dart' as p;

extension UriExtension on Uri {
  Uri removeLastComponent() {
    final lastPathComponent = path.split('/').lastOrNullWhere((it) => it.isNotEmpty);
    if (lastPathComponent == null) {
      return this;
    }
    return Uri.parse(toString().removeSuffix('/').removeSuffix(lastPathComponent));
  }

  String get extension => p.extension(path);
}
