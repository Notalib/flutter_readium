// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:dartx/dartx.dart';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../utils/additional_properties.dart';
import '../../utils/jsonable.dart';

class OpdsMetadata extends AdditionalProperties with EquatableMixin implements JSONable {
  const OpdsMetadata({
    required this.title,
    this.numberOfItems,
    this.itemsPerPage,
    this.currentPage,
    this.modified,
    this.position,
    this.rdfType,
    super.additionalProperties,
  });

  // TODO: handle multi-language titles

  final String title;
  final int? numberOfItems;
  final int? itemsPerPage;
  final int? currentPage;
  final DateTime? modified;
  final int? position;
  final String? rdfType;

  @override
  List<Object?> get props => [
    title,
    numberOfItems,
    itemsPerPage,
    currentPage,
    modified,
    position,
    rdfType,
    additionalProperties,
  ];

  OpdsMetadata copyWith({
    String? title,
    int? numberOfItems,
    int? itemsPerPage,
    int? currentPage,
    DateTime? modified,
    int? position,
    String? rdfType,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return OpdsMetadata(
      title: title ?? this.title,
      numberOfItems: numberOfItems ?? this.numberOfItems,
      itemsPerPage: itemsPerPage ?? this.itemsPerPage,
      currentPage: currentPage ?? this.currentPage,
      modified: modified ?? this.modified,
      position: position ?? this.position,
      rdfType: rdfType ?? this.rdfType,
      additionalProperties: mergeProperties,
    );
  }

  @override
  String toString() =>
      'OpdsMetadata{title: $title, numberOfItems: $numberOfItems, '
      'itemsPerPage: $itemsPerPage, currentPage: $currentPage, '
      'modified: $modified, position: $position, rdfType: $rdfType}'
      'additionalProperties: $additionalProperties';

  @override
  Map<String, dynamic> toJson() {
    final json = Map<String, dynamic>.from(additionalProperties)
      ..put('title', title)
      ..putOpt('numberOfItems', numberOfItems)
      ..putOpt('itemsPerPage', itemsPerPage)
      ..putOpt('currentPage', currentPage)
      ..putOpt('modified', modified?.toIso8601String())
      ..putOpt('position', position)
      ..putOpt('@type', rdfType);
    return json;
  }

  static OpdsMetadata? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final title = json.safeRemove('title') as String? ?? '';
    final numberOfItems = json.safeRemove('numberOfItems') as int?;
    final itemsPerPage = json.safeRemove('itemsPerPage') as int?;
    final currentPage = json.safeRemove('currentPage') as int?;
    final modifiedString = json.safeRemove('modified') as String?;
    final modified = modifiedString != null ? DateTime.parse(modifiedString) : null;
    final position = json.safeRemove('position') as int?;
    final rdfType = [
      json.safeRemove('@type') as String?,
      json.safeRemove('rdfType') as String?,
    ].firstOrNullWhere((element) => element != null);

    return OpdsMetadata(
      title: title,
      numberOfItems: numberOfItems,
      itemsPerPage: itemsPerPage,
      currentPage: currentPage,
      modified: modified,
      position: position,
      rdfType: rdfType,
      additionalProperties: json,
    );
  }
}

class OpdsMetadataJsonConverter extends JsonConverter<OpdsMetadata?, Map<String, dynamic>?> {
  const OpdsMetadataJsonConverter();

  @override
  OpdsMetadata? fromJson(Map<String, dynamic>? json) => OpdsMetadata.fromJson(json);

  @override
  Map<String, dynamic>? toJson(OpdsMetadata? metadata) => metadata?.toJson();
}
