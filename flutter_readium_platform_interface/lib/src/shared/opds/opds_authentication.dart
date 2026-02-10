import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../utils/additional_properties.dart';
import '../../utils/jsonable.dart';
import '../publication/link.dart';

/// OPDS Authentication Object plus NYPL additions.
/// https://drafts.opds.io/schema/authentication.schema.json
///
/// NYPL extensions: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions
@immutable
class OpdsAuthentication extends AdditionalProperties with EquatableMixin implements JSONable {
  factory OpdsAuthentication.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final type = jsonObject.optString('type', remove: true);
    final id = jsonObject.optString('id', remove: true);
    final description = jsonObject.optNullableString('description', remove: true);
    final links =
        jsonObject
            .optJsonArray('links', remove: true)
            ?.map((dynamic linkJson) => Link.fromJson(linkJson as Map<String, dynamic>))
            .nonNulls
            .toList() ??
        [];

    final authentication =
        jsonObject
            .optJsonArray('authentication', remove: true)
            ?.map((dynamic flowJson) => OpdsAuthenticationFlow.fromJson(flowJson as Map<String, dynamic>))
            .nonNulls
            .toList() ??
        [];

    final announcements =
        jsonObject
            .optJsonArray('announcements', remove: true)
            ?.map((dynamic announcementJson) => Announcement.fromJson(announcementJson as Map<String, dynamic>))
            .nonNulls
            .toList() ??
        [];

    var audiences = <Audience>[];

    final audienceJson = jsonObject.opt('audiences', remove: true);
    if (audienceJson is String) {
      audiences = [AudienceExtension.fromString(audienceJson)];
    } else if (audienceJson is List) {
      audiences = audienceJson
          .map((dynamic audienceValue) => AudienceExtension.fromString(audienceValue as String?))
          .nonNulls
          .toList();
    }

    final collectionSize =
        jsonObject.optJsonObject('collection_size', remove: true)?.map((key, value) => MapEntry(key, value as int)) ??
        {};

    final colorScheme = jsonObject.optNullableString('color_scheme', remove: true);

    final featureFlagsJson = jsonObject.optJsonObject('feature_flags', remove: true);
    final featureFlags = featureFlagsJson != null ? FeatureFlags.fromJson(featureFlagsJson) : null;

    final inputDataJson = jsonObject.optJsonObject('inputs', remove: true);
    final inputs = inputDataJson != null ? InputData.fromJson(inputDataJson) : null;

    final labels = jsonObject
        .optJsonObject('labels', remove: true)
        ?.map((key, value) => MapEntry(key, value.toString()));

    final publicKeyJson = jsonObject.optJsonObject('public_key', remove: true);
    final publicKey = publicKeyJson != null ? PublicKeyData.fromJson(publicKeyJson) : null;

    final serviceDescription = jsonObject.optNullableString('service_description', remove: true);
    final webColorSchemeJson = jsonObject.optJsonObject('web_color_scheme', remove: true);
    final webColorScheme = webColorSchemeJson != null ? WebColor.fromJson(webColorSchemeJson) : null;

    return OpdsAuthentication(
      type: type,
      id: id,
      description: description,
      links: links,
      authentication: authentication,
      announcements: announcements,
      audiences: audiences,
      collectionSize: collectionSize,
      colorScheme: colorScheme,
      featureFlags: featureFlags,
      inputs: inputs,
      labels: labels,
      publicKey: publicKey,
      serviceDescription: serviceDescription,
      webColorScheme: webColorScheme,
      additionalProperties: jsonObject,
    );
  }
  const OpdsAuthentication({
    required this.type,
    required this.id,
    this.description,
    this.links = const [],
    this.authentication = const [],
    this.announcements = const [],
    this.audiences = const [],
    this.collectionSize = const {},
    this.colorScheme,
    this.featureFlags,
    this.inputs,
    this.labels,
    this.publicKey,
    this.serviceDescription,
    this.webColorScheme,
    super.additionalProperties = const {},
  });

  /// Title of the Catalog being accessed
  final String type;

  /// Unique identifier for the Catalog provider and canonical location for the Authentication Document.
  final String id;

  /// A description of the service being displayed to the user.
  final String? description;

  final List<Link> links;

  /// A list of site-wide announcements.
  final List<Announcement> announcements;

  /// A list of supported Authentication Flows.
  final List<OpdsAuthenticationFlow> authentication;

  /// A list of intended audiences service.
  final List<Audience> audiences;

  /// Collection size.
  /// see: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#collection-size
  final Map<String, int> collectionSize;

  /// Color scheme.
  /// see: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#color-scheme
  final String? colorScheme;

  final FeatureFlags? featureFlags;

  /// Input fields for login and password.
  final InputData? inputs;

  /// Labels for input fields.
  final Map<String, String>? labels;

  /// An OPDS server may use the service_description extension to describe itself.
  /// This is distinct from the standard description field, which is to be used to
  /// describe the text prompt displayed to the authenticating user.
  ///
  /// See https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#server-description.
  final String? serviceDescription;

  /// See: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#public-key
  final PublicKeyData? publicKey;

  /// Web color scheme.
  /// See: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#web-color-scheme
  final WebColor? webColorScheme;

  @override
  Map<String, dynamic> toJson() => Map.from(additionalProperties)
    ..put('type', type)
    ..put('id', id)
    ..putOpt('description', description)
    ..putIterableIfNotEmpty('links', links)
    ..putIterableIfNotEmpty('authentication', authentication)
    ..putIterableIfNotEmpty('announcements', announcements)
    ..putIterableIfNotEmpty('audiences', audiences.map((a) => a.name))
    ..putMapIfNotEmpty('collection_size', collectionSize)
    ..putOpt('color_scheme', colorScheme)
    ..putJSONableIfNotEmpty('feature_flags', featureFlags)
    ..putJSONableIfNotEmpty('inputs', inputs)
    ..putOpt('labels', labels)
    ..putJSONableIfNotEmpty('public_key', publicKey)
    ..putOpt('service_description', serviceDescription)
    ..putJSONableIfNotEmpty('web_color_scheme', webColorScheme);

  OpdsAuthentication copyWith({
    String? type,
    String? id,
    String? description,
    List<Link>? links,
    List<Announcement>? announcements,
    List<Audience>? audiences,
    Map<String, int>? collectionSize,
    String? colorScheme,
    FeatureFlags? featureFlags,
    InputData? inputs,
    Map<String, String>? labels,
    PublicKeyData? publicKey,
    String? serviceDescription,
    WebColor? webColorScheme,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return OpdsAuthentication(
      type: type ?? this.type,
      id: id ?? this.id,
      links: links ?? this.links,
      description: description ?? this.description,
      announcements: announcements ?? this.announcements,
      audiences: audiences ?? this.audiences,
      collectionSize: collectionSize ?? this.collectionSize,
      colorScheme: colorScheme ?? this.colorScheme,
      featureFlags: featureFlags ?? this.featureFlags,
      inputs: inputs ?? this.inputs,
      labels: labels ?? this.labels,
      publicKey: publicKey ?? this.publicKey,
      serviceDescription: serviceDescription ?? this.serviceDescription,
      webColorScheme: webColorScheme ?? this.webColorScheme,
      additionalProperties: mergeProperties,
    );
  }

  @override
  List<Object?> get props => [
    type,
    id,
    description,
    links,
    announcements,
    authentication,
    audiences,
    collectionSize,
    colorScheme,
    featureFlags,
    inputs,
    labels,
    publicKey,
    serviceDescription,
    webColorScheme,
    additionalProperties,
  ];
}

@immutable
class OpdsAuthenticationFlow with EquatableMixin implements JSONable {
  factory OpdsAuthenticationFlow.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final type = jsonObject.optString('type', remove: true);
    final links =
        jsonObject
            .optJsonArray('links', remove: true)
            ?.map((dynamic linkJson) => Link.fromJson(linkJson as Map<String, dynamic>))
            .nonNulls
            .toList() ??
        [];

    return OpdsAuthenticationFlow(type: type, links: links);
  }

  const OpdsAuthenticationFlow({required this.type, this.links = const []});
  final String type;
  final List<Link> links;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('type', type)
    ..putIterableIfNotEmpty('links', links);

  OpdsAuthenticationFlow copyWith({String? type, List<Link>? links}) =>
      OpdsAuthenticationFlow(type: type ?? this.type, links: links ?? this.links);

  @override
  List<Object?> get props => [type, links];
}

@immutable
class OpdsAuthenticationLabels with EquatableMixin implements JSONable {
  factory OpdsAuthenticationLabels.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final login = jsonObject.optNullableString('login', remove: true);
    final password = jsonObject.optNullableString('password', remove: true);

    return OpdsAuthenticationLabels(login: login, password: password);
  }
  const OpdsAuthenticationLabels({this.login, this.password});

  final String? login;
  final String? password;

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('login', login)
    ..putOpt('password', password);

  OpdsAuthenticationLabels copyWith({String? login, String? password}) =>
      OpdsAuthenticationLabels(login: login ?? this.login, password: password ?? this.password);

  @override
  List<Object?> get props => [login, password];
}

/// Announcement object
/// See: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#sitewide-announcements
@immutable
class Announcement extends AdditionalProperties with EquatableMixin implements JSONable {
  factory Announcement.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final id = jsonObject.optString('id', remove: true);
    final content = jsonObject.optString('content', remove: true);

    return Announcement(id: id, content: content, additionalProperties: jsonObject);
  }
  const Announcement({required this.id, required this.content, super.additionalProperties});

  final String id;
  final String content;

  @override
  Map<String, dynamic> toJson() => Map.from(additionalProperties)
    ..put('id', id)
    ..put('content', content);

  Announcement copyWith({String? id, String? content, Map<String, dynamic>? additionalProperties}) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Announcement(id: id ?? this.id, content: content ?? this.content, additionalProperties: mergeProperties);
  }

  @override
  List<Object?> get props => [id, content, additionalProperties];
}

/// Audience enum representing the intended audience for a resource.
enum Audience {
  /// No audience specified.
  none,

  /// Open to the general public. If this is specified, any other values are redundant.
  public,

  /// Open to pre-university students.
  educationalPrimary,

  /// Open to university-level students.
  educationalSecondary,

  /// Open to academics and researchers.
  research,

  /// Open only to those who have a print disability.
  printDisability,

  /// Open to people who meet some other qualification.
  other,
}

extension AudienceExtension on Audience {
  static final _audienceMap = {
    'public': Audience.public,
    'educational-primary': Audience.educationalPrimary,
    'educational-secondary': Audience.educationalSecondary,
    'research': Audience.research,
    'print-disability': Audience.printDisability,
    'other': Audience.other,
    'none': Audience.none,
  };

  /// Maps enum to its string value.
  String get name => _audienceMap.entries
      .firstWhere((entry) => entry.value == this, orElse: () => const MapEntry('none', Audience.none))
      .key;

  /// Parses a string to an Audience enum.
  static Audience fromString(String? value) =>
      _audienceMap[value] ?? _audienceMap[value?.toLowerCase()] ?? Audience.none;
}

/// FeatureFlags class
/// See: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#feature-flags
@immutable
class FeatureFlags with EquatableMixin implements JSONable {
  factory FeatureFlags.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final enabled = (jsonObject.optJsonArray('enabled', remove: true))?.whereType<String>().toList() ?? [];
    final disabled = (jsonObject.optJsonArray('disabled', remove: true))?.whereType<String>().toList() ?? [];

    return FeatureFlags(enabled: enabled, disabled: disabled);
  }

  const FeatureFlags({this.enabled = const [], this.disabled = const []});

  /// List of enabled features.
  final List<String> enabled;

  /// List of disabled features.
  final List<String> disabled;

  @override
  Map<String, dynamic> toJson() => {}
    ..putIterableIfNotEmpty('enabled', enabled)
    ..putIterableIfNotEmpty('disabled', disabled);

  FeatureFlags copyWith({List<String>? enabled, List<String>? disabled}) =>
      FeatureFlags(enabled: enabled ?? this.enabled, disabled: disabled ?? this.disabled);

  @override
  List<Object?> get props => [enabled, disabled];
}

@immutable
class InputField with EquatableMixin implements JSONable {
  factory InputField.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final keyboard = KeyboardTypeExtension.fromString(jsonObject.optNullableString('keyboard', remove: true));
    final maximumLength = jsonObject.optNullableInt('maximum_length', remove: true);

    return InputField(keyboard: keyboard, maximumLength: maximumLength);
  }

  const InputField({this.keyboard, this.maximumLength});

  final KeyboardType? keyboard;
  final int? maximumLength;

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('keyboard', keyboard?.name)
    ..putOpt('maximum_length', maximumLength);

  InputField copyWith({KeyboardType? keyboard, int? maximumLength}) =>
      InputField(keyboard: keyboard ?? this.keyboard, maximumLength: maximumLength ?? this.maximumLength);

  @override
  List<Object?> get props => [keyboard, maximumLength];
}

enum KeyboardType { defaultType, emailAddress, numPad, noInput }

extension KeyboardTypeExtension on KeyboardType? {
  static const _keyboardTypeMap = {
    'Default': KeyboardType.defaultType,
    'Email address': KeyboardType.emailAddress,
    'Number pad': KeyboardType.numPad,
    'No input': KeyboardType.noInput,
  };

  String? get name => _keyboardTypeMap.entries.firstWhere((entry) => entry.value == this).key;

  static KeyboardType? fromString(String? value) => _keyboardTypeMap[value];
}

@immutable
class LoginInputField extends InputField with EquatableMixin {
  factory LoginInputField.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final barcodeFormat = jsonObject.optNullableString('barcode_format', remove: true);

    // Parse base InputField properties
    final keyboard = KeyboardTypeExtension.fromString(jsonObject.optNullableString('keyboard', remove: true));
    final maximumLength = jsonObject.optNullableInt('maximum_length', remove: true);

    return LoginInputField(barcodeFormat: barcodeFormat, keyboard: keyboard, maximumLength: maximumLength);
  }

  const LoginInputField({this.barcodeFormat, super.keyboard, super.maximumLength});

  /// Barcode format.
  final String? barcodeFormat;

  @override
  Map<String, dynamic> toJson() => Map.from(super.toJson())..putOpt('barcode_format', barcodeFormat);

  @override
  LoginInputField copyWith({String? barcodeFormat, KeyboardType? keyboard, int? maximumLength}) => LoginInputField(
    barcodeFormat: barcodeFormat ?? this.barcodeFormat,
    keyboard: keyboard ?? this.keyboard,
    maximumLength: maximumLength ?? this.maximumLength,
  );

  @override
  List<Object?> get props => [barcodeFormat, keyboard, maximumLength];
}

@immutable
class InputData with EquatableMixin implements JSONable {
  factory InputData.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final login = jsonObject['login'] != null
        ? LoginInputField.fromJson(jsonObject['login'] as Map<String, dynamic>)
        : const LoginInputField();

    final password = jsonObject['password'] != null
        ? InputField.fromJson(jsonObject['password'] as Map<String, dynamic>)
        : const InputField();

    return InputData(login: login, password: password);
  }

  const InputData({this.login = const LoginInputField(), this.password = const InputField()});

  final LoginInputField login;
  final InputField password;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('login', login)
    ..put('password', password);

  InputData copyWith({LoginInputField? login, InputField? password}) =>
      InputData(login: login ?? this.login, password: password ?? this.password);

  @override
  List<Object?> get props => [login, password];
}

/// If your OPDS server needs to receive cryptographically signed messages (e.g. to set up shared secrets with other servers),
/// you can publish your public key in the authentication document.
@immutable
class PublicKeyData with EquatableMixin implements JSONable {
  factory PublicKeyData.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);
    final type = jsonObject.optString('type', remove: true);
    final value = jsonObject.optString('value', remove: true);
    return PublicKeyData(type: type, value: value);
  }

  const PublicKeyData({required this.type, required this.value});

  /// Type of the key.
  final String type;

  /// Value of the key.
  final String value;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('type', type)
    ..put('value', value);

  PublicKeyData copyWith({String? type, String? value}) =>
      PublicKeyData(type: type ?? this.type, value: value ?? this.value);

  @override
  List<Object?> get props => [type, value];
}

/// Web color scheme.
/// See: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#web-color-scheme
@immutable
class WebColor with EquatableMixin implements JSONable {
  factory WebColor.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);
    final primary = jsonObject.optNullableString('primary', remove: true) ?? '';
    final secondary = jsonObject.optNullableString('secondary', remove: true) ?? '';
    return WebColor(primary: primary, secondary: secondary);
  }

  const WebColor({this.primary = '', this.secondary = ''});

  /// Primary color in HEX format.
  final String primary;

  /// Secondary color in HEX format.
  final String secondary;

  /// Returns true if primary is not empty or whitespace.
  bool get shouldSerializePrimary => primary.trim().isNotEmpty;

  /// Returns true if secondary is not empty or whitespace.
  bool get shouldSerializeSecondary => secondary.trim().isNotEmpty;

  /// Returns true if either primary or secondary should be serialized.
  bool get shouldSerializeThis => shouldSerializePrimary || shouldSerializeSecondary;

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('primary', primary)
    ..putOpt('secondary', secondary);

  WebColor copyWith({String? primary, String? secondary}) =>
      WebColor(primary: primary ?? this.primary, secondary: secondary ?? this.secondary);

  @override
  List<Object?> get props => [primary, secondary];
}
