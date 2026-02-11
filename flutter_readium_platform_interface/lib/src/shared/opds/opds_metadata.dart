// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

import '../../../flutter_readium_platform_interface.dart';

@immutable
class OpdsMetadata extends AdditionalProperties with EquatableMixin implements JSONable {
  const OpdsMetadata({
    required this.localizedTitle,
    this.identifier,
    this.localizedSubtitle,
    this.description,
    this.numberOfItems,
    this.itemsPerPage,
    this.currentPage,
    this.modified,
    this.position,
    this.rdfType,
    super.additionalProperties,
  });

  final String? identifier;

  final LocalizedString localizedTitle;
  String get title => localizedTitle.string;
  final LocalizedString? localizedSubtitle;
  String? get subtitle => localizedSubtitle?.string;
  final String? description;
  final int? numberOfItems;
  final int? itemsPerPage;
  final int? currentPage;
  final DateTime? modified;
  final double? position;
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
    LocalizedString? localizedTitle,
    LocalizedString? localizedSubtitle,
    String? identifier,
    String? description,
    int? numberOfItems,
    int? itemsPerPage,
    int? currentPage,
    DateTime? modified,
    double? position,
    String? rdfType,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return OpdsMetadata(
      localizedTitle: localizedTitle ?? this.localizedTitle,
      localizedSubtitle: localizedSubtitle ?? this.localizedSubtitle,
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
      ..putJSONableIfNotEmpty('title', localizedTitle)
      ..putJSONableIfNotEmpty('subtitle', localizedSubtitle)
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

    final localizedTitle = LocalizedString.fromJsonDynamic(jsonObject.opt('title', remove: true)) ?? LocalizedString();
    final description = jsonObject.optNullableString('description', remove: true);
    final localizedSubtitle = LocalizedString.fromJsonDynamic(jsonObject.opt('subtitle', remove: true));
    final identifier = jsonObject.optNullableString('identifier', remove: true);
    final numberOfItems = jsonObject.optNullableInt('numberOfItems', remove: true);
    final itemsPerPage = jsonObject.optNullableInt('itemsPerPage', remove: true);
    final currentPage = jsonObject.optNullableInt('currentPage', remove: true);
    final modified = jsonObject.optNullableDateTime('modified', remove: true);
    final position = jsonObject.optNullableDouble('position', remove: true);
    final rdfType = [
      jsonObject.optNullableString('@type', remove: true),
      jsonObject.optNullableString('rdfType', remove: true),
    ].firstWhereOrNull((element) => element != null);

    return OpdsMetadata(
      localizedTitle: localizedTitle,
      localizedSubtitle: localizedSubtitle,
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
