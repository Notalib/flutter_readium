// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// Originally from https://github.com/Mantano/iridium/blob/main/components/commons/lib/utils/take.dart

extension Take<T> on T {
  T? takeIf(bool Function(T) predicate) => (predicate(this)) ? this : null;

  T? takeUnless(bool Function(T) predicate) => (!predicate(this)) ? this : null;
}
