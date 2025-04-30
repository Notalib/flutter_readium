class MediaType {
  const MediaType(
    this.value, {
    this.name,
    this.fileExtension,
  });

  /// - The string representation of this media type.
  /// - Type, subtype and parameter names are lowercase.
  /// - Parameter values keep their original case, except for the charset parameter, which is uppercase.
  /// - Parameters are ordered alphabetically.
  /// - No spaces between parameters.
  final String value;

  /// A human readable name identifying the media type, which may be presented to the user.
  final String? name;

  /// The default file extension to use for this media type.
  final String? fileExtension;

  /// The type component, e.g. application in application/epub+zip
  String get type => value.split('/').first;

  /// The subtype component, e.g. epub+zip in application/epub+zip.
  String get subtype => value.split('/').last;

  /// Structured syntax suffix, e.g. +zip in application/epub+zip
  /// Gives a hint about the underlying structure of this media type.
  /// i.e. https://tools.ietf.org/html/rfc6838#section-4.2.8
  String? get structuredSyntaxSuffix {
    if (subtype.contains('+')) {
      return '+${subtype.split('+').last}';
    }

    return null;
  }

  /// Returns whether this media type is structured as a ZIP archive.
  bool get isZip => subtype.toLowerCase().contains('zip');

  /// Returns whether this media type is structured as a JSON file.
  bool get isJSON => subtype.contains('json');

  /// Returns whether this media type is contained by OPDS1, OPDS1Entry, OPDS2 or OPDS2Publication.
  /// Used to determine the type of remote catalogs.
  bool get isOPDS => subtype.toLowerCase().contains('opds');

  /// Returns whether this media type is contained by HTML or XHTML.
  /// Used to determine the type of remote catalogs.
  bool get isHtml => subtype.toLowerCase().contains('html');

  /// Returns whether this media type is a bitmap image, so excluding SVG and other vectorial formats. It must be contained by BMP, GIF, JPEG, JXL, PNG, TIFF, WebP or AVIF.
  /// Used to determine if a RWPM is a DiViNa publication.
  // bool get isBitmap => true;

  /// Returns whether this media type is of an audio clip.
  /// Used to determine if a RWPM is an Audiobook publication.
  bool get isAudio => type.toLowerCase().contains('audio');

  /// Returns whether this media type is of a publication file.
  // bool get isPublication => true;

  static const aac = MediaType('audio/aac', fileExtension: 'aac');
  static const acsm = MediaType(
    'application/vnd.adobe.adept+xml',
    name: 'Adobe Content Server Message',
    fileExtension: 'acsm',
  );
  static const aiff = MediaType('audio/aiff', fileExtension: 'aiff');
  static const avi = MediaType('video/x-msvideo', fileExtension: 'avi');
  static const binary = MediaType('application/octet-stream');
  static const bmp = MediaType('image/bmp', fileExtension: 'bmp');
  static const cbz =
      MediaType('application/vnd.comicbook+zip', name: 'Comic Book Archive', fileExtension: 'cbz');
  static const css = MediaType('text/css', fileExtension: 'css');
  static const divina = MediaType(
    'application/divina+zip',
    name: 'Digital Visual Narratives',
    fileExtension: 'divina',
  );
  static const divinaManifest = MediaType(
    'application/divina+json',
    name: 'Digital Visual Narratives',
    fileExtension: 'json',
  );
  static const epub = MediaType('application/epub+zip', name: 'EPUB', fileExtension: 'epub');
  static const gif = MediaType('image/gif', fileExtension: 'gif');
  static const gz = MediaType('application/gzip', fileExtension: 'gz');
  static const html = MediaType('text/html', fileExtension: 'html');
  static const javascript = MediaType('text/javascript', fileExtension: 'js');
  static const jpeg = MediaType('image/jpeg', fileExtension: 'jpg');
  static const json = MediaType('application/json', fileExtension: 'json');
  static const lcpLicenseDocument = MediaType(
    'application/vnd.readium.lcp.license.v1.0+json',
    name: 'LCP License',
    fileExtension: 'lcpl',
  );
  static const lcpProtectedAudiobook = MediaType(
    'application/audiobook+lcp',
    name: 'LCP Protected Audiobook',
    fileExtension: 'lcpa',
  );
  static const lcpProtectedPDF =
      MediaType('application/pdf+lcp', name: 'LCP Protected PDF', fileExtension: 'lcpdf');
  static const lcpStatusDocument = MediaType('application/vnd.readium.license.status.v1.0+json');
  static const lpf = MediaType('application/lpf+zip', fileExtension: 'lpf');
  static const mp3 = MediaType('audio/mpeg', fileExtension: 'mp3');
  static const mpeg = MediaType('video/mpeg', fileExtension: 'mpeg');
  static const ncx = MediaType('application/x-dtbncx+xml', fileExtension: 'ncx');
  static const ogg = MediaType('audio/ogg', fileExtension: 'oga');
  static const ogv = MediaType('video/ogg', fileExtension: 'ogv');
  static const opds1 = MediaType('application/atom+xml;profile=opds-catalog');
  static const opds1Entry = MediaType('application/atom+xml;type=entry;profile=opds-catalog');
  static const opds2 = MediaType('application/opds+json');
  static const opds2Publication = MediaType('application/opds-publication+json');
  static const opdsAuthentication = MediaType('application/opds-authentication+json');
  static const opus = MediaType('audio/opus', fileExtension: 'opus');
  static const otf = MediaType('font/otf', fileExtension: 'otf');
  static const pdf = MediaType('application/pdf', name: 'PDF', fileExtension: 'pdf');
  static const png = MediaType('image/png', fileExtension: 'png');
  static const readiumAudiobook =
      MediaType('application/audiobook+zip', name: 'Readium Audiobook', fileExtension: 'audiobook');
  static const readiumAudiobookManifest =
      MediaType('application/audiobook+json', name: 'Readium Audiobook', fileExtension: 'json');
  static const readiumWebPub =
      MediaType('application/webpub+zip', name: 'Readium Web Publication', fileExtension: 'webpub');
  static const readiumWebPubManifest =
      MediaType('application/webpub+json', name: 'Readium Web Publication', fileExtension: 'json');
  static const smil = MediaType('application/smil+xml', fileExtension: 'smil');
  static const svg = MediaType('image/svg+xml', fileExtension: 'svg');
  static const text = MediaType('text/plain', fileExtension: 'txt');
  static const tiff = MediaType('image/tiff', fileExtension: 'tiff');
  static const ttf = MediaType('font/ttf', fileExtension: 'ttf');
  static const w3cWPUBManifest = MediaType(
    'application/x.readium.w3c.wpub+json',
    name: 'Web Publication',
    fileExtension: 'json',
  ); // non-existent
  static const wav = MediaType('audio/wav', fileExtension: 'wav');
  static const webmAudio = MediaType('audio/webm', fileExtension: 'webm');
  static const webmVideo = MediaType('video/webm', fileExtension: 'webm');
  static const webp = MediaType('image/webp', fileExtension: 'webp');
  static const woff = MediaType('font/woff', fileExtension: 'woff');
  static const woff2 = MediaType('font/woff2', fileExtension: 'woff2');
  static const xhtml = MediaType('application/xhtml+xml', fileExtension: 'xhtml');
  static const xml = MediaType('application/xml', fileExtension: 'xml');
  static const zab = MediaType(
    'application/x.readium.zab+zip',
    name: 'Zipped Audio Book',
    fileExtension: 'zab',
  ); // non-existent
  static const zip = MediaType('application/zip', fileExtension: 'zip');
  static const syncMediaNarration =
      MediaType('application/vnd.syncnarr+json', fileExtension: 'json');

  List<String?> toList() => [value, name, fileExtension];

  @override
  bool operator ==(final Object other) =>
      other is MediaType &&
      value == other.value &&
      name == other.name &&
      fileExtension == other.fileExtension;

  @override
  int get hashCode =>
      1009 * (1009 * value.hashCode + name.hashCode | 0) + fileExtension.hashCode | 0;
}
