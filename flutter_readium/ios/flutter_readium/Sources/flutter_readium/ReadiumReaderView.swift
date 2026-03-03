import ReadiumNavigator
import ReadiumAdapterGCDWebServer
import ReadiumShared
import Flutter
import UIKit
import WebKit

private let TAG = "ReadiumReaderView"
private let ReadiumReaderStatusReady = "ready"
private let ReadiumReaderStatusLoading = "loading"
private let ReadiumReaderStatusClosed = "closed"
private let ReadiumReaderStatusError = "error"

let readiumReaderViewType = "dk.nota.flutter_readium/ReadiumReaderWidget"

class ReadiumBugLogger: ReadiumShared.WarningLogger {
  func log(_ warning: Warning) {
    print(TAG, "Error in Readium: \(warning)")
  }
}

private let readiumBugLogger = ReadiumBugLogger()
private var userScripts: [WKUserScript] = []
private let jsonEncoder = JSONEncoder()

private func emitReaderStatusChanged(status: String) {
  let jsonData = try! jsonEncoder.encode(status)
  if let jsonStsring = String(data: jsonData, encoding: .utf8){
    FlutterReadiumPlugin.instance?.readerStatusStreamHandler?.sendEvent(jsonStsring)
  }
}

public class ReadiumReaderView: NSObject, FlutterPlatformView, EPUBNavigatorDelegate, VisualNavigatorDelegate {

  private let channel: ReadiumReaderChannel
  private let _view: UIView
  private let readiumViewController: EPUBNavigatorViewController
  private var hasSentReady = false

  var publicationIdentifier: String?

  public func view() -> UIView {
    print(TAG, "::getView")
    return _view
  }

  deinit {
    print(TAG, "::dispose")
    readiumViewController.view.removeFromSuperview()
    readiumViewController.delegate = nil
    channel.setMethodCallHandler(nil)
    FlutterReadiumPlugin.instance?.setCurrentReadiumReaderView(nil)
  }

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
    registrar: FlutterPluginRegistrar
  ) {
    print(TAG, "::init")
    let creationParams = args as! Dictionary<String, Any?>

    let publication = FlutterReadiumPlugin.instance!.getCurrentPublication()!

    let preferencesMap = creationParams["preferences"] as? Dictionary<String, String>?
    let defaultPreferences = preferencesMap == nil ? nil : EPUBPreferences.init(fromMap: preferencesMap!!)

    let locatorStr = creationParams["initialLocator"] as? String
    let locator = locatorStr == nil ? nil : try! Locator.init(jsonString: locatorStr!)
    print(TAG, "publication = \(publication)")

    channel = ReadiumReaderChannel(
      name: "\(readiumReaderViewType):\(viewId)", binaryMessenger: registrar.messenger())

    emitReaderStatusChanged(status: ReadiumReaderStatusLoading)

    print(TAG, "Publication: (identifier=\(String(describing: publication.metadata.identifier)),title=\(String(describing: publication.metadata.title)))")
    print(TAG, "Added publication at \(String(describing: publication.baseURL))")

    // Remove undocumented Readium default 20dp or 44dp top/bottom padding.
    // See EPUBNavigatorViewController.swift in r2-navigator-swift.
    var config = EPUBNavigatorViewController.Configuration()
    config.contentInset = [
      .compact: (top: 0, bottom: 0),
      .regular: (top: 0, bottom: 0),
    ]
    // TODO: Make this config configurable from Flutter
    // Might want it to be higher for a local publication than remote. Default is 2 previous and 6 next resources.
    config.preloadPreviousPositionCount = 2
    config.preloadNextPositionCount = 4
    config.debugState = true

    // TODO: Use experimentalPositioning for now. It places highlights on z-index -1 behind text, instead of in-front.
    config.decorationTemplates = HTMLDecorationTemplate.defaultTemplates(alpha: 1.0, experimentalPositioning: true)

    // TODO: This is a PoC for adding custom editing actions, like user highlights. It should be configurable from Flutter.
    config.editingActions = [.lookup, .translate, EditingAction(title: "Custom Highlight Action", action: #selector(onCustomEditingAction))]

    if (defaultPreferences != nil) {
      config.preferences = defaultPreferences!
    }

    readiumViewController = try! EPUBNavigatorViewController(
      publication: publication,
      initialLocation: locator,
      config: config,
      httpServer: sharedReadium.httpServer!
    )

    if userScripts.isEmpty {
      initUserScripts(registrar: registrar)
    }

    _view = UIView()
    super.init()

    channel.setMethodCallHandler(onMethodCall)
    readiumViewController.delegate = self

    let child: UIView = readiumViewController.view
    let view = _view
    view.addSubview(readiumViewController.view)

    child.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate(
      [
        child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        child.topAnchor.constraint(equalTo: view.topAnchor),
        child.bottomAnchor.constraint(equalTo: view.bottomAnchor)
      ]
    )

    FlutterReadiumPlugin.instance?.setCurrentReadiumReaderView(self)
    publicationIdentifier = publication.metadata.identifier

    /// This adapter will automatically turn pages when the user taps the
    /// screen edges or press arrow keys.
    ///
    /// Bind it to the navigator before adding your own observers to prevent
    /// triggering your actions when turning pages.
    DirectionalNavigationAdapter(
        pointerPolicy: .init(types: [.mouse, .touch])
    ).bind(to: readiumViewController)

    print(TAG, "::init success")
  }

  @objc public func onCustomEditingAction() {
    print(TAG, "EditingAction::NOTA")
    // NOTE: This method will not actually be hit. It will try to find an "onCustomEditingAction" function in the Responder chain!
    // Because of how Flutter generates its responder chain, we need to implement this func in the client AppDelegate.swift and then call the plugin again.
    // see https://github.com/readium/swift-toolkit/issues/466

    if let selection = readiumViewController.currentSelection {
      let selectionLocator = selection.locator
      readiumViewController.apply(decorations: [Decoration(id: "highlight", locator: selectionLocator, style: .highlight(), userInfo: [:])], in: "user-highlight")
      readiumViewController.clearSelection()
    }
  }

  // override EPUBNavigatorDelegate::navigator:setupUserScripts
  public func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
    print(TAG, "setupUserScripts: adding \(userScripts.count) scripts")
    for script in userScripts {
      userContentController.addUserScript(script)
    }
  }

  // override EPUBNavigatorDelegate::middleTapHandler
  func middleTapHandler() {
  }

  public func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
    // All margin & safe-area is handled on the Flutter side.
    return .init(top: 0, left: 0, bottom: 0, right: 0)
  }

  // override EPUBNavigatorDelegate::navigator:presentError
  public func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
    print(TAG, "presentError: \(error)")
  }

  // override EPUBNavigatorDelegate::navigator:didFailToLoadResourceAt
  public func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
    print(TAG, "didFailToLoadResourceAt: \(href). err: \(error)")

    // TODO: Should we send resource-load error like this?
    emitReaderStatusChanged(status: ReadiumReaderStatusError)

    let error = FlutterReadiumError(message: error.localizedDescription, code: "DidFailToLoadResource", data: href.string)
    FlutterReadiumPlugin.instance?.errorStreamHandler?.sendEvent(error)
  }

  // override NavigatorDelegate::navigator:locationDidChange
  public func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    print(TAG, "onPageChanged: \(locator)")
    if (!hasSentReady) {
      emitReaderStatusChanged(status: ReadiumReaderStatusReady)
      hasSentReady = true
    }
    emitOnPageChanged(locator: locator)
  }

  public func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
      print(TAG, "skipped non-http external URL: \(url)")
      return
    }
    emitOnExternalLinkActivated(url: url)
  }

  func applyDecorations(_ decorations: [Decoration], forGroup groupIdentifier: String) {
    print(TAG, "onMethodApplyDecorations: \(decorations) identifier: \(groupIdentifier)")
    self.readiumViewController.apply(decorations: decorations, in: groupIdentifier)
  }

  func getFirstVisibleLocator() async -> Locator? {
    return await self.readiumViewController.firstVisibleElementLocator()
  }

  func getCurrentLocation() -> Locator? {
    return self.readiumViewController.currentLocation
  }

  func getCurrentSelection() -> Locator? {
    return self.readiumViewController.currentSelection?.locator
  }

  private func evaluateJavascript(_ code: String) async -> Result<Any, Error> {
    return await self.readiumViewController.evaluateJavaScript(code)
  }

  private func evaluateJSReturnResult(_ code: String, result: @escaping FlutterResult) {
    Task.detached(priority: .high) {
      do {
        let data = try await self.evaluateJavascript(code).get()
        print(TAG, "evaluateJSReturnResult result: \(data)")
        await MainActor.run() {
          return result(data)
        }
      } catch (let err) {
        print(TAG, "evaluateJSReturnResult error: \(err)")
        await MainActor.run() {
          return result(nil)
        }
      }
    }
  }

  private func setUserPreferences(preferences: EPUBPreferences) {
    self.readiumViewController.submitPreferences(preferences)
  }

  private func emitOnPageChanged(locator: Locator) -> Void {
    print(TAG, "emitOnPageChanged:locator=\(String(describing: locator))")

    Task.detached(priority: .high) { [locator] in

      // Map the ToC location into the locator.
      var resultLocator = (try? await FlutterReadiumPlugin.instance?.epubFindCurrentToc(locator: locator)) ?? locator
      // Get information about current page.
      if let pageInfo = await self.getPageInformation() {
        resultLocator.locations.otherLocations.merge(pageInfo.otherLocations, uniquingKeysWith: { lhs, rhs in lhs })
      }

      let finalLocator = resultLocator
      await MainActor.run() {
        self.channel.onPageChanged(locator: finalLocator)
        FlutterReadiumPlugin.instance?.textLocatorStreamHandler?
          .sendEvent(finalLocator.jsonString)
      }
    }
  }

  private func emitOnExternalLinkActivated(url: URL) {
    print(TAG, "emitOnExternalLinkActivated: \(url)")
    Task.detached(priority: .high) {
      await MainActor.run() {
        self.channel.onExternalLinkActivated(url: url)
      }
    }
  }

  internal func getPageInformation() async -> PageInformation? {
    switch await self.evaluateJavascript("window.epubPage.getPageInformation();") {
    case .success(let jresult):
      let pageInfo = PageInformation.fromJson(jresult as? Dictionary<String, Any> ?? Dictionary())
      return pageInfo
    case .failure(let err):
      print(TAG, "getPageInformation failed! \(err)")
      return nil
    }
  }

  func goToLocator(locator: Locator, animated: Bool) async -> Void {
    let readiumViewController = self.readiumViewController

    let goToSuccees = await readiumViewController.go(to: locator, options: NavigatorGoOptions(animated: animated))
    //self.emitOnPageChanged()
  }

  func justGoToLocator(_ locator: Locator, animated: Bool) async -> Bool {
    return await readiumViewController.go(to: locator, options: NavigatorGoOptions(animated: animated))
  }

  private func emitOnPageChanged() {
    guard let locator = readiumViewController.currentLocation else {
      print(TAG, "emitOnPageChanged: currentLocation = nil!")
      return
    }

    print(TAG, "emitOnPageChanged: Calling navigator:locationDidChange.")
    navigator(readiumViewController, locationDidChange: locator)
  }

  func onMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "go":
      let args = call.arguments as! [Any?]
      print(TAG, "onMethodCall[go] locator = \(args[0] as! String)")
      let locator = try! Locator(jsonString: args[0] as! String, warnings: readiumBugLogger)!
      let animated = args[1] as! Bool
      let isAudioBookWithText = args[2] as? Bool ?? false

      Task.detached(priority: .high) {
        await self.goToLocator(locator: locator, animated: animated)
        await MainActor.run() {
          result(true)
        }
      }
      break
    case "goLeft":
      let animated = call.arguments as! Bool
      let readiumViewController = self.readiumViewController

      Task.detached(priority: .high) {
        let success = await readiumViewController.goLeft(options: NavigatorGoOptions(animated: animated))
        await MainActor.run() {
          result(success)
        }
      }
      break
    case "goRight":
      let animated = call.arguments as! Bool
      let readiumViewController = self.readiumViewController

      Task.detached(priority: .high) {
        let success = await readiumViewController.goRight(options: NavigatorGoOptions(animated: animated))
        await MainActor.run() {
          result(success)
        }
      }
      break
    case "setPreferences":
      let args = call.arguments as! [String: String]
      print(TAG, "onMethodCall[setPreferences] args = \(args)")
      let preferences = EPUBPreferences.init(fromMap: args)
      setUserPreferences(preferences: preferences)
      break
    case "applyDecorations":
      let args = call.arguments as! [Any?]
      let identifier = args[0] as! String
      let decorationsStr = args[1] as! [String]

      guard let decorations = try? decorationsStr.map({ try Decoration(fromJson: $0) }) else {
        return result(FlutterError.init(
          code: "JSON mapping error",
          message: "Could not map decorations from JSON: \(decorationsStr)",
          details: nil))
      }

      print(TAG, "onMethodCall[setPreferences] args = \(args)")
      applyDecorations(decorations, forGroup: identifier)
      break
    case "dispose":
      print(TAG, "Disposing readiumViewController")
      readiumViewController.view.removeFromSuperview()
      readiumViewController.delegate = nil
      emitReaderStatusChanged(status: ReadiumReaderStatusClosed)
      result(nil)
      break
    default:
      print(TAG, "Unhandled call \(call.method)")
      result(FlutterMethodNotImplemented)
      break
    }
  }
}

func initUserScripts(registrar: FlutterPluginRegistrar) {
  let comicJsKey = registrar.lookupKey(forAsset: "assets/helpers/comics.js", fromPackage: "flutter_readium")
  let comicCssKey = registrar.lookupKey(forAsset: "assets/helpers/comics.css", fromPackage: "flutter_readium")
  let epubJsKey = registrar.lookupKey(forAsset: "assets/helpers/epub.js", fromPackage: "flutter_readium")
  let epubCssKey = registrar.lookupKey(forAsset: "assets/helpers/epub.css", fromPackage: "flutter_readium")
  let jsScripts = [comicJsKey, epubJsKey].map { sourceFile -> String in
    let path = Bundle.main.path(forResource: sourceFile, ofType: nil)!
    let data = FileManager().contents(atPath: path)!
    return String(data: data, encoding: .utf8)!
  }
  let addCssScripts = [comicCssKey, epubCssKey].map { sourceFile -> String in
    let path = Bundle.main.path(forResource: sourceFile, ofType: nil)!
    let data = FileManager().contents(atPath: path)!.base64EncodedString()
    return """
      (function() {
      var parent = document.getElementsByTagName('head').item(0);
      var style = document.createElement('style');
      style.type = 'text/css';
      style.innerHTML = window.atob('\(data)');
      parent.appendChild(style)})();
    """
  }
  /// Add JS scripts right away, before loading the rest of the document.
  for jsScript in jsScripts {
    userScripts.append(WKUserScript(source: jsScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
  }
  /// Add css injection scripts after primary document finished loading.
  for addCssScript in addCssScripts {
    userScripts.append(WKUserScript(source: addCssScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
  }
  /// Add simple script used by our JS to detect OS
  userScripts.append(WKUserScript(source: "const isAndroid=false,isIos=true;", injectionTime: .atDocumentStart, forMainFrameOnly: false))
}
