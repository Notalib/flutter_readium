// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';

import '../opds.dart';
import '../publication/link.dart';
import '../publication/publication.dart';

class Group with EquatableMixin {
  Group({
    required this.title,
    OpdsMetadata? metadata,
    List<Link>? links,
    List<Publication>? publications,
    List<Link>? navigation,
  }) : metadata = metadata ?? OpdsMetadata(title: title),
       links = links ?? [],
       publications = publications ?? [],
       navigation = navigation ?? [];
  final String title;

  OpdsMetadata metadata;
  List<Link> links;
  List<Publication> publications;
  List<Link> navigation;

  @override
  List<Object?> get props => [title, metadata, links, publications, navigation];

  @override
  String toString() =>
      'Group{title: $title, metadata: $metadata, links: $links, '
      'publications: $publications, navigation: $navigation}';
}
