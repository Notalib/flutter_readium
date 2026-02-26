import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// BelongsTo Object for the Metadata object.
///
/// https://readium.org/webpub-manifest/schema/metadata.schema.json#belongsTo
@immutable
class BelongsTo extends AdditionalProperties with EquatableMixin implements JSONable {
  const BelongsTo({
    this.collections,
    this.journals,
    this.magazines,
    this.newspapers,
    this.periodicals,
    this.seasons,
    this.series,
    this.storyArcs,
    this.volumes,
    super.additionalProperties,
  });
  factory BelongsTo.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.from(json);
    final collection = Collection.listFromJson(jsonObject.opt('collection', remove: true));
    final journal = Periodical.listFromJson(jsonObject.opt('journal', remove: true));
    final magazine = Periodical.listFromJson(jsonObject.opt('magazine', remove: true));
    final newspaper = Periodical.listFromJson(jsonObject.opt('newspaper', remove: true));
    final periodical = Periodical.listFromJson(jsonObject.opt('periodical', remove: true));
    final season = Season.listFromJson(jsonObject.opt('season', remove: true));
    final series = Series.listFromJson(jsonObject.opt('series', remove: true));
    final storyArc = StoryArc.listFromJson(jsonObject.opt('storyArc', remove: true));
    final volume = Volume.listFromJson(jsonObject.opt('volume', remove: true));

    return BelongsTo(
      collections: collection,
      journals: journal,
      magazines: magazine,
      newspapers: newspaper,
      periodicals: periodical,
      seasons: season,
      series: series,
      storyArcs: storyArc,
      volumes: volume,
      additionalProperties: jsonObject,
    );
  }

  final List<Collection>? collections;
  final List<Periodical>? journals;
  final List<Periodical>? magazines;
  final List<Periodical>? newspapers;
  final List<Periodical>? periodicals;
  final List<Season>? seasons;
  final List<Series>? series;
  final List<StoryArc>? storyArcs;
  final List<Volume>? volumes;

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('collection', collections.toSingleOrMultiJson())
    ..putOpt('journal', journals.toSingleOrMultiJson())
    ..putOpt('magazine', magazines.toSingleOrMultiJson())
    ..putOpt('newspaper', newspapers.toSingleOrMultiJson())
    ..putOpt('periodical', periodicals.toSingleOrMultiJson())
    ..putOpt('season', seasons.toSingleOrMultiJson())
    ..putOpt('series', series.toSingleOrMultiJson())
    ..putOpt('storyArc', storyArcs.toSingleOrMultiJson())
    ..putOpt('volume', volumes.toSingleOrMultiJson());

  BelongsTo copyWith({
    List<Collection>? collections,
    List<Periodical>? journals,
    List<Periodical>? magazines,
    List<Periodical>? newspapers,
    List<Periodical>? periodicals,
    List<Season>? seasons,
    List<Series>? series,
    List<StoryArc>? storyArcs,
    List<Volume>? volumes,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return BelongsTo(
      collections: collections ?? this.collections,
      journals: journals ?? this.journals,
      magazines: magazines ?? this.magazines,
      newspapers: newspapers ?? this.newspapers,
      periodicals: periodicals ?? this.periodicals,
      seasons: seasons ?? this.seasons,
      series: series ?? this.series,
      storyArcs: storyArcs ?? this.storyArcs,
      volumes: volumes ?? this.volumes,
      additionalProperties: mergeProperties,
    );
  }

  @override
  List<Object?> get props => [
    collections,
    journals,
    magazines,
    newspapers,
    periodicals,
    seasons,
    series,
    storyArcs,
    volumes,
  ];
}
