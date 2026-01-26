// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// Originally from https://github.com/Mantano/iridium/blob/main/components/commons/lib/utils/href.dart

import 'dart:convert';

import 'package:dartx/dartx.dart';
import 'package:collection/collection.dart';
import 'package:fimber/fimber.dart';
import '../extensions/strings.dart';

/// Represents an HREF, optionally relative to another one.
///
/// This is used to normalize the string representation.
class Href {
  Href(this.href, {String baseHref = '/'}) : baseHref = (baseHref.isEmpty) ? '/' : baseHref;

  final String href;
  final String baseHref;

  /// Returns the normalized string representation for this HREF.
  String get string {
    if (href.isBlank) {
      return baseHref;
    }

    String resolved;
    try {
      final absoluteUri = Uri.parse(baseHref).resolve(href);
      final absoluteString = absoluteUri.toString(); // This is percent-decoded
      final addSlash = !absoluteUri.hasScheme && !absoluteString.startsWith('/');
      resolved = ((addSlash) ? '/' : '') + absoluteString;
    } on Exception {
      if (href.startsWith('http://') || href.startsWith('https://')) {
        resolved = href;
      } else {
        resolved = baseHref.removeSuffix('/') + href.addPrefix('/');
      }
    }

    return Uri.decodeFull(resolved);
  }

  /// Returns the normalized string representation for this HREF, encoded for URL uses.
  ///
  /// Taken from https://stackoverflow.com/a/49796882/1474476
  String get percentEncodedString {
    var string = this.string;
    if (string.startsWith('/')) {
      string = string.addPrefix('file://');
    }

    try {
      final url = Uri.parse(string);
      final uri = url.replace(host: AsciiCodec().decode(url.host.toUtf8()));
      return String.fromCharCodes(AsciiCodec().encode(uri.toString())).removePrefix('file://');
    } on Exception catch (e) {
      Fimber.e('ERROR in percentEncodedString', ex: e);
      return this.string;
    }
  }

  /// Returns the query parameters present in this HREF, in the order they appear.
  List<QueryParameter> get queryParameters => Uri.parse(
    percentEncodedString,
  ).queryParameters.entries.map((it) => QueryParameter(it.key, value: it.value)).toList();
}

class QueryParameter {
  QueryParameter(this.name, {this.value});
  final String name;
  final String? value;

  @override
  String toString() => 'QueryParameter{name: $name, value: $value}';
}

extension QueryParameterExtension on List<QueryParameter> {
  String? firstNamedOrNull(String name) => firstWhereOrNull((it) => it.name == name)?.value;

  List<String> allNamed(String name) => where((it) => it.name == name).mapNotNull((it) => it.value).toList();
}
