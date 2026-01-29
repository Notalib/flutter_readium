// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:dartx/dartx.dart';
import 'package:dfunc/dfunc.dart';
import 'package:equatable/equatable.dart';
import 'package:fimber/fimber.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../utils/href.dart';
import '../../utils/jsonable.dart';
import '../../utils/uri_template.dart';
import '../mediatype/mediatype.dart';
import 'properties.dart';

export 'link_list_extension.dart';

/// Function used to recursively transform the href of a [Link] when parsing its JSON
/// representation.
typedef LinkHrefNormalizer = String Function(String);

/// Default href normalizer for [Link], doing nothing.
const LinkHrefNormalizer linkHrefNormalizerIdentity = identity;

/// Link to a resource, either relative to a [Publication] or external (remote).
///
/// See https://readium.org/webpub-manifest/schema/link.schema.json
class Link with EquatableMixin implements JSONable {
  const Link({
    required this.href,
    this.id,
    this.templated = false,
    this.type,
    this.title,
    this.rels = const {},
    this.properties = const Properties(),
    this.height,
    this.width,
    this.bitrate,
    this.duration,
    this.languages = const [],
    this.alternates = const [],
    this.children = const [],
  });

  /// Creates an [Link] from its RWPM JSON representation.
  /// It's [href] and its children's recursively will be normalized using the provided
  /// [normalizeHref] closure.
  /// If the link can't be parsed, a warning will be logged with [warnings].
  static Link? fromJson(
    Map<String, dynamic>? json, {
    LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity,
  }) {
    final href = json?.optNullableString('href');
    if (href == null) {
      Fimber.i('[href] is required: $json');
      return null;
    }

    return Link(
      href: normalizeHref(href),
      type: json.optNullableString('type'),
      templated: json.optBoolean('templated', fallback: false),
      title: json.optNullableString('title'),
      rels: json.optStringsFromArrayOrSingle('rel').toSet(),
      properties: Properties.fromJson(json.optJSONObject('properties')),
      height: json.optPositiveInt('height'),
      width: json.optPositiveInt('width'),
      bitrate: json.optPositiveDouble('bitrate'),
      duration: json.optPositiveDouble('duration'),
      languages: json.optStringsFromArrayOrSingle('language'),
      alternates: fromJSONArray(json.optJSONArray('alternate'), normalizeHref: normalizeHref),
      children: fromJSONArray(json.optJSONArray('children'), normalizeHref: normalizeHref),
    );
  }

  /// Creates a list of [Link] from its RWPM JSON representation.
  /// It's [href] and its children's recursively will be normalized using the provided
  /// [normalizeHref] closure.
  /// If a link can't be parsed, a warning will be logged with [warnings].
  static List<Link> fromJSONArray(
    List<dynamic>? json, {
    LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity,
  }) => (json ?? []).parseObjects(
    (it) => Link.fromJson(it as Map<String, dynamic>?, normalizeHref: normalizeHref),
  );

  /// (Nullable) Unique identifier for this link in the [Publication].
  final String? id;

  /// URI or URI template of the linked resource.
  final String href; // URI

  /// Indicates that a URI template is used in href.
  final bool templated;

  /// (Nullable) MIME type of the linked resource.
  final String? type;

  /// (Nullable) Title of the linked resource.
  final String? title;

  /// Relations between the linked resource and its containing collection.
  final Set<String> rels;

  /// Properties associated to the linked resource.
  final Properties properties;

  /// (Nullable) Height of the linked resource in pixels.
  final int? height;

  /// (Nullable) Width of the linked resource in pixels.
  final int? width;

  /// (Nullable) Bitrate of the linked resource in kbps.
  final double? bitrate;

  /// (Nullable) Length of the linked resource in seconds.
  final double? duration;

  /// Expected language of the linked resource.
  final List<String> languages; // BCP 47 tag

  /// Alternate resources for the linked resource.
  final List<Link> alternates;

  /// Resources that are children of the linked resource, in the context of a
  /// given collection role.
  final List<Link> children;

  List<String> get _hrefParts => href.split('#');

  String get hrefPart => _hrefParts[0];

  String? get elementId => (_hrefParts.length > 1) ? _hrefParts[1] : null;

  Link copyWith({
    String? id,
    String? href,
    bool? templated,
    String? type,
    String? title,
    Set<String>? rels,
    Properties? properties,
    int? height,
    int? width,
    double? bitrate,
    double? duration,
    List<String>? languages,
    List<Link>? alternates,
    List<Link>? children,
  }) => Link(
    id: id ?? this.id,
    href: href ?? this.href,
    templated: templated ?? this.templated,
    type: type ?? this.type,
    title: title ?? this.title,
    rels: rels ?? this.rels,
    properties: properties ?? this.properties,
    height: height ?? this.height,
    width: width ?? this.width,
    bitrate: bitrate ?? this.bitrate,
    duration: duration ?? this.duration,
    languages: languages ?? this.languages,
    alternates: alternates ?? this.alternates,
    children: children ?? this.children,
  );

  /// Media type of the linked resource.
  MediaType get mediaType {
    if (type != null && type!.isNotEmpty) {
      return MediaType.parse(type!) ?? MediaType.binary;
    } else {
      return MediaType.binary;
    }
  }

  /// List of URI template parameter keys, if the [Link] is templated.
  List<String> get templateParameters => (templated) ? UriTemplate(href).parameters.toList() : [];

  /// Expands the HREF by replacing URI template variables by the given parameters.
  ///
  /// See RFC 6570 on URI template.
  Link expandTemplate(Map<String, String> parameters) =>
      copyWith(href: UriTemplate(href).expand(parameters), templated: false);

  /// Computes an absolute URL to the link, relative to the given [baseUrl].
  ///
  /// If the link's [href] is already absolute, the [baseUrl] is ignored.
  String? toUrl(String? baseUrl) {
    final href = this.href.removePrefix('/');
    if (href.isBlank) {
      return null;
    }
    return Href(href, baseHref: baseUrl ?? '/').percentEncodedString;
  }

  /// Serializes a [Link] to its RWPM JSON representation.
  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('href', href)
    ..putOpt('type', type)
    ..putOpt('templated', templated)
    ..putOpt('title', title)
    ..putIterableIfNotEmpty('rel', rels)
    ..putJSONableIfNotEmpty('properties', properties)
    ..putOpt('height', height)
    ..putOpt('width', width)
    ..putOpt('bitrate', bitrate)
    ..putOpt('duration', duration)
    ..putIterableIfNotEmpty('language', languages)
    ..putIterableIfNotEmpty('alternate', alternates)
    ..putIterableIfNotEmpty('children', children);

  /// Makes a copy of this [Link] after merging in the given additional other [properties].
  Link copyWithProperties(Properties properties) => copyWith(
    properties: this.properties.copyWith(
      page: properties.page,
      contains: properties.contains,
      orientation: properties.orientation,
      layout: properties.layout,
      overflow: properties.overflow,
      spread: properties.spread,
      encryption: properties.encryption,
      additionalProperties: properties.additionalProperties,
    ),
  );

  @override
  List<Object?> get props => [
    href,
    templated,
    type,
    title,
    rels,
    properties,
    height,
    width,
    bitrate,
    duration,
    languages,
    alternates,
    children,
  ];

  @override
  String toString() =>
      'Link{id: $id, href: $href, type: $type, title: $title, rels: $rels, properties: $properties}';
}

class LinkJsonConverter extends JsonConverter<Link, Map<String, dynamic>?> {
  const LinkJsonConverter();

  @override
  Link fromJson(Map<String, dynamic>? json) => Link.fromJson(json)!;

  @override
  Map<String, dynamic>? toJson(Link? link) => link?.toJson();
}

class LinkListJsonConverter extends JsonConverter<List<Link>, List<dynamic>?> {
  const LinkListJsonConverter();

  @override
  List<Link> fromJson(List<dynamic>? json) => Link.fromJSONArray(json);

  @override
  List<dynamic>? toJson(List<Link> links) => links.map((it) => it.toJson()).toList();
}
