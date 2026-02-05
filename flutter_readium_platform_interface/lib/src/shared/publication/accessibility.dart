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

    final exemption = AccessibilityExemptionExtension.fromString(
      jsonObject.optNullableString('exemption', remove: true),
    );

    final accessMode = jsonObject
        .optJsonArray('accessMode', remove: true)
        ?.map((e) => AccessibilityAccessModeExtension.fromString(e))
        .nonNulls
        .toList();

    final accessModeSufficient = jsonObject
        .opt('accessModeSufficient', remove: true)
        ?.map((e) => AccessibilityAccessModeSufficient.fromJson(e))
        .nonNulls
        .toList();

    final feature = jsonObject
        .optJsonArray('feature', remove: true)
        ?.map((e) => AccessibilityFeatureExtension.fromString(e))
        .nonNulls
        .toList();

    final hazard = jsonObject
        .optJsonArray('hazard', remove: true)
        ?.map((e) => AccessibilityHazardExtension.fromString(e))
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

enum AccessibilityExemption { eaaDisproportionateBurden, eaaFundamentalAlteration, eaaMicroenterprise }

extension AccessibilityExemptionExtension on AccessibilityExemption {
  static const _exemptionMap = {
    'eaa-disproportionate-burden': AccessibilityExemption.eaaDisproportionateBurden,
    'eaa-fundamental-alteration': AccessibilityExemption.eaaFundamentalAlteration,
    'eaa-microenterprise': AccessibilityExemption.eaaMicroenterprise,
  };

  String get name => _exemptionMap.entries.firstWhere((entry) => entry.value == this).key;

  static AccessibilityExemption? fromString(String? value) =>
      _exemptionMap[value] ?? _exemptionMap[value?.toLowerCase()];
}

enum AccessibilityAccessMode {
  auditory,
  chartOnVisual,
  chemOnVisual,
  colorDependent,
  diagramOnVisual,
  mathOnVisual,
  musicOnVisual,
  tactile,
  textOnVisual,
  textual,
  visual,
}

extension AccessibilityAccessModeExtension on AccessibilityAccessMode {
  static final _accessModeMap = {
    'auditory': AccessibilityAccessMode.auditory,
    'chartOnVisual': AccessibilityAccessMode.chartOnVisual,
    'chemOnVisual': AccessibilityAccessMode.chemOnVisual,
    'colorDependent': AccessibilityAccessMode.colorDependent,
    'diagramOnVisual': AccessibilityAccessMode.diagramOnVisual,
    'mathOnVisual': AccessibilityAccessMode.mathOnVisual,
    'musicOnVisual': AccessibilityAccessMode.musicOnVisual,
    'tactile': AccessibilityAccessMode.tactile,
    'textOnVisual': AccessibilityAccessMode.textOnVisual,
    'textual': AccessibilityAccessMode.textual,
    'visual': AccessibilityAccessMode.visual,
  };

  String get value => _accessModeMap.entries.firstWhere((entry) => entry.value == this).key;

  static AccessibilityAccessMode? fromString(String? name) =>
      _accessModeMap[name] ?? _accessModeMap[name?.toLowerCase()];
}

/// Represents a sufficient access mode, which can be a single mode or a list of modes.
@immutable
class AccessibilityAccessModeSufficient with EquatableMixin {
  factory AccessibilityAccessModeSufficient.fromJson(dynamic json) {
    if (json is String) {
      final mode = AccessibilityAccessModeSimpleExtension.fromString(json);
      if (mode == null) {
        throw ArgumentError('Invalid accessModeSufficient value: $json');
      }

      return AccessibilityAccessModeSufficient([mode]);
    } else if (json is List) {
      return AccessibilityAccessModeSufficient(
        json
            .map(
              (e) =>
                  AccessibilityAccessModeSimpleExtension.fromString(e) ??
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

enum AccessibilityAccessModeSimple { auditory, tactile, textual, visual }

extension AccessibilityAccessModeSimpleExtension on AccessibilityAccessModeSimple {
  static final _modeMap = {
    'auditory': AccessibilityAccessModeSimple.auditory,
    'tactile': AccessibilityAccessModeSimple.tactile,
    'textual': AccessibilityAccessModeSimple.textual,
    'visual': AccessibilityAccessModeSimple.visual,
  };

  String get value => _modeMap.entries.firstWhere((entry) => entry.value == this).key;

  static AccessibilityAccessModeSimple? fromString(String name) => _modeMap[name] ?? _modeMap[name.toLowerCase()];
}

enum AccessibilityFeature {
  annotations,
  ARIA,
  bookmarks,
  indexed,
  pageBreakMarkers,
  printPageNumbers,
  pageNavigation,
  readingOrder,
  structuralNavigation,
  tableOfContents,
  taggedPDF,
  alternativeText,
  audioDescription,
  closeCaptions,
  captions,
  describedMath,
  longDescription,
  openCaptions,
  signLanguage,
  transcript,
  displayTransformability,
  synchronizedAudioText,
  timingControl,
  unlocked,
  ChemML,
  latex,
  latexChemistry,
  MathML,
  MathMLChemistry,
  ttsMarkup,
  highContrastAudio,
  highContrastDisplay,
  largePrint,
  braille,
  tactileGraphic,
  tactileObject,
  fullRubyAnnotations,
  horizontalWriting,
  rubyAnnotations,
  verticalWriting,
  withAdditionalWordSegmentation,
  withoutAdditionalWordSegmentation,
  none,
  unknown,
}

extension AccessibilityFeatureExtension on AccessibilityFeature {
  static const _featureMap = {
    'annotations': AccessibilityFeature.annotations,
    'ARIA': AccessibilityFeature.ARIA,
    'bookmarks': AccessibilityFeature.bookmarks,
    'index': AccessibilityFeature.indexed,
    'pageBreakMarkers': AccessibilityFeature.pageBreakMarkers,
    'printPageNumbers': AccessibilityFeature.printPageNumbers,
    'pageNavigation': AccessibilityFeature.pageNavigation,
    'readingOrder': AccessibilityFeature.readingOrder,
    'structuralNavigation': AccessibilityFeature.structuralNavigation,
    'tableOfContents': AccessibilityFeature.tableOfContents,
    'taggedPDF': AccessibilityFeature.taggedPDF,
    'alternativeText': AccessibilityFeature.alternativeText,
    'audioDescription': AccessibilityFeature.audioDescription,
    'closeCaptions': AccessibilityFeature.closeCaptions,
    'captions': AccessibilityFeature.captions,
    'describedMath': AccessibilityFeature.describedMath,
    'longDescription': AccessibilityFeature.longDescription,
    'openCaptions': AccessibilityFeature.openCaptions,
    'signLanguage': AccessibilityFeature.signLanguage,
    'transcript': AccessibilityFeature.transcript,
    'displayTransformability': AccessibilityFeature.displayTransformability,
    'synchronizedAudioText': AccessibilityFeature.synchronizedAudioText,
    'timingControl': AccessibilityFeature.timingControl,
    'unlocked': AccessibilityFeature.unlocked,
    'ChemML': AccessibilityFeature.ChemML,
    'latex': AccessibilityFeature.latex,
    'latex-chemistry': AccessibilityFeature.latexChemistry,
    'MathML': AccessibilityFeature.MathML,
    'MathML-chemistry': AccessibilityFeature.MathMLChemistry,
    'ttsMarkup': AccessibilityFeature.ttsMarkup,
    'highContrastAudio': AccessibilityFeature.highContrastAudio,
    'highContrastDisplay': AccessibilityFeature.highContrastDisplay,
    'largePrint': AccessibilityFeature.largePrint,
    'braille': AccessibilityFeature.braille,
    'tactileGraphic': AccessibilityFeature.tactileGraphic,
    'tactileObject': AccessibilityFeature.tactileObject,
    'fullRubyAnnotations': AccessibilityFeature.fullRubyAnnotations,
    'horizontalWriting': AccessibilityFeature.horizontalWriting,
    'rubyAnnotations': AccessibilityFeature.rubyAnnotations,
    'verticalWriting': AccessibilityFeature.verticalWriting,
    'withAdditionalWordSegmentation': AccessibilityFeature.withAdditionalWordSegmentation,
    'withoutAdditionalWordSegmentation': AccessibilityFeature.withoutAdditionalWordSegmentation,
    'none': AccessibilityFeature.none,
    'unknown': AccessibilityFeature.unknown,
  };

  String get value => _featureMap.entries.firstWhere((entry) => entry.value == this).key;

  static AccessibilityFeature? fromString(String? name) => _featureMap[name] ?? _featureMap[name?.toLowerCase()];
}

enum AccessibilityHazard {
  flashing,
  motionSimulation,
  sound,
  none,
  noFlashingHazard,
  noMotionSimulationHazard,
  noSoundHazard,
  unknown,
  unknownFlashingHazard,
  unknownMotionSimulationHazard,
  unknownSoundHazard,
}

extension AccessibilityHazardExtension on AccessibilityHazard {
  static const _hazardMap = {
    'flashing': AccessibilityHazard.flashing,
    'motionSimulation': AccessibilityHazard.motionSimulation,
    'sound': AccessibilityHazard.sound,
    'none': AccessibilityHazard.none,
    'noFlashingHazard': AccessibilityHazard.noFlashingHazard,
    'noMotionSimulationHazard': AccessibilityHazard.noMotionSimulationHazard,
    'noSoundHazard': AccessibilityHazard.noSoundHazard,
    'unknown': AccessibilityHazard.unknown,
    'unknownFlashingHazard': AccessibilityHazard.unknownFlashingHazard,
    'unknownMotionSimulationHazard': AccessibilityHazard.unknownMotionSimulationHazard,
    'unknownSoundHazard': AccessibilityHazard.unknownSoundHazard,
  };

  String get name => _hazardMap.entries.firstWhere((entry) => entry.value == this).key;

  static AccessibilityHazard? fromString(String name) =>
      _hazardMap[name] ?? _hazardMap[name.toLowerCase()] ?? AccessibilityHazard.unknown;
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
