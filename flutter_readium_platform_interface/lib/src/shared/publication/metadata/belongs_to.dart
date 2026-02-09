import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../../flutter_readium_platform_interface.dart';

@immutable
class BelongsTo extends AdditionalProperties with EquatableMixin implements JSONable {
  const BelongsTo({
    this.collection,
    this.journal,
    this.magazine,
    this.newspaper,
    this.periodical,
    this.season,
    this.series,
    this.storyArc,
    this.volume,
    super.additionalProperties,
  });
  factory BelongsTo.fromJson(
    Map<String, dynamic> json, {
    LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity,
  }) {
    final jsonObject = Map<String, dynamic>.from(json);
    final collection = Collection.listFromJson(
      jsonObject.opt('collection', remove: true),
      normalizeHref: normalizeHref,
    );
    final journal = Periodical.listFromJson(jsonObject.opt('journal', remove: true), normalizeHref: normalizeHref);
    final magazine = Periodical.listFromJson(jsonObject.opt('magazine', remove: true), normalizeHref: normalizeHref);
    final newspaper = Periodical.listFromJson(jsonObject.opt('newspaper', remove: true), normalizeHref: normalizeHref);
    final periodical = Periodical.listFromJson(
      jsonObject.opt('periodical', remove: true),
      normalizeHref: normalizeHref,
    );
    final season = Season.listFromJson(jsonObject.opt('season', remove: true), normalizeHref: normalizeHref);
    final series = Series.listFromJson(jsonObject.opt('series', remove: true), normalizeHref: normalizeHref);
    final storyArc = StoryArc.listFromJson(jsonObject.opt('storyArc', remove: true), normalizeHref: normalizeHref);
    final volume = Volume.listFromJson(jsonObject.opt('volume', remove: true), normalizeHref: normalizeHref);

    return BelongsTo(
      collection: collection,
      journal: journal,
      magazine: magazine,
      newspaper: newspaper,
      periodical: periodical,
      season: season,
      series: series,
      storyArc: storyArc,
      volume: volume,
      additionalProperties: jsonObject,
    );
  }

  final List<Collection>? collection;
  final List<Periodical>? journal;
  final List<Periodical>? magazine;
  final List<Periodical>? newspaper;
  final List<Periodical>? periodical;
  final List<Season>? season;
  final List<Series>? series;
  final List<StoryArc>? storyArc;
  final List<Volume>? volume;

  @override
  Map<String, dynamic> toJson() => {}
    ..putIterableIfNotEmpty('collection', collection)
    ..putIterableIfNotEmpty('journal', journal)
    ..putIterableIfNotEmpty('magazine', magazine)
    ..putIterableIfNotEmpty('newspaper', newspaper)
    ..putIterableIfNotEmpty('periodical', periodical)
    ..putIterableIfNotEmpty('season', season)
    ..putIterableIfNotEmpty('series', series)
    ..putIterableIfNotEmpty('storyArc', storyArc)
    ..putIterableIfNotEmpty('volume', volume);

  BelongsTo copyWith({
    List<Collection>? collection,
    List<Periodical>? journal,
    List<Periodical>? magazine,
    List<Periodical>? newspaper,
    List<Periodical>? periodical,
    List<Season>? season,
    List<Series>? series,
    List<StoryArc>? storyArc,
    List<Volume>? volume,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return BelongsTo(
      collection: collection ?? this.collection,
      journal: journal ?? this.journal,
      magazine: magazine ?? this.magazine,
      newspaper: newspaper ?? this.newspaper,
      periodical: periodical ?? this.periodical,
      season: season ?? this.season,
      series: series ?? this.series,
      storyArc: storyArc ?? this.storyArc,
      volume: volume ?? this.volume,
      additionalProperties: mergeProperties,
    );
  }

  @override
  List<Object?> get props => [collection, journal, magazine, newspaper, periodical, season, series, storyArc, volume];
}
