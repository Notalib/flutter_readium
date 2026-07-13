import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../utils/index.dart';
import '../publication/link.dart';
import 'guided_navigation_object.dart';

/// A Readium Guided Navigation Document, describing a structured sequence of
/// media-aligned navigation steps for a publication.
///
/// See https://readium.org/guided-navigation/schema/document.schema.json
@immutable
class GuidedNavigationDocument with Equatable implements JSONable {
  const GuidedNavigationDocument({required this.guided, this.links = const []});

  /// Optional cross-references to related resources, using the Readium Web
  /// Publication Manifest link schema.
  final List<Link> links;

  /// The ordered list of guided navigation objects. Must contain at least one.
  final List<GuidedNavigationObject> guided;

  @override
  List<Object> get props => [links, guided];

  @override
  Map<String, dynamic> toJson() => {}
    ..putIterableIfNotEmpty('links', links)
    ..putIterableIfNotEmpty('guided', guided);

  static GuidedNavigationDocument? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final jsonObject = Map<String, dynamic>.of(json);
    final links = Link.fromJsonArray(
      jsonObject.optJsonArray('links', remove: true),
    );
    final guided = GuidedNavigationObject.fromJsonArray(
      jsonObject.optJsonArray('guided', remove: true),
    );

    if (guided.isEmpty) {
      ReadiumLog.d(
        'GuidedNavigationDocument: [guided] is required and must not be empty',
      );
      return null;
    }

    return GuidedNavigationDocument(links: links, guided: guided);
  }
}
