import Flutter
import ReadiumLCP
import ReadiumShared
import UIKit
import flutter_readium
import os

private let log = Logger(subsystem: "dk.nota.flutter_readium_lcp", category: "FlutterReadiumLcp")

/// Registers LCP with `flutter_readium`. Needs the app's `LCPClient`, which wraps EDRLab's private
/// R2LCPClient library; this plugin never ships that library.
public final class FlutterReadiumLcpPlugin: NSObject, FlutterPlugin {
  /// The app's `LCPClient`. Set it before `GeneratedPluginRegistrant.register`: the plugin reads it
  /// once, while it registers. Without it, or when set later, LCP stays disabled.
  public static var lcpClient: LCPClient? {
    didSet {
      if didRegisterPlugin {
        log.warning(
          "FlutterReadiumLcpPlugin.lcpClient was set after plugin registration and is ignored. Set it before GeneratedPluginRegistrant.register."
        )
      }
    }
  }

  /// Channels of the registered engines, oldest first.
  private static var channels: [FlutterMethodChannel] = []
  /// Channel of the latest registered engine; the toolkit's passphrase prompts go through it.
  fileprivate static var channel: FlutterMethodChannel? { channels.last }
  private static var didRegisterPlugin = false
  private static var didRegisterWithCore = false

  /// The channel this instance serves, so detaching its engine clears the right one.
  private var engineChannel: FlutterMethodChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    didRegisterPlugin = true
    let channel = FlutterMethodChannel(name: "dk.nota/flutter_readium_lcp", binaryMessenger: registrar.messenger())
    channels.append(channel)
    let instance = FlutterReadiumLcpPlugin()
    instance.engineChannel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.publish(instance)

    guard !didRegisterWithCore else { return }
    guard let service = services()?.service else {
      log.info("No LCPClient set on FlutterReadiumLcpPlugin.lcpClient; LCP is disabled.")
      return
    }
    didRegisterWithCore = true

    FlutterReadiumContentProtections.register { service.contentProtection(with: DartAuthentication()) }
    FlutterReadiumRestrictions.registerMapper { publication in
      guard publication.findService(ContentProtectionService.self)?.scheme == .lcp else { return nil }
      return LcpErrors.map(publication.protectionError)
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    guard let channel = engineChannel else { return }
    Self.channels.removeAll { $0 === channel }
    engineChannel = nil
    Task { @MainActor in PendingPassphrases.cancel(channel) }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(Self.didRegisterWithCore)
    case "acquirePublication":
      acquirePublication(call.arguments as? [String: Any], result)
    case "getLicenseInfo":
      getLicenseInfo(call.arguments as? [String: Any], result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Acquisition and license info

  /// The one `LCPService`, shared by core's content protection, acquisition and license info. It has
  /// its own HTTP client, so LCP servers never see the headers the app sets for core's requests.
  private static var cachedServices: (service: LCPService, assetRetriever: AssetRetriever)?

  private static func services() -> (service: LCPService, assetRetriever: AssetRetriever)? {
    if let cachedServices { return cachedServices }
    guard let client = lcpClient else { return nil }
    let httpClient = DefaultHTTPClient()
    let assetRetriever = AssetRetriever(httpClient: httpClient)
    let service = LCPService(
      client: client,
      licenseRepository: LCPKeychainLicenseRepository(),
      passphraseRepository: LCPKeychainPassphraseRepository(),
      assetRetriever: assetRetriever,
      httpClient: httpClient
    )
    cachedServices = (service, assetRetriever)
    return cachedServices
  }

  /// Folder inside Application Support that holds acquired publications.
  private static func acquiredDirectory() throws -> URL {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let dir = support.appendingPathComponent("flutter_readium_lcp/acquired", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func acquirePublication(_ args: [String: Any]?, _ result: @escaping FlutterResult) {
    guard let path = args?["lcplPath"] as? String, let lcpl = FileURL(path: path, isDirectory: false),
      let service = Self.services()?.service
    else {
      result(FlutterError(code: "lcpError", message: "LCP is unavailable or the license path is invalid.", details: nil))
      return
    }
    let progressId = args?["progressId"] as? Int
    Task { @MainActor in
      var lastPercent = -1
      let acquired = await service.acquirePublication(from: .file(lcpl)) { progress in
        guard let progressId, case .percent(let fraction) = progress else { return }
        let percent = Int(fraction * 100)
        guard percent != lastPercent else { return }
        lastPercent = percent
        DispatchQueue.main.async {
          self.engineChannel?.invokeMethod(
            "acquisitionProgress", arguments: ["id": progressId, "progress": Double(fraction)])
        }
      }
      switch acquired {
      case .failure(let error):
        result(LcpErrors.flutterError(error))
      case .success(let publication):
        // Already gone after a successful move.
        defer { try? FileManager.default.removeItem(at: publication.localURL.url) }
        do {
          result(try Self.moveToAcquiredDirectory(publication))
        } catch is AcquiredPathError {
          result(LcpErrors.flutterError(LCPError.parsing(.licenseDocument)))
        } catch {
          log.error("Could not move the acquired publication: \(error)")
          result(FlutterError(code: "lcpError", message: "Could not store the acquired publication.", details: nil))
        }
      }
    }
  }

  private static func moveToAcquiredDirectory(_ publication: LCPAcquiredPublication) throws -> [String: Any] {
    let directory = try acquiredDirectory().standardizedFileURL.resolvingSymlinksInPath()
    let target = directory.appendingPathComponent(publication.suggestedFilename).standardizedFileURL
    // The file name comes from the license id, which the license document controls.
    guard target.deletingLastPathComponent().path == directory.path else { throw AcquiredPathError() }
    if FileManager.default.fileExists(atPath: target.path) {
      try FileManager.default.removeItem(at: target)
    }
    try FileManager.default.moveItem(at: publication.localURL.url, to: target)
    var wire: [String: Any] = [
      "path": target.path,
      "fileName": publication.suggestedFilename,
      "licenseId": publication.licenseDocument.id,
    ]
    if let mediaType = publication.format.mediaType?.string { wire["mediaType"] = mediaType }
    if let fileExtension = publication.format.fileExtension?.rawValue { wire["fileExtension"] = fileExtension }
    return wire
  }

  /// Opens the license of the publication at `args["path"]` and runs `body` with it. Fails `result` when
  /// the license cannot be opened.
  private func withLicense(
    _ args: [String: Any]?, _ result: @escaping FlutterResult, _ body: @escaping @MainActor (LCPLicense) async -> Void
  ) {
    guard let path = args?["path"] as? String, let url = FileURL(path: path, isDirectory: false),
      let (service, assetRetriever) = Self.services()
    else {
      result(FlutterError(code: "lcpError", message: "LCP is unavailable or the path is invalid.", details: nil))
      return
    }
    Task { @MainActor in
      switch await assetRetriever.retrieve(url: url) {
      case .failure(let error):
        result(LcpErrors.flutterError(error))
      case .success(let asset):
        let license = await service.retrieveLicense(
          from: asset, authentication: DartAuthentication(), allowUserInteraction: true, sender: nil)
        switch license {
        case .failure(let error):
          result(LcpErrors.flutterError(error))
        case .success(let license):
          // Like Android, whose retrieval fails for a restricted license (expired, returned, revoked).
          if let error = license.error {
            result(LcpErrors.flutterError(error))
          } else {
            await body(license)
          }
        }
      }
    }
  }

  private func getLicenseInfo(_ args: [String: Any]?, _ result: @escaping FlutterResult) {
    withLicense(args, result) { license in result(await Self.licenseInfo(license)) }
  }

  private static func licenseInfo(_ license: LCPLicense) async -> [String: Any] {
    let document = license.license
    var wire: [String: Any] = [
      "licenseId": document.id,
      "provider": document.provider,
      "issued": iso(document.issued),
      "updated": iso(document.updated),
    ]
    wire["rightsStart"] = document.rights.start.map(iso)
    wire["rightsEnd"] = document.rights.end.map(iso)
    wire["copyLimit"] = document.rights.copy
    wire["printLimit"] = document.rights.print
    wire["charactersToCopyLeft"] = await license.charactersToCopyLeft()
    wire["pagesToPrintLeft"] = await license.pagesToPrintLeft()
    if let status = license.status {
      wire["state"] = status.status.rawValue
      wire["statusMessage"] = status.message
      wire["statusUpdated"] = iso(status.updated)
    }
    return wire
  }
}

/// The toolkit's suggested file name would land outside the acquired directory.
private struct AcquiredPathError: Error {}

/// Asks Dart for the passphrase. A nil result (cancel, no provider, no engine) makes the toolkit give up.
private struct DartAuthentication: LCPAuthenticating {
  @MainActor
  func retrievePassphrase(
    for license: LCPAuthenticatedLicense,
    reason: LCPAuthenticationReason,
    allowUserInteraction: Bool,
    sender: Any?
  ) async -> String? {
    guard allowUserInteraction, let channel = FlutterReadiumLcpPlugin.channel else { return nil }
    let args: [String: Any?] = [
      "reason": reason == .invalidPassphrase ? "invalid" : "notFound",
      "hint": license.hint,
      "hintUrl": license.hintLink?.href,
      "provider": license.provider,
      "licenseId": license.document.id,
    ]
    return await PendingPassphrases.ask(channel: channel, arguments: args)
  }
}

/// Passphrase requests waiting for Dart. Each one is resumed exactly once: by Dart's answer, or with
/// nil when its engine detaches, so a request never hangs on an engine that no longer answers.
@MainActor
private enum PendingPassphrases {
  private static var pending: [UUID: (channel: FlutterMethodChannel, continuation: CheckedContinuation<String?, Never>)] = [:]

  static func ask(channel: FlutterMethodChannel, arguments: [String: Any?]) async -> String? {
    await withCheckedContinuation { continuation in
      let id = UUID()
      pending[id] = (channel, continuation)
      channel.invokeMethod("requestPassphrase", arguments: arguments) { result in
        Task { @MainActor in finish(id, result as? String) }
      }
    }
  }

  /// Resumes every request still waiting on `channel`'s engine with nil.
  static func cancel(_ channel: FlutterMethodChannel) {
    for (id, request) in pending where request.channel === channel {
      finish(id, nil)
    }
  }

  private static func finish(_ id: UUID, _ value: String?) {
    pending.removeValue(forKey: id)?.continuation.resume(returning: value)
  }
}
