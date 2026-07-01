import Foundation
import CryptoKit

/// Caches publication resources (e.g. tapped EPUB images) to app-owned files
/// under `Caches/flutter_readium_resources/`, keyed by a hash of their href.
///
/// Used so the platform channel can hand Flutter a short `file://` URL
/// instead of transferring the resource's bytes over the bridge.
enum ResourceFileCache {
  private static var directory: URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    return caches.appendingPathComponent("flutter_readium_resources", isDirectory: true)
  }

  /// Returns the cache file URL for `href`, creating the cache directory if
  /// needed. Does not check whether the file itself already exists.
  static func fileURL(forHref href: String) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let digest = SHA256.hash(data: Data(href.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    let ext = (href as NSString).pathExtension
    let fileName = ext.isEmpty ? hex : "\(hex).\(ext)"
    return directory.appendingPathComponent(fileName)
  }

  /// Removes all cached resource files. Called when a publication closes so
  /// entries don't outlive the publication they were fetched from.
  static func purgeAll() {
    try? FileManager.default.removeItem(at: directory)
  }
}
