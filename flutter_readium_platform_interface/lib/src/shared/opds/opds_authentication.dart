import 'package:collection/collection.dart';
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
class OpdsAuthentication extends AdditionalProperties with Equatable implements JSONable {
  factory OpdsAuthentication.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final type = jsonObject.optString('type', remove: true);
    final id = jsonObject.optString('id', remove: true);
    final description = jsonObject.optNullableString(
      'description',
      remove: true,
    );
    final links =
        jsonObject
            .optJsonArray('links', remove: true)
            ?.map(
              (dynamic linkJson) => Link.fromJson(linkJson as Map<String, dynamic>),
            )
            .nonNulls
            .toList() ??
        [];

    final authentication =
        jsonObject
            .optJsonArray('authentication', remove: true)
            ?.map(
              (dynamic flowJson) => OpdsAuthenticationFlow.fromJson(
                flowJson as Map<String, dynamic>,
              ),
            )
            .nonNulls
            .toList() ??
        [];

    final announcements =
        jsonObject
            .optJsonArray('announcements', remove: true)
            ?.map(
              (dynamic announcementJson) => Announcement.fromJson(
                announcementJson as Map<String, dynamic>,
              ),
            )
            .nonNulls
            .toList() ??
        [];

    var audiences = <Audience>[];

    final audienceJson = jsonObject.opt('audiences', remove: true);
    if (audienceJson is String) {
      audiences = [Audience.fromString(audienceJson)];
    } else if (audienceJson is List) {
      audiences = audienceJson
          .map(
            (dynamic audienceValue) => Audience.fromString(audienceValue as String?),
          )
          .nonNulls
          .toList();
    }

    final collectionSize =
        jsonObject.optJsonObject('collection_size', remove: true)?.map((key, value) => MapEntry(key, value as int)) ??
        {};

    final colorScheme = jsonObject.optNullableString(
      'color_scheme',
      remove: true,
    );

    final featureFlagsJson = jsonObject.optJsonObject(
      'feature_flags',
      remove: true,
    );
    final featureFlags = featureFlagsJson != null ? FeatureFlags.fromJson(featureFlagsJson) : null;

    final inputDataJson = jsonObject.optJsonObject('inputs', remove: true);
    final inputs = inputDataJson != null ? InputData.fromJson(inputDataJson) : null;

    final labels = jsonObject
        .optJsonObject('labels', remove: true)
        ?.map((key, value) => MapEntry(key, value.toString()));

    final publicKeyJson = jsonObject.optJsonObject('public_key', remove: true);
    final publicKey = publicKeyJson != null ? PublicKeyData.fromJson(publicKeyJson) : null;

    final serviceDescription = jsonObject.optNullableString(
      'service_description',
      remove: true,
    );
    final webColorSchemeJson = jsonObject.optJsonObject(
      'web_color_scheme',
      remove: true,
    );
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

  static const _unset = Object();

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
    Object? type = _unset,
    Object? id = _unset,
    Object? description = _unset,
    Object? links = _unset,
    Object? announcements = _unset,
    Object? audiences = _unset,
    Object? collectionSize = _unset,
    Object? colorScheme = _unset,
    Object? featureFlags = _unset,
    Object? inputs = _unset,
    Object? labels = _unset,
    Object? publicKey = _unset,
    Object? serviceDescription = _unset,
    Object? webColorScheme = _unset,
    Object? additionalProperties = _unset,
  }) {
    final mergeProperties = identical(additionalProperties, _unset) || additionalProperties == null
        ? Map<String, dynamic>.of(this.additionalProperties)
        : Map<String, dynamic>.of(this.additionalProperties)
            ..addAll(additionalProperties as Map<String, dynamic>)
            ..removeWhere((key, value) => value == null);

    return OpdsAuthentication(
      type: identical(type, _unset) ? this.type : (type as String?)!,
      id: identical(id, _unset) ? this.id : (id as String?)!,
      links: identical(links, _unset) ? this.links : (links as List<Link>?)!,
      description: identical(description, _unset) ? this.description : description as String?,
      announcements: identical(announcements, _unset) ? this.announcements : (announcements as List<Announcement>?)!,
      audiences: identical(audiences, _unset) ? this.audiences : (audiences as List<Audience>?)!,
      collectionSize: identical(collectionSize, _unset) ? this.collectionSize : (collectionSize as Map<String, int>?)!,
      colorScheme: identical(colorScheme, _unset) ? this.colorScheme : colorScheme as String?,
      featureFlags: identical(featureFlags, _unset) ? this.featureFlags : (featureFlags as FeatureFlags?)!,
      inputs: identical(inputs, _unset) ? this.inputs : (inputs as InputData?)!,
      labels: identical(labels, _unset) ? this.labels : (labels as Map<String, String>?)!,
      publicKey: identical(publicKey, _unset) ? this.publicKey : (publicKey as PublicKeyData?)!,
      serviceDescription: identical(serviceDescription, _unset)
          ? this.serviceDescription
          : serviceDescription as String?,
      webColorScheme: identical(webColorScheme, _unset) ? this.webColorScheme : (webColorScheme as WebColor?)!,
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
class OpdsAuthenticationFlow with Equatable implements JSONable {
  factory OpdsAuthenticationFlow.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final type = jsonObject.optString('type', remove: true);
    final links =
        jsonObject
            .optJsonArray('links', remove: true)
            ?.map(
              (dynamic linkJson) => Link.fromJson(linkJson as Map<String, dynamic>),
            )
            .nonNulls
            .toList() ??
        [];

    return OpdsAuthenticationFlow(type: type, links: links);
  }

  const OpdsAuthenticationFlow({required this.type, this.links = const []});
  static const _unset = Object();
  final String type;
  final List<Link> links;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('type', type)
    ..putIterableIfNotEmpty('links', links);

  OpdsAuthenticationFlow copyWith({Object? type = _unset, Object? links = _unset}) => OpdsAuthenticationFlow(
    type: identical(type, _unset) ? this.type : (type as String?)!,
    links: identical(links, _unset) ? this.links : (links as List<Link>?)!,
  );

  @override
  List<Object?> get props => [type, links];
}

@immutable
class OpdsAuthenticationLabels with Equatable implements JSONable {
  factory OpdsAuthenticationLabels.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final login = jsonObject.optNullableString('login', remove: true);
    final password = jsonObject.optNullableString('password', remove: true);

    return OpdsAuthenticationLabels(login: login, password: password);
  }
  const OpdsAuthenticationLabels({this.login, this.password});

  static const _unset = Object();

  final String? login;
  final String? password;

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('login', login)
    ..putOpt('password', password);

  OpdsAuthenticationLabels copyWith({Object? login = _unset, Object? password = _unset}) => OpdsAuthenticationLabels(
    login: identical(login, _unset) ? this.login : (login as String?)!,
    password: identical(password, _unset) ? this.password : (password as String?)!,
  );

  @override
  List<Object?> get props => [login, password];
}

/// Announcement object
/// See: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#sitewide-announcements
@immutable
class Announcement extends AdditionalProperties with Equatable implements JSONable {
  factory Announcement.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final id = jsonObject.optString('id', remove: true);
    final content = jsonObject.optString('content', remove: true);

    return Announcement(
      id: id,
      content: content,
      additionalProperties: jsonObject,
    );
  }
  const Announcement({
    required this.id,
    required this.content,
    super.additionalProperties,
  });

  final String id;
  final String content;

  @override
  Map<String, dynamic> toJson() => Map.from(additionalProperties)
    ..put('id', id)
    ..put('content', content);

  static const _unset = Object();

  Announcement copyWith({
    Object? id = _unset,
    Object? content = _unset,
    Object? additionalProperties = _unset,
  }) {
    final mergeProperties = identical(additionalProperties, _unset) || additionalProperties == null
        ? Map<String, dynamic>.of(this.additionalProperties)
        : Map<String, dynamic>.of(this.additionalProperties)
            ..addAll(additionalProperties as Map<String, dynamic>)
            ..removeWhere((key, value) => value == null);

    return Announcement(
      id: identical(id, _unset) ? this.id : (id as String?)!,
      content: identical(content, _unset) ? this.content : (content as String?)!,
      additionalProperties: mergeProperties,
    );
  }

  @override
  List<Object?> get props => [id, content, additionalProperties];
}

/// Audience enum representing the intended audience for a resource.
enum Audience {
  /// No audience specified.
  none('none'),

  /// Open to the general public. If this is specified, any other values are redundant.
  public('public'),

  /// Open to pre-university students.
  educationalPrimary('educational-primary'),

  /// Open to university-level students.
  educationalSecondary('educational-secondary'),

  /// Open to academics and researchers.
  research('research'),

  /// Open only to those who have a print disability.
  printDisability('print-disability'),

  /// Open to people who meet some other qualification.
  other('other');

  const Audience(this.name);

  final String name;

  static Audience fromString(String? value) =>
      Audience.values.firstWhereOrNull(
        (audience) => audience.name.toLowerCase() == value?.toLowerCase(),
      ) ??
      Audience.none;
}

/// FeatureFlags class
/// See: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#feature-flags
@immutable
class FeatureFlags with Equatable implements JSONable {
  factory FeatureFlags.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final enabled =
        (jsonObject.optJsonArray(
          'enabled',
          remove: true,
        ))?.whereType<String>().toList() ??
        [];
    final disabled =
        (jsonObject.optJsonArray(
          'disabled',
          remove: true,
        ))?.whereType<String>().toList() ??
        [];

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

  static const _unset = Object();

  FeatureFlags copyWith({Object? enabled = _unset, Object? disabled = _unset}) => FeatureFlags(
    enabled: identical(enabled, _unset) ? this.enabled : (enabled as List<String>?)!,
    disabled: identical(disabled, _unset) ? this.disabled : (disabled as List<String>?)!,
  );

  @override
  List<Object?> get props => [enabled, disabled];
}

@immutable
class InputField with Equatable implements JSONable {
  factory InputField.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final keyboard = KeyboardType.optFromString(
      jsonObject.optNullableString('keyboard', remove: true),
    );
    final maximumLength = jsonObject.optNullableInt(
      'maximum_length',
      remove: true,
    );

    return InputField(keyboard: keyboard, maximumLength: maximumLength);
  }

  const InputField({this.keyboard, this.maximumLength});

  final KeyboardType? keyboard;
  final int? maximumLength;

  static const _unset = Object();

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('keyboard', keyboard?.name)
    ..putOpt('maximum_length', maximumLength);

  InputField copyWith({Object? keyboard = _unset, Object? maximumLength = _unset}) => InputField(
    keyboard: identical(keyboard, _unset) ? this.keyboard : keyboard as KeyboardType?,
    maximumLength: identical(maximumLength, _unset) ? this.maximumLength : maximumLength as int?,
  );

  @override
  List<Object?> get props => [keyboard, maximumLength];
}

enum KeyboardType {
  defaultType('Default'),
  emailAddress('Email address'),
  numPad('Number pad'),
  noInput('No input');

  const KeyboardType(this.name);

  final String name;

  static KeyboardType? optFromString(String? value) => KeyboardType.values.firstWhereOrNull(
    (keyboardType) => keyboardType.name.toLowerCase() == value?.toLowerCase(),
  );
}

@immutable
class LoginInputField extends InputField with Equatable {
  factory LoginInputField.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final barcodeFormat = jsonObject.optNullableString(
      'barcode_format',
      remove: true,
    );

    // Parse base InputField properties
    final keyboard = KeyboardType.optFromString(
      jsonObject.optNullableString('keyboard', remove: true),
    );
    final maximumLength = jsonObject.optNullableInt(
      'maximum_length',
      remove: true,
    );

    return LoginInputField(
      barcodeFormat: barcodeFormat,
      keyboard: keyboard,
      maximumLength: maximumLength,
    );
  }

  const LoginInputField({
    this.barcodeFormat,
    super.keyboard,
    super.maximumLength,
  });

  /// Barcode format.
  final String? barcodeFormat;

  @override
  Map<String, dynamic> toJson() => super.toJson()..putOpt('barcode_format', barcodeFormat);

  static const _unset = Object();

  @override
  LoginInputField copyWith({
    Object? barcodeFormat = _unset,
    Object? keyboard = _unset,
    Object? maximumLength = _unset,
  }) => LoginInputField(
    barcodeFormat: identical(barcodeFormat, _unset) ? this.barcodeFormat : barcodeFormat as String?,
    keyboard: identical(keyboard, _unset) ? this.keyboard : keyboard as KeyboardType?,
    maximumLength: identical(maximumLength, _unset) ? this.maximumLength : maximumLength as int?,
  );

  @override
  List<Object?> get props => [barcodeFormat, keyboard, maximumLength];
}

@immutable
class InputData with Equatable implements JSONable {
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

  const InputData({
    this.login = const LoginInputField(),
    this.password = const InputField(),
  });

  final LoginInputField login;
  final InputField password;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('login', login)
    ..put('password', password);

  static const _unset = Object();

  InputData copyWith({Object? login = _unset, Object? password = _unset}) => InputData(
    login: identical(login, _unset) ? this.login : (login as LoginInputField?)!,
    password: identical(password, _unset) ? this.password : (password as InputField?)!,
  );

  @override
  List<Object?> get props => [login, password];
}

/// If your OPDS server needs to receive cryptographically signed messages (e.g. to set up shared secrets with other servers),
/// you can publish your public key in the authentication document.
@immutable
class PublicKeyData with Equatable implements JSONable {
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

  static const _unset = Object();

  PublicKeyData copyWith({Object? type = _unset, Object? value = _unset}) => PublicKeyData(
    type: identical(type, _unset) ? this.type : (type as String?)!,
    value: identical(value, _unset) ? this.value : (value as String?)!,
  );

  @override
  List<Object?> get props => [type, value];
}

/// Web color scheme.
/// See: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#web-color-scheme
@immutable
class WebColor with Equatable implements JSONable {
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

  static const _unset = Object();

  WebColor copyWith({Object? primary = _unset, Object? secondary = _unset}) => WebColor(
    primary: identical(primary, _unset) ? this.primary : (primary as String?)!,
    secondary: identical(secondary, _unset) ? this.secondary : (secondary as String?)!,
  );

  @override
  List<Object?> get props => [primary, secondary];
}
