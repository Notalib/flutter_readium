// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

class Drm {
  const Drm._(this.brand, this.scheme);
  static const Drm lcp = Drm._('lcp', 'http://readium.org/2014/01/lcp');
  final String brand;
  final String scheme;

  @override
  String toString() => 'Drm{brand: $brand, scheme: $scheme}';
}
