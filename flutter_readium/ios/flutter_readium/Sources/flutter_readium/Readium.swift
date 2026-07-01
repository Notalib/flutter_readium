//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer
import UIKit

#if LCP
import R2LCPClient
import ReadiumAdapterLCPSQLite
import ReadiumLCP
#endif

let sharedReadium = Readium(withHeaders: nil)

final class Readium : DefaultHTTPClientDelegate {

  init(withHeaders headers: [String: String]?) {
    self.setupWithHeaders(headers: headers)
  }

  lazy var httpClient: HTTPClient? = nil
  lazy var formatSniffer: FormatSniffer = DefaultFormatSniffer()
  lazy var assetRetriever: AssetRetriever? = nil
  lazy var publicationOpener: PublicationOpener? = nil
  var additionalHeaders = Dictionary<String, String>()
  /// Sanitised User-Agent applied to every outgoing request. Captured here so
  /// that `willStartRequest` can stamp it onto the HTTPRequest's headers dict
  /// (otherwise the UA is only added downstream by `startTask` / URLSession
  /// and our request-log shows misleading `headers=[:]`).
  private var userAgent: String = ""

  func setupWithHeaders(headers: [String: String]?) {
    let userAgent = "FlutterReadium"
    self.userAgent = userAgent
    // Put User-Agent on URLSessionConfiguration.httpAdditionalHeaders so it
    // applies to *every* CFNetwork-level request — including any retry/redirect/
    // background fetch that may not go through our `willStartRequest` delegate.
    // Without this, CFNetwork falls back to a UA synthesised from CFBundleName.
    var sessionHeaders: [String: String] = headers ?? [:]
    sessionHeaders["User-Agent"] = userAgent
    self.httpClient = DefaultHTTPClient(
      userAgent: userAgent,
      cachePolicy: .useProtocolCachePolicy, // default = useProtocolCachePolicy
      additionalHeaders: sessionHeaders,
      requestTimeout: 20.0,   // default = 60 seconds
      resourceTimeout: 300.0, // default = 7 days
      delegate: self)
    self.assetRetriever = AssetRetriever(httpClient: self.httpClient!)
    self.publicationOpener = PublicationOpener(
      parser: DefaultPublicationParser(
        httpClient: httpClient!,
        assetRetriever: assetRetriever!,
        pdfFactory: DefaultPDFDocumentFactory()
      ),
      contentProtections: contentProtections,
    )
  }

  func setAdditionalHeaders(_ headers: [String: String]) -> Void {
    // Sanitise host-app-supplied headers the same way we sanitise our own
    // User-Agent: fold diacritics, strip non-ASCII / control / DEL, and drop
    // entries that end up empty. Some servers (notably ASP.NET Core) will
    // silently drop or fail requests when header values contain
    // non-ASCII bytes or stray CR/LF — we'd rather log a warning and ship a
    // clean header than have the request stall.
    var sanitized: [String: String] = [:]
    for (key, value) in headers {
      let cleanValue = sanitizeHeaderValue(value)
      if cleanValue != value {
        Log.readium.warn("setAdditionalHeaders: sanitised header '\(key)' (stripped non-ASCII/control chars)")
      }
      guard !cleanValue.isEmpty else {
        Log.readium.warn("setAdditionalHeaders: dropping header '\(key)' — empty after sanitisation")
        continue
      }
      sanitized[key] = cleanValue
    }
    self.additionalHeaders = sanitized
  }

  private func makeSanitizedUserAgent() -> String {
    let bundle = Bundle.main

    let rawName = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "App"
    ///FIX: Below line revealed characters not compatible with some server's header parsing. We now sanitize it.
    //debugPrint(rawName.unicodeScalars.map { String(format: "%04X", $0.value) })
    let appName = sanitizeHeaderValue(rawName).replacingOccurrences(of: " ", with: "")

    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"

    let system = UIDevice.current.systemVersion
    let device = UIDevice.current.model

    return "\(appName)/\(version) (\(build); iOS \(system); \(device))"
  }

  /// Returns `input` with diacritics folded and non-ASCII / control / DEL
  /// characters stripped. Safe to use for any HTTP header value where the
  /// receiving server may be intolerant of non-ASCII bytes (e.g. ASP.NET Core
  /// silently drops requests with non-ASCII UA). Also defends against header
  /// injection because CR/LF/NUL fall in the control range and get dropped.
  private func sanitizeHeaderValue(_ input: String) -> String {
    let decomposed = input.folding(options: .diacriticInsensitive, locale: .current)

    let asciiOnly = decomposed.unicodeScalars.compactMap { scalar -> Character? in
      guard scalar.isASCII && scalar.value >= 0x20 && scalar.value != 0x7F else {
        return nil
      }
      return Character(scalar)
    }

    return String(asciiOnly)
  }

  //--- MARK: DefaultHTTPClientDelegate

  /// You can modify the `request`, for example by adding additional HTTP headers or redirecting to a different URL,
  /// before calling the `completion` handler with the new request.
  func httpClient(_ httpClient: DefaultHTTPClient, willStartRequest request: HTTPRequest) async -> HTTPResult<HTTPRequestConvertible> {
    var req = request // make a mutable copy
    var merged = additionalHeaders
    for (k, v) in request.headers { merged[k] = v } // per-request wins
    // Stamp the UA explicitly so it's visible in the diagnostic log.
    // Without this, `startTask` (DefaultHTTPClient.swift:206-208) adds it
    // *after* this delegate, and URLSession merges in the session-level
    // `httpAdditionalHeaders["User-Agent"]` even later when building the wire
    // frame — both invisible from here. The on-wire request always carries
    // User-Agent; this just keeps the log honest. `startTask`'s null-check
    // makes its set a no-op when we've already populated it here.
    if merged["User-Agent"] == nil, !userAgent.isEmpty {
      merged["User-Agent"] = userAgent
    }
    req.headers = merged
    // Info-level: method, URL, header keys only (no values — Authorization tokens etc. are sensitive).
    // If a request hangs, its "→" line appears here but no matching "←" line shows up in didReceiveResponse.
    Log.readium.info("HTTPClient → \(req.method.rawValue) \(req.url) headerKeys=\(req.headers.keys.sorted())")
    Log.readium.debug("HTTPClient → \(req.method.rawValue) \(req.url) headers=\(req.headers.debugDescription)")

    // DIAGNOSTIC: kick off a parallel one-off URLSession probe to the same URL.
    //runOneOffProbe(for: req)

    return .success(req)
  }

  func httpClient(_ httpClient: DefaultHTTPClient, request: HTTPRequest, didReceiveResponse response: HTTPResponse) {
    Log.readium.info("HTTPClient ← \(response.status.rawValue) \(request.method.rawValue) \(response.url)")
    Log.readium.debug("HTTPClient ← \(response.status.rawValue) \(request.method.rawValue) \(response.url) headers=\(response.headers.debugDescription)")
  }

  /// Fires a parallel diagnostic GET/HEAD via a freshly-created URLSession.
  /// Does not consume the body or surface the result — just logs PROBE lines so
  /// we can compare its timing/outcome against the shared client's request to
  /// the same URL.
  private func runOneOffProbe(for request: HTTPRequest) {
    let probeURL = request.url.url
    let method = request.method.rawValue
    let ua = self.userAgent
    // Truncate URL in logs.
    let urlPreview: String = {
      let s = probeURL.absoluteString
      return s.count > 160 ? String(s.prefix(120)) + "…(\(s.count) chars)" : s
    }()
    Task.detached(priority: .utility) {
      let config = URLSessionConfiguration.default
      config.timeoutIntervalForRequest = 10
      config.timeoutIntervalForResource = 30
      config.httpAdditionalHeaders = ["User-Agent": ua]
      let session = URLSession(configuration: config)
      defer { session.invalidateAndCancel() }

      var probe = URLRequest(url: probeURL)
      probe.httpMethod = method

      Log.readium.info("HTTPProbe → \(method) \(urlPreview)")
      let start = Date()
      do {
        let (_, response) = try await session.data(for: probe)
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        Log.readium.info("HTTPProbe ← \(status) \(method) in \(elapsedMs)ms (one-off URLSession reached server)")
      } catch {
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        Log.readium.warn("HTTPProbe × \(method) failed in \(elapsedMs)ms: \(error.localizedDescription)")
      }
    }
  }

  //--- MARK: LCP

#if !LCP
  let contentProtections: [ContentProtection] = []

#else
  lazy var contentProtections: [ContentProtection] = [
    lcpService.contentProtection(with: lcpAuthentication),
  ]

  lazy var lcpService = LCPService(
    client: LCPClient(),
    licenseRepository: try! LCPSQLiteLicenseRepository(),
    passphraseRepository: try! LCPSQLitePassphraseRepository(),
    assetRetriever: assetRetriever,
    httpClient: httpClient
  )

  lazy var lcpAuthentication: LCPAuthenticating = LCPDialogAuthentication()

  /// Facade to the private R2LCPClient.framework.
  class LCPClient: ReadiumLCP.LCPClient {
    func createContext(jsonLicense: String, hashedPassphrase: LCPPassphraseHash, pemCrl: String) throws -> LCPClientContext {
      try R2LCPClient.createContext(jsonLicense: jsonLicense, hashedPassphrase: hashedPassphrase, pemCrl: pemCrl)
    }

    func decrypt(data: Data, using context: LCPClientContext) -> Data? {
      R2LCPClient.decrypt(data: data, using: context as! DRMContext)
    }

    func findOneValidPassphrase(jsonLicense: String, hashedPassphrases: [LCPPassphraseHash]) -> LCPPassphraseHash? {
      R2LCPClient.findOneValidPassphrase(jsonLicense: jsonLicense, hashedPassphrases: hashedPassphrases)
    }
  }
#endif

}
