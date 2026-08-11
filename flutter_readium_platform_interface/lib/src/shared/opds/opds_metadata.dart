// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../../flutter_readium_platform_interface.dart';

@immutable
class OpdsMetadata extends AdditionalProperties with Equatable implements JSONable {
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

  static const _unset = Object();

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
    Object? localizedTitle = _unset,
    Object? localizedSubtitle = _unset,
    Object? identifier = _unset,
    Object? description = _unset,
    Object? numberOfItems = _unset,
    Object? itemsPerPage = _unset,
    Object? currentPage = _unset,
    Object? modified = _unset,
    Object? position = _unset,
    Object? rdfType = _unset,
    Object? additionalProperties = _unset,
  }) {
    final mergeProperties = identical(additionalProperties, _unset) || additionalProperties == null
        ? Map<String, dynamic>.of(this.additionalProperties)
        : Map<String, dynamic>.of(this.additionalProperties)
            ..addAll(additionalProperties as Map<String, dynamic>)
            ..removeWhere((key, value) => value == null);

    return OpdsMetadata(
      localizedTitle: identical(localizedTitle, _unset) ? this.localizedTitle : (localizedTitle as LocalizedString?)!,
      localizedSubtitle: identical(localizedSubtitle, _unset)
          ? this.localizedSubtitle
          : localizedSubtitle as LocalizedString?,
      identifier: identical(identifier, _unset) ? this.identifier : identifier as String?,
      description: identical(description, _unset) ? this.description : description as String?,
      numberOfItems: identical(numberOfItems, _unset) ? this.numberOfItems : numberOfItems as int?,
      itemsPerPage: identical(itemsPerPage, _unset) ? this.itemsPerPage : itemsPerPage as int?,
      currentPage: identical(currentPage, _unset) ? this.currentPage : currentPage as int?,
      modified: identical(modified, _unset) ? this.modified : modified as DateTime?,
      position: identical(position, _unset) ? this.position : position as double?,
      rdfType: identical(rdfType, _unset) ? this.rdfType : rdfType as String?,
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

    final localizedTitle =
        LocalizedString.fromJsonDynamic(
          jsonObject.opt('title', remove: true),
        ) ??
        LocalizedString();
    final description = jsonObject.optNullableString(
      'description',
      remove: true,
    );
    final localizedSubtitle = LocalizedString.fromJsonDynamic(
      jsonObject.opt('subtitle', remove: true),
    );
    final identifier = jsonObject.optNullableString('identifier', remove: true);
    final numberOfItems = jsonObject.optNullableInt(
      'numberOfItems',
      remove: true,
    );
    final itemsPerPage = jsonObject.optNullableInt(
      'itemsPerPage',
      remove: true,
    );
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
