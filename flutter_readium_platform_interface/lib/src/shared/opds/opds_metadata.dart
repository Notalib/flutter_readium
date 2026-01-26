// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';

import '../../utils/jsonable.dart';

class OpdsMetadata with EquatableMixin implements JSONable {
  OpdsMetadata({
    required this.title,
    this.numberOfItems,
    this.itemsPerPage,
    this.currentPage,
    this.modified,
    this.position,
    this.rdfType,
  });
  String title;
  int? numberOfItems;
  int? itemsPerPage;
  int? currentPage;
  DateTime? modified;
  int? position;
  String? rdfType;

  @override
  List<Object?> get props => [title, numberOfItems, itemsPerPage, currentPage, modified, position, rdfType];

  @override
  String toString() =>
      'OpdsMetadata{title: $title, numberOfItems: $numberOfItems, '
      'itemsPerPage: $itemsPerPage, currentPage: $currentPage, '
      'modified: $modified, position: $position, rdfType: $rdfType}';

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'title': title}
      ..putOpt('numberOfItems', numberOfItems)
      ..putOpt('itemsPerPage', itemsPerPage)
      ..putOpt('currentPage', currentPage)
      ..putOpt('modified', modified?.toIso8601String())
      ..putOpt('position', position)
      ..putOpt('rdfType', rdfType);
    return json;
  }

  static OpdsMetadata? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    return OpdsMetadata(
      title: json['title'] as String? ?? '',
      numberOfItems: json['numberOfItems'] as int?,
      itemsPerPage: json['itemsPerPage'] as int?,
      currentPage: json['currentPage'] as int?,
      modified: json['modified'] != null ? DateTime.parse(json['modified'] as String) : null,
      position: json['position'] as int?,
      rdfType: json['rdfType'] as String?,
    );
  }
}
