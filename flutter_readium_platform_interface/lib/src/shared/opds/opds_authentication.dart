import '../../utils/additional_properties.dart';
import '../../utils/jsonable.dart';
import '../publication/link.dart';

/// OPDS Authentication Object plus NYPL additions.
/// https://github.com/opds-community/drafts/blob/main/schema/authentication.schema.json
///
/// NYPL extensions: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions
class OpdsAuthentication extends AdditionalProperties implements JSONable {
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
  Map<String, dynamic> toJson() => <String, dynamic>{
    ...additionalProperties,
    'type': type,
    'id': id,
    if (description != null) 'description': description,
    'links': links.map((link) => link.toJson()).toList(),
    'authentication': authentication.map((flow) => flow.toJson()).toList(),
    'announcements': announcements.map((announcement) => announcement.toJson()).toList(),
    if (audiences.isNotEmpty)
      'audiences': audiences.length > 1
          ? audiences.map((audience) => audience.toString()).toList()
          : audiences.first.toString(),
    if (collectionSize.isNotEmpty) 'collection_size': collectionSize,
    if (colorScheme != null) 'color_scheme': colorScheme,
    if (featureFlags != null) 'feature_flags': featureFlags?.toJson(),
    if (inputs != null) 'inputs': inputs?.toJson(),
    if (labels != null) 'labels': labels,
    if (publicKey != null) 'public_key': publicKey?.toJson(),
    if (serviceDescription != null) 'service_description': serviceDescription,
    if (webColorScheme != null) 'web_color_scheme': webColorScheme?.toJson(),
  };

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
}

class OpdsAuthenticationFlow implements JSONable {
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
  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type,
    'links': links.map((link) => link.toJson()).toList(),
  };

  OpdsAuthenticationFlow copyWith({String? type, List<Link>? links}) =>
      OpdsAuthenticationFlow(type: type ?? this.type, links: links ?? this.links);
}

class OpdsAuthenticationLabels implements JSONable {
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
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (login != null) 'login': login,
    if (password != null) 'password': password,
  };

  OpdsAuthenticationLabels copyWith({String? login, String? password}) =>
      OpdsAuthenticationLabels(login: login ?? this.login, password: password ?? this.password);
}

/// Announcement object
/// See: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#sitewide-announcements
class Announcement implements JSONable {
  factory Announcement.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final id = jsonObject.optString('id', remove: true);
    final content = jsonObject.optString('content', remove: true);

    return Announcement(id: id, content: content);
  }
  const Announcement({required this.id, required this.content});

  final String id;
  final String content;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'content': content};

  Announcement copyWith({String? id, String? content}) =>
      Announcement(id: id ?? this.id, content: content ?? this.content);
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
  /// Maps enum to its string value.
  String get value {
    switch (this) {
      case Audience.none:
        return 'none';
      case Audience.public:
        return 'public';
      case Audience.educationalPrimary:
        return 'educational-primary';
      case Audience.educationalSecondary:
        return 'educational-secondary';
      case Audience.research:
        return 'research';
      case Audience.printDisability:
        return 'print-disability';
      case Audience.other:
        return 'other';
    }
  }

  /// Parses a string to an Audience enum.
  static Audience fromString(String? value) {
    switch (value) {
      case 'public':
        return Audience.public;
      case 'educational-primary':
        return Audience.educationalPrimary;
      case 'educational-secondary':
        return Audience.educationalSecondary;
      case 'research':
        return Audience.research;
      case 'print-disability':
        return Audience.printDisability;
      case 'other':
        return Audience.other;
      case 'none':
      default:
        return Audience.none;
    }
  }
}

/// FeatureFlags class
/// See: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#feature-flags
class FeatureFlags implements JSONable {
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
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (enabled.isNotEmpty) 'enabled': enabled,
    if (disabled.isNotEmpty) 'disabled': disabled,
  };

  FeatureFlags copyWith({List<String>? enabled, List<String>? disabled}) =>
      FeatureFlags(enabled: enabled ?? this.enabled, disabled: disabled ?? this.disabled);
}

class InputField implements JSONable {
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
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (keyboard != null) 'keyboard': keyboard!.value,
    if (maximumLength != null) 'maximum_length': maximumLength,
  };

  InputField copyWith({KeyboardType? keyboard, int? maximumLength}) =>
      InputField(keyboard: keyboard ?? this.keyboard, maximumLength: maximumLength ?? this.maximumLength);
}

enum KeyboardType { defaultType, emailAddress, numPad, noInput }

extension KeyboardTypeExtension on KeyboardType? {
  String? get value {
    switch (this) {
      case KeyboardType.defaultType:
        return 'Default';
      case KeyboardType.emailAddress:
        return 'Email address';
      case KeyboardType.numPad:
        return 'Number pad';
      case KeyboardType.noInput:
        return 'No input';
      default:
        return null;
    }
  }

  static KeyboardType? fromString(String? value) {
    switch (value) {
      case 'Default':
        return KeyboardType.defaultType;
      case 'Email address':
        return KeyboardType.emailAddress;
      case 'Number pad':
        return KeyboardType.numPad;
      case 'No input':
        return KeyboardType.noInput;
      default:
        return null;
    }
  }
}

class LoginInputField extends InputField {
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
  Map<String, dynamic> toJson() => <String, dynamic>{
    ...super.toJson(),
    if (barcodeFormat != null) 'barcode_format': barcodeFormat,
  };

  @override
  LoginInputField copyWith({String? barcodeFormat, KeyboardType? keyboard, int? maximumLength}) => LoginInputField(
    barcodeFormat: barcodeFormat ?? this.barcodeFormat,
    keyboard: keyboard ?? this.keyboard,
    maximumLength: maximumLength ?? this.maximumLength,
  );
}

class InputData implements JSONable {
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
  Map<String, dynamic> toJson() => <String, dynamic>{'login': login.toJson(), 'password': password.toJson()};

  InputData copyWith({LoginInputField? login, InputField? password}) =>
      InputData(login: login ?? this.login, password: password ?? this.password);
}

/// If your OPDS server needs to receive cryptographically signed messages (e.g. to set up shared secrets with other servers),
/// you can publish your public key in the authentication document.
class PublicKeyData implements JSONable {
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
  Map<String, dynamic> toJson() => <String, dynamic>{'type': type, 'value': value};

  PublicKeyData copyWith({String? type, String? value}) =>
      PublicKeyData(type: type ?? this.type, value: value ?? this.value);
}

/// Web color scheme.
/// See: https://github.com/NYPL-Simplified/Simplified/wiki/Authentication-For-OPDS-Extensions#web-color-scheme
class WebColor implements JSONable {
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
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (shouldSerializePrimary) 'primary': primary,
    if (shouldSerializeSecondary) 'secondary': secondary,
  };

  WebColor copyWith({String? primary, String? secondary}) =>
      WebColor(primary: primary ?? this.primary, secondary: secondary ?? this.secondary);
}
