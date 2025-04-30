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

let readium = Readium()

private var currentPublication: Publication? = nil

func getCurrentPublication() -> Publication? {
  return currentPublication
}

private func openPublication(
        at url: AbsoluteURL,
        allowUserInteraction: Bool,
        sender: UIViewController?
    ) async throws -> (Publication, Format) {
        do {
            let asset = try await readium.assetRetriever.retrieve(url: url).get()

            let publication = try await readium.publicationOpener.open(
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
  case "openPublication":
    let args = call.arguments as! [Any?]
    let pubUrlStr = args[0] as! String

//    let documentFolderURL = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
//    let fileURL = documentFolderURL.appendingPathComponent("readium_flutter/pubs/moby_dick.epub")
//    print("FileURL is \(fileURL.absoluteURL.absoluteString)")

    let encodedFilePath = "file://\(pubUrlStr)".addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
    guard let url = URL(string: encodedFilePath!) else {
      return result(FlutterError.init(
        code: "InvalidArgument",
        message: "Invalid publication URL: \(pubUrlStr)",
        details: nil))
    }

    print("Attempting to open publication at: \(url.absoluteString)")

    Task.detached(priority: .background) {
      do {
        let pub: (Publication, Format) = try await openPublication(at: url.anyURL.absoluteURL!, allowUserInteraction: false, sender: nil)
        let mediaType: String = pub.1.mediaType?.string ?? "unknown"
        print("Opened publication!")
        print("Opened publication (format): \(mediaType)")
        currentPublication = pub.0

        await MainActor.run {
          result(currentPublication?.jsonManifest)
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
  case "assetFromHttpURL":
//    let args = call.arguments as! [Any?]
//    let urlStr = args[0] as! String
//    let url = HTTPURL(string: urlStr)
//    if (url == nil) {
//      return result(FlutterError.init(
//        code: "InvalidArgument",
//        message: "Invalid file path: \(urlStr)",
//        details: nil))
//    }
//
//    Task.detached(priority: .background) {
//      let asset = await getAssetFromUrl(url: url!)!
//      let mediaType: String = asset.format.mediaType?.type ?? "unknown"
//
//      await MainActor.run {
//        result(mediaType)
//      }
//    }
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




// private func parseMediaType(_ mediaType: Any?) -> MediaType? {
//   guard let list = mediaType as! [String?]? else {
//     return nil
//   }
//   return MediaType(list[0]!, name: list[1], fileExtension: list[2])
// }

// func injectCSS(_ resource: Resource) -> Resource {
//   let comicCssKey = FlutterReadiumPlugin.registrar?.lookupKey(
//     forAsset: "assets/helpers/comics.css", fromPackage: "flutter_readium")
//   let epubCssKey = FlutterReadiumPlugin.registrar?.lookupKey(
//     forAsset: "assets/helpers/epub.css", fromPackage: "flutter_readium")

//   let sourceFiles = [comicCssKey, epubCssKey]
//   let source = sourceFiles.compactMap { sourceFile -> String? in
//     if let path = Bundle.main.path(forResource: sourceFile, ofType: nil),
//       let data = FileManager().contents(atPath: path),
//       let stringData = String(data: data, encoding: .utf8)
//     {
//       return stringData
//     }
//     print("\(TAG)::injectCSS No source found on \(String(describing: sourceFile))")

//     return nil
//   }.joined(separator: "\n")

//   // We only transform HTML resources.
//   guard resource.link.mediaType.isHTML else {
//     return resource
//   }

//   return resource.mapAsString { content -> String in
//     var content = content

//     if let headEnd = content.startIndex(of: "</head>") {
//       let style = "<style>\(source)</style>"
//       content = content.insert(string: style, at: headEnd)
//     } else {
//       print("\(TAG)::injectCSS No head found on the document")
//     }

//     return content
//   }
// }

// private func assetToPublication(asset: PublicationAsset) -> Promise<Publication> {
//   return Promise<Publication> { resolver in
//     // Convert the FileAsset to a Publication using a temporary Streamer.
//     //
//     // A Streamer contains an EPUB parser which converts it to something the navigator can understand (probably HTML).
//     // https://github.com/readium/architecture
//     Streamer().open(
//       asset: asset,
//       allowUserInteraction: false,
//       onCreatePublication: { _, _, fetcher, _ in
//         fetcher = TransformingFetcher(fetcher: fetcher, transformers: [injectCSS])
//       }
//     ) { result in
//       do {
//         let publication = try result.get()
//         resolver.fulfill(publication)
//       } catch let error {
//         print("error = \(error)")
//         resolver.reject(error)
//       }
//     }
//   }
// }

// private func handleFromSomething(asset: PublicationAsset, result: @escaping FlutterResult) {
//   await assetRetriever.retrieve(url: url.anyURL.absoluteURL!)
//   let _ = assetToPublication(asset: asset).done { pub in
//     print("\(TAG)::fromSomething created publication on \(Thread.current)")
//     DispatchQueue.global(qos: .background).async {
//       guard let jsonManifest = pub.jsonManifest else {
//         print("\(TAG)::fromSomething partially failed to create publication: jsonManifest == nil")
//         result([
//           nil, nil,
//           "Something very wrong, opened publication but got publication.jsonManifest == nil!",
//         ])
//         return
//       }
//       let _ = pub.positions
//       print(
//         "\(TAG)::fromSomething did publication?.positions, workaround for app deadlock via EPUBNavigatorViewController.viewDidLoad on \(Thread.current)"
//       )
//       DispatchQueue.main.async {
//         print("\(TAG)::fromSomething back on \(Thread.current)")
//         publication = pub
//         result(jsonManifest)
//       }
//     }
//   }.catch { error in
//     print("\(TAG)::fromSomething failed to create publication: \(error)")
//     if let openingError = error as? Publication.OpeningError {
//       result(
//         FlutterError.init(
//           code: "\(index(openingError: openingError)))", message: openingError.errorDescription,
//           details: openingError.failureReason))
//     } else {
//       result(
//         FlutterError.init(
//           code: "", message: error.localizedDescription, details: error.localizedDescription))
//     }
//   }
// }
