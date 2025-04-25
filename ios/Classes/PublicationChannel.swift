import Flutter
import Foundation
import ReadiumShared
import ReadiumStreamer
import PromiseKit

private let TAG = "PublicationChannel"

let publicationChannelName = "dk.nota.flutter_readium/Publication"

private var publication: Publication? = nil

func publicationFromHandle() -> Publication? {
  return publication
}

class SwiftR2PublicationChannel {

  private func openPublication(
    at url: AbsoluteURL,
    allowUserInteraction: Bool,
    knownMediaType: MediaType?,
    sender: UIViewController?
  ) async throws -> (Publication, Format) {
    do {
      let asset: Asset;
      if (knownMediaType != nil) {
        asset = try await sharedReadium.assetRetriever.retrieve(url: url, mediaType: knownMediaType!).get()
      } else {
        asset = try await sharedReadium.assetRetriever.retrieve(url: url).get()
      }

      let publication = try await sharedReadium.publicationOpener.open(
        asset: asset,
        allowUserInteraction: allowUserInteraction,
        sender: sender
      ).get()

      return (publication, asset.format)

    } catch AssetRetrieveError.formatNotSupported {
      throw LibraryError.openFailed(AssetRetrieveError.formatNotSupported)
    } catch AssetRetrieveError.reading (let err) {
      throw LibraryError.openFailed(err)
    }
  }


  private func parseMediaType(_ mediaType: Any?) -> MediaType? {
    guard let list = mediaType as! [String?]? else {
      return nil
    }
    return MediaType(list[0]! as String)
  }

  func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "fromPath":
      let args = call.arguments as! [Any?]
      let path = args[0] as! String
      let mediaType = parseMediaType(args[1])
      // Create a FileAsset referring to a file in the filesystem.
      //handleFromSomething(asset: FileAsset(url: URL(fileURLWithPath: path), mediaType: mediaType), result: result)
      let encodedFilePath = "file://\(path)".addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
      guard let url = URL(string: encodedFilePath!) else {
        return result(FlutterError.init(
          code: "InvalidArgument",
          message: "Invalid publication URL: \(path)",
          details: nil))
      }

      Task.detached(priority: .background) {
        do {
          let openedPub: (Publication, Format) = try await self.openPublication(at: url.anyURL.absoluteURL!, allowUserInteraction: false, knownMediaType: mediaType, sender: nil)
          // Try accessing positions
          let pub = openedPub.0
          let format = openedPub.1
          publication = pub
          let _ = pub.positions
          let jsonManifest = pub.jsonManifest
          DispatchQueue.main.async { [jsonManifest] in
            print("\(TAG)::fromPath back on \(Thread.current)")
            result(jsonManifest)
          }
        }
      }
      break
    case "fromLink":
      let args = call.arguments as! [Any?]
      let href = args[0] as! String
      let headers = args[1] as! [String: String]
      let mediaType = parseMediaType(args[2])!
      // TODO: handle headers
      guard let url = URL(string: href) else {
        return result(FlutterError.init(
          code: "InvalidArgument",
          message: "Invalid publication URL: \(href)",
          details: nil))
      }
      Task.detached(priority: .background) {
        let openedPub: (Publication, Format) = try await self.openPublication(at: url.anyURL.absoluteURL!, allowUserInteraction: false, knownMediaType: mediaType, sender: nil)
        let pub = openedPub.0
        let format = openedPub.1
        publication = pub
        let _ = pub.positions
        let jsonManifest = pub.jsonManifest
        DispatchQueue.main.async { [jsonManifest] in
          print("\(TAG)::fromLink back on \(Thread.current)")
          result(jsonManifest)
        }
      }
      break
    case "dispose":
      print("\(TAG) dispose")
      publication?.close()
      publication = nil
      result(nil)
      break
    case "get":
      let args = call.arguments as! [Any?]
      let isLink = args[0] as! Bool
      let linkData = args[1] as! String
      let asString = args[2] as! Bool
      let link = isLink ? try! Link(json: try! JSONSerialization.jsonObject(with: linkData.data(using: .utf8)!, options: [])) : nil
      // readAsString is an async suspend function in Swift.
      // Must run on background thread to avoid permanently deadlocking the main thread.
      guard let pub = publication else {
        return result(FlutterError.init(code: "", message: "No publication found", details: ""))
      }
      Task.detached(priority: .high) {
        do {
          guard let resource = isLink ? pub.get(link!) : pub.get(URL(string: linkData)!) else {
            return result(FlutterError.init(code: "", message: "Could not find resource", details: ""))
          }
          if asString {
            let string = try await resource.readAsString(encoding: .utf8).get()
            await MainActor.run {
              result(string)
            }
          } else {
            let data = try await resource.read().get()
            await MainActor.run {
              result(FlutterStandardTypedData(bytes: data))
            }
          }
        } catch let e {
          DispatchQueue.main.async {
            print("\(TAG)::get: Exception: \(e)")
            result(FlutterError.init(code: "\(type(of: e))", message: e.localizedDescription, details: "Something went wrong."))
          }
        }
      }
      break
    default:
      result(FlutterMethodNotImplemented)
      break
    }
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
