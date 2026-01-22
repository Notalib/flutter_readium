// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:equatable/equatable.dart';

import '../../shared/index.dart' show Link;
import '../opds.dart' show OpdsMetadata;

class Facet with EquatableMixin {
  Facet({required this.title, OpdsMetadata? metadata, List<Link>? links})
    : metadata = metadata ?? OpdsMetadata(title: title),
      links = links ?? [];
  final String title;
  final OpdsMetadata metadata;
  final List<Link> links;

  @override
  List<Object> get props => [title, metadata, links];

  @override
  String toString() => 'Facet{title: $title, metadata: $metadata, links: $links}';
}
