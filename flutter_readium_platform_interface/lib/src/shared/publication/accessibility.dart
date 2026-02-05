import 'package:collection/collection.dart';
import 'package:dartx/dartx.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../utils/jsonable.dart';

/// Accessibility Object
/// https://readium.org/webpub-manifest/schema/a11y.schema.json
@immutable
class Accessibility with EquatableMixin implements JSONable {
  factory Accessibility.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final conformsToJson = jsonObject.opt('conformsTo', remove: true);
    final conformsTo = <String>[];
    if (conformsToJson is String) {
      conformsTo.add(conformsToJson);
    } else if (conformsToJson is List<dynamic>) {
      conformsTo.addAll(conformsToJson.cast<String>());
    }

    final exemption = AccessibilityExemption.fromString(jsonObject.optNullableString('exemption', remove: true));

    final accessMode = jsonObject
        .optJsonArray('accessMode', remove: true)
        ?.map((e) => AccessibilityAccessMode.fromString(e))
        .nonNulls
        .toList();

    final accessModeSufficient = jsonObject
        .opt('accessModeSufficient', remove: true)
        ?.map((e) => AccessibilityAccessModeSufficient.fromJson(e))
        .nonNulls
        .toList();

    final feature = jsonObject
        .optJsonArray('feature', remove: true)
        ?.map((e) => AccessibilityFeature.fromString(e))
        .nonNulls
        .toList();

    final hazard = jsonObject
        .optJsonArray('hazard', remove: true)
        ?.map((e) => AccessibilityHazard.fromString(e))
        .nonNulls
        .toList();

    final certificationJson = jsonObject.optNullableMap('certification', remove: true);

    final certification = certificationJson != null ? AccessibilityCertification.fromJson(certificationJson) : null;

    final summary = jsonObject.optNullableString('summary', remove: true);

    return Accessibility(
      conformsTo: conformsTo.isNotEmpty ? conformsTo : null,
      exemption: exemption,
      accessMode: accessMode,
      accessModeSufficient: accessModeSufficient,
      feature: feature,
      hazard: hazard,
      certification: certification,
      summary: summary,
    );
  }
  const Accessibility({
    this.conformsTo,
    this.exemption,
    this.accessMode,
    this.accessModeSufficient,
    this.feature,
    this.hazard,
    this.certification,
    this.summary,
  });

  /// URI(s) the publication conforms to.
  final List<String>? conformsTo;

  /// EAA exemption type.
  final AccessibilityExemption? exemption;

  /// List of access modes.
  final List<AccessibilityAccessMode>? accessMode;

  /// List of sufficient access modes.
  /// Each item can be a single mode or a list of modes.
  final List<AccessibilityAccessModeSufficient>? accessModeSufficient;

  /// List of accessibility features.
  final List<AccessibilityFeature>? feature;

  /// List of accessibility hazards.
  final List<AccessibilityHazard>? hazard;

  /// Certification information.
  final AccessibilityCertification? certification;

  /// Human-readable summary.
  final String? summary;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('conformsTo', conformsTo)
    ..putOpt('exemption', exemption?.name)
    ..putIterableIfNotEmpty('accessMode', accessMode?.map((e) => e.name))
    ..putIterableIfNotEmpty('accessModeSufficient', accessModeSufficient?.mapNotNull((e) => e.toJson()))
    ..putIterableIfNotEmpty('feature', feature?.map((e) => e.name).toList())
    ..putIterableIfNotEmpty('hazard', hazard?.map((e) => e.name).toList())
    ..putJSONableIfNotEmpty('certification', certification)
    ..putOpt('summary', summary);

  @override
  List<Object?> get props => [
    conformsTo,
    exemption,
    accessMode,
    accessModeSufficient,
    feature,
    hazard,
    certification,
    summary,
  ];
}

enum AccessibilityExemption {
  eaaDisproportionateBurden('eaa-disproportionate-burden'),
  eaaFundamentalAlteration('eaa-fundamental-alteration'),
  eaaMicroenterprise('eaa-microenterprise');

  const AccessibilityExemption(this.name);
  final String name;

  static AccessibilityExemption? fromString(String? name) {
    if (name == null || name.isEmpty) {
      return null;
    }

    return AccessibilityExemption.values.firstWhereOrNull((e) => e.name.toLowerCase() == name.toLowerCase());
  }
}

enum AccessibilityAccessMode {
  auditory('auditory'),
  chartOnVisual('chartOnVisual'),
  chemOnVisual('chemOnVisual'),
  colorDependent('colorDependent'),
  diagramOnVisual('diagramOnVisual'),
  mathOnVisual('mathOnVisual'),
  musicOnVisual('musicOnVisual'),
  tactile('tactile'),
  textOnVisual('textOnVisual'),
  textual('textual'),
  visual('visual');

  const AccessibilityAccessMode(this.name);

  final String name;

  static AccessibilityAccessMode? fromString(String? name) {
    if (name == null || name.isEmpty) {
      return null;
    }

    return AccessibilityAccessMode.values.firstWhereOrNull((e) => e.name.toLowerCase() == name.toLowerCase());
  }
}

/// Represents a sufficient access mode, which can be a single mode or a list of modes.
@immutable
class AccessibilityAccessModeSufficient with EquatableMixin {
  factory AccessibilityAccessModeSufficient.fromJson(dynamic json) {
    if (json is String) {
      final mode = AccessibilityAccessModeSimple.fromString(json);
      if (mode == null) {
        throw ArgumentError('Invalid accessModeSufficient value: $json');
      }

      return AccessibilityAccessModeSufficient([mode]);
    } else if (json is List) {
      return AccessibilityAccessModeSufficient(
        json
            .map(
              (e) =>
                  AccessibilityAccessModeSimple.fromString(e) ??
                  (throw ArgumentError('Invalid accessModeSufficient value: $e')),
            )
            .toList(),
      );
    } else {
      throw ArgumentError('Invalid accessModeSufficient type');
    }
  }

  const AccessibilityAccessModeSufficient(this.modes);

  final List<AccessibilityAccessModeSimple> modes;

  dynamic toJson() {
    if (modes.length == 1) {
      return modes.first.name;
    } else {
      return modes.map((e) => e.name).toList();
    }
  }

  @override
  List<Object?> get props => [modes];
}

enum AccessibilityAccessModeSimple {
  auditory('auditory'),
  tactile('tactile'),
  textual('textual'),
  visual('visual');

  const AccessibilityAccessModeSimple(this.name);
  final String name;

  static AccessibilityAccessModeSimple? fromString(String? name) =>
      AccessibilityAccessModeSimple.values.firstWhereOrNull((mode) => mode.name.toLowerCase() == name?.toLowerCase());
}

enum AccessibilityFeature {
  annotations('annotations'),
  aria('ARIA'),
  bookmarks('bookmarks'),
  indexed('indexed'),
  pageBreakMarkers('pageBreakMarkers'),
  printPageNumbers('printPageNumbers'),
  pageNavigation('pageNavigation'),
  readingOrder('readingOrder'),
  structuralNavigation('structuralNavigation'),
  tableOfContents('tableOfContents'),
  taggedPDF('taggedPDF'),
  alternativeText('alternativeText'),
  audioDescription('audioDescription'),
  closeCaptions('closeCaptions'),
  captions('captions'),
  describedMath('describedMath'),
  longDescription('longDescription'),
  openCaptions('openCaptions'),
  signLanguage('signLanguage'),
  transcript('transcript'),
  displayTransformability('displayTransformability'),
  synchronizedAudioText('synchronizedAudioText'),
  timingControl('timingControl'),
  unlocked('unlocked'),
  chemML('ChemML'),
  latex('latex'),
  latexChemistry('latex-chemistry'),
  mathML('MathML'),
  mathMLChemistry('MathML-chemistry'),
  ttsMarkup('ttsMarkup'),
  highContrastAudio('highContrastAudio'),
  highContrastDisplay('highContrastDisplay'),
  largePrint('largePrint'),
  braille('braille'),
  tactileGraphic('tactileGraphic'),
  tactileObject('tactileObject'),
  fullRubyAnnotations('fullRubyAnnotations'),
  horizontalWriting('horizontalWriting'),
  rubyAnnotations('rubyAnnotations'),
  verticalWriting('verticalWriting'),
  withAdditionalWordSegmentation('withAdditionalWordSegmentation'),
  withoutAdditionalWordSegmentation('withoutAdditionalWordSegmentation'),
  none('none'),
  unknown('unknown');

  const AccessibilityFeature(this.name);
  final String name;

  static AccessibilityFeature? fromString(String? name) {
    if (name == null || name.isEmpty) {
      return null;
    }

    return AccessibilityFeature.values.firstWhereOrNull(
          (feature) => feature.name.toLowerCase() == name.toLowerCase(),
        ) ??
        unknown;
  }
}

enum AccessibilityHazard {
  flashing('flashing'),
  motionSimulation('motionSimulation'),
  sound('sound'),
  none('none'),
  noFlashingHazard('noFlashingHazard'),
  noMotionSimulationHazard('noMotionSimulationHazard'),
  noSoundHazard('noSoundHazard'),
  unknown('unknown'),
  unknownFlashingHazard('unknownFlashingHazard'),
  unknownMotionSimulationHazard('unknownMotionSimulationHazard'),
  unknownSoundHazard('unknownSoundHazard');

  const AccessibilityHazard(this.name);
  final String name;

  static AccessibilityHazard? fromString(String? name) {
    if (name == null || name.isEmpty) {
      return null;
    }

    return AccessibilityHazard.values.firstWhereOrNull((hazard) => hazard.name.toLowerCase() == name.toLowerCase()) ??
        AccessibilityHazard.unknown;
  }
}

@immutable
class AccessibilityCertification with EquatableMixin implements JSONable {
  factory AccessibilityCertification.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    return AccessibilityCertification(
      certifiedBy: jsonObject.optNullableString('certifiedBy', remove: true),
      credential: jsonObject.optNullableString('credential', remove: true),
      report: jsonObject.optNullableString('report', remove: true),
    );
  }

  const AccessibilityCertification({this.certifiedBy, this.credential, this.report});

  final String? certifiedBy;
  final String? credential;
  final String? report;

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('certifiedBy', certifiedBy)
    ..putOpt('credential', credential)
    ..putOpt('report', report);

  @override
  List<Object?> get props => [certifiedBy, credential, report];
}
