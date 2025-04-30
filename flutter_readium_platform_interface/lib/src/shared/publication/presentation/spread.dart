/// Indicates the condition to be met for the linked resource to be rendered
/// within a synthetic spread.
///
/// PartOf:
///   * [Properties Json Schema](https://readium.org/webpub-manifest/schema/extensions/presentation/properties.schema.json)
///   * [Metadata Json Schema](https://readium.org/webpub-manifest/schema/extensions/presentation/metadata.schema.json)
enum Spread {
  auto,
  both,
  none,
  landscape,
}
