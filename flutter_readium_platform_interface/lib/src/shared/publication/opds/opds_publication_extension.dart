// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import '../link.dart';
import '../publication.dart';

extension OpdsPublicationExtension on Publication {
  List<Link> get images => collectionLinks('images');
}
