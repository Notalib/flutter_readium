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
    this.identifier,
    this.subtitle,
    this.description,
    this.numberOfItems,
    this.itemsPerPage,
    this.currentPage,
    this.modified,
    this.position,
    this.rdfType,
    super.additionalProperties,
  });

  // TODO: handle multi-language titles

  final String? identifier;
  final String title;
  final String? subtitle;
  final String? description;
  final int? numberOfItems;
  final int? itemsPerPage;
  final int? currentPage;
  final DateTime? modified;
  final int? position;
  final String? rdfType;

  @override
  List<Object?> get props => [
    title,
    identifier,
    subtitle,
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
    String? subtitle,
    String? identifier,
    String? description,
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
      subtitle: subtitle ?? this.subtitle,
      identifier: identifier ?? this.identifier,
      description: description ?? this.description,
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
      'OpdsMetadata{title: $title, subtitle: $subtitle, identifier: $identifier, numberOfItems: $numberOfItems, '
      'itemsPerPage: $itemsPerPage, currentPage: $currentPage, '
      'modified: $modified, position: $position, rdfType: $rdfType}'
      'additionalProperties: $additionalProperties';

  @override
  Map<String, dynamic> toJson() {
    final json = Map<String, dynamic>.from(additionalProperties)
      ..put('title', title)
      ..putOpt('subtitle', subtitle)
      ..putOpt('identifier', identifier)
      ..putOpt('description', description)
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

    final jsonObject = Map<String, dynamic>.of(json);

    final title = jsonObject.optNullableString('title', remove: true) ?? '';
    final description = jsonObject.optNullableString('description', remove: true);
    final subtitle = jsonObject.optNullableString('subtitle', remove: true);
    final identifier = jsonObject.optNullableString('identifier', remove: true);
    final numberOfItems = jsonObject.optNullableInt('numberOfItems', remove: true);
    final itemsPerPage = jsonObject.optNullableInt('itemsPerPage', remove: true);
    final currentPage = jsonObject.optNullableInt('currentPage', remove: true);
    final modified = jsonObject.optNullableDateTime('modified', remove: true);
    final position = jsonObject.optNullableInt('position', remove: true);
    final rdfType = [
      jsonObject.optNullableString('@type', remove: true),
      jsonObject.optNullableString('rdfType', remove: true),
    ].firstOrNullWhere((element) => element != null);

    return OpdsMetadata(
      title: title,
      subtitle: subtitle,
      identifier: identifier,
      description: description,
      numberOfItems: numberOfItems,
      itemsPerPage: itemsPerPage,
      currentPage: currentPage,
      modified: modified,
      position: position,
      rdfType: rdfType,
      additionalProperties: jsonObject,
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
