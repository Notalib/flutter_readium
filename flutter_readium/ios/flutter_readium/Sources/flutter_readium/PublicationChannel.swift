import Flutter
import PromiseKit
import ReadiumShared
import ReadiumStreamer

// PublicationChannel handles opening publications via the Readium toolkit.
// See https://github.com/readium/swift-toolkit/blob/develop/docs/Guides/Open%20Publication.md

// For general docs on using async code via bridge
// see: https://docs.flutter.dev/get-started/flutter-for/dart-swift-concurrency#leveraging-a-background-threadisolate

private let TAG = "PublicationChannel"

let publicationChannelName = "dk.nota.flutter_readium/Publication"

private var currentPublication: Publication? = nil
private var openedReadiumPublications = [String: Publication]()

func getCurrentPublication() -> Publication? {
  return currentPublication
}

func getPublicationByIdentifier(_ identifier: String) -> Publication? {
  return openedReadiumPublications[identifier]
}

private func openPublication(
        at url: AbsoluteURL,
        allowUserInteraction: Bool,
        sender: UIViewController?
    ) async throws -> (Publication, Format) {
        do {
            let asset = try await sharedReadium.assetRetriever!.retrieve(url: url).get()

            let publication = try await sharedReadium.publicationOpener!.open(
                asset: asset,
                allowUserInteraction: allowUserInteraction,
                sender: sender
            ).get()

            return (publication, asset.format)

        } catch {
            throw LibraryError.openFailed(error)
        }
    }


private func getAssetFromUrl(url: AbsoluteURL) async -> Asset? {
  let assetRetriever = AssetRetriever(httpClient: DefaultHTTPClient())
  switch await assetRetriever.retrieve(url: url) {
  case .success(let asset):
    return asset
  case .failure(let error):
    print("\(TAG)::getAssetFromUrl failed to retrieve asset: \(error)")
    return nil
  }
}

func publicationMethodCallHandler(call: FlutterMethodCall, result: @escaping FlutterResult) {
  switch call.method {
  case "setCurrentPublication":
    let pubId = call.arguments as! String
    let pub = openedReadiumPublications[pubId]
    if (pub != nil) {
      currentPublication = pub
      result(true)
    } else {
      result(FlutterError.init(
        code: "InvalidArgument",
        message: "Invalid publication ID: \(pubId), did you call openPublication first?",
        details: nil))
    }
    break
  case "openPublication":
    let args = call.arguments as! [Any?]
    var pubUrlStr = args[0] as! String

    if (!pubUrlStr.hasPrefix("http") && !pubUrlStr.hasPrefix("file")) {
      // Assume URLs without a supported prefix are local file paths.
      pubUrlStr = "file://\(pubUrlStr)"
    }

    let encodedUrlStr = "\(pubUrlStr)".addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
    guard let url = URL(string: encodedUrlStr!) else {
      return result(FlutterError.init(
        code: "InvalidArgument",
        message: "Invalid publication URL: \(pubUrlStr)",
        details: nil))
    }

    print("Attempting to open publication at: \(url.absoluteString)")

    Task.detached(priority: .background) {
      do {
        guard let absUrl = url.anyURL.absoluteURL else {
          return result(FlutterError.init(
            code: "InvalidArgument",
            message: "Invalid publication absoluteURL: \(url.absoluteString)",
            details: nil))
        }
        let pub: (Publication, Format) = try await openPublication(at: absUrl, allowUserInteraction: false, sender: nil)
        print("Opened publication!")
        let mediaType: String = pub.1.mediaType?.string ?? "unknown"
        print("Opened publication (format): \(mediaType)")
        openedReadiumPublications[pub.0.metadata.identifier ?? url.absoluteString] = pub.0
        currentPublication = pub.0

        await MainActor.run {
          result(pub.0.jsonManifest)
        }
      } catch {
          await MainActor.run {
            result(FlutterError.init(
              code: "OpenPublicationError",
              message: "Failed to open publication: \(error.localizedDescription)",
              details: nil))
          }
      }
    }
    break
  default:
    result(FlutterMethodNotImplemented)
    break
  }
}

extension String {
  fileprivate func endIndex(of string: String, options: CompareOptions = .literal) -> Index? {
    return range(of: string, options: options)?.upperBound
  }

  fileprivate func startIndex(of string: String, options: CompareOptions = .literal) -> Index? {
    return range(of: string, options: options)?.lowerBound
  }

  fileprivate func insert(string: String, at index: String.Index) -> String {
    let prefix = self[..<index]  //substring(to: index)
    let suffix = self[index...]  //substring(from: index)

    return prefix + string + suffix
  }
}
