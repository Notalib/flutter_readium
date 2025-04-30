/// Indicates if the overflow of linked resources from the `readingOrder` or
/// `resources` should be handled using dynamic pagination or scrolling.
///
/// PartOf: [Metadata Json Schema](https://readium.org/webpub-manifest/schema/extensions/presentation/metadata.schema.json)
enum Overflow {
  auto,
  paginated,
  scrolled,
  scrollContinuous,
}
