import ReadiumNavigator
import ReadiumAdapterGCDWebServer
import ReadiumShared
import ReadiumStreamer
import Flutter
import UIKit
import WebKit

private let TAG = "ReadiumReaderView"

let readiumReaderViewType = "dk.nota.flutter_readium/ReadiumReaderWidget"

private let scrollScripts = [
  false: WKUserScript(
    source: "setScrollMode(false);", injectionTime: .atDocumentEnd, forMainFrameOnly: false),
  true: WKUserScript(
    source: "setScrollMode(true);", injectionTime: .atDocumentEnd, forMainFrameOnly: false),
]

class ReadiumReaderView: NSObject, FlutterPlatformView, FlutterStreamHandler, EPUBNavigatorDelegate {

  private let channel: ReadiumReaderChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?
  private let _view: UIView
  private let readiumViewController: EPUBNavigatorViewController
  private let userScript: WKUserScript
  private var isVerticalScroll = false
  private var synthesizer: PublicationSpeechSynthesizer?

  func view() -> UIView {
    print(TAG, "::getView")
    return _view
  }

  deinit {
    print(TAG, "::dispose")
    readiumViewController.view.removeFromSuperview()
    readiumViewController.delegate = nil
    channel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
  }

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
    registrar: FlutterPluginRegistrar
  ) {
    print(TAG, "::init")
    let creationParams = args as! Dictionary<String, Any?>
    let publication = getCurrentPublication()!

    let preferencesStr = creationParams["preferences"] as? Dictionary<String, String>?
    let defaultPreferences = preferencesStr == nil ? nil : EPUBPreferencesHelper.mapToEPUBPreferences(preferencesStr!!)

    let locatorStr = creationParams["initialLocator"] as? String
    let locator = locatorStr == nil ? nil : try! Locator.init(jsonString: locatorStr!)
    print(TAG, "publication = \(publication)")

    channel = ReadiumReaderChannel(
      name: "\(readiumReaderViewType):\(viewId)", binaryMessenger: registrar.messenger())
    eventChannel = FlutterEventChannel(name: "dk.nota.flutter_readium/text-locator", binaryMessenger: registrar.messenger())

    print(TAG, "Publication: (identifier=\(String(describing: publication.metadata.identifier)),title=\(String(describing: publication.metadata.title)))")
    print(TAG, "Added publication at \(String(describing: publication.baseURL))")

    // Remove undocumented Readium default 20dp or 44dp top/bottom padding.
    // See EPUBNavigatorViewController.swift in r2-navigator-swift.
    var config = EPUBNavigatorViewController.Configuration()
    config.contentInset = [
      .compact: (top: 0, bottom: 0),
      .regular: (top: 0, bottom: 0),
    ]
    config.preloadPreviousPositionCount = 1
    config.preloadNextPositionCount = 1
    config.debugState = true
    if (defaultPreferences != nil) {
      config.preferences = defaultPreferences!;
    }

    readiumViewController = try! EPUBNavigatorViewController(
      publication: publication,
      initialLocation: locator,
      config: config,
      httpServer: sharedReadium.httpServer
    )

    let commicJsKey = registrar.lookupKey(forAsset: "assets/helpers/comics.js", fromPackage: "flutter_readium")
    // Add epub.js script for highlighting and things like that.
    let epubJsKey = registrar.lookupKey(forAsset: "assets/helpers/epub.js", fromPackage: "flutter_readium")
    let sourceFiles = [commicJsKey, epubJsKey]
    let source = sourceFiles.map { sourceFile -> String in
      let path = Bundle.main.path(forResource: sourceFile, ofType: nil)!
      let data = FileManager().contents(atPath: path)!
      return String(data: data, encoding: .utf8)!
    }.joined(separator: "\n")
    userScript = WKUserScript(source: "const isAndroid=false,isIos=true;\n" + source, injectionTime: .atDocumentStart, forMainFrameOnly: false)

    _view = UIView()
    super.init()

    channel.setMethodCallHandler(onMethodCall)
    eventChannel.setStreamHandler(self)
    readiumViewController.delegate = self

    let child: UIView = readiumViewController.view  // Must specify type `UIView`, or we end up with an `UIView?` instead…
    let view = _view
    // Set view to match parent, otherwise it ends up bigger than the parent and overflowing.
    // Somehow seems to work even after screen rotation, despite not being called again.
    child.frame = view.bounds
    print(TAG, "Fixed view bounds \(view.bounds)")
    view.addSubview(readiumViewController.view)

    print(TAG, "::init success")
  }

  // override EPUBNavigatorDelegate::navigator:setupUserScripts
  func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
    print(TAG, "setupUserScripts:")
    userContentController.addUserScript(userScript)
  }

  // override EPUBNavigatorDelegate::middleTapHandler
  func middleTapHandler() {
  }

  // override EPUBNavigatorDelegate::navigator:presentError
  func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
    print(TAG, "presentError: \(error)")
  }

  // override EPUBNavigatorDelegate::navigator:didFailToLoadResourceAt
  func navigator(_ navigator: any ReadiumNavigator.Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
    print(TAG, "didFailToLoadResourceAt: \(href). err: \(error)")
  }

  // override NavigatorDelegate::navigator:locationDidChange
  func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    print(TAG, "onPageChanged: \(locator)")
    emitOnPageChanged(locator: locator)
  }

  // override NavigatorDelegate::navigator:didPressKey
  func navigator(_ navigator: VisualNavigator, didPressKey event: KeyEvent) async {
    print(TAG, "didPressKey: \(event)")
    // Turn pages when pressing the arrow keys.
    await DirectionalNavigationAdapter(navigator: navigator).didPressKey(event: event)
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
    isVerticalScroll = preferences.scroll ?? false
    self.readiumViewController.submitPreferences(preferences)
  }

  private func emitOnPageChanged(locator: Locator) -> Void {
    let json = locator.jsonString ?? "null"
    
    print(TAG, "emitOnPageChanged:locator=\(String(describing: locator))")
    
    Task.detached(priority: .high) { [isVerticalScroll] in
      guard let locatorWithFragments = await self.getLocatorFragments(json, isVerticalScroll) else {
        print(TAG, "emitOnPageChanged failed!")
        return
      }
      await MainActor.run() {
        self.channel.onPageChanged(locator: locatorWithFragments)
        if (self.eventSink != nil) {
          self.eventSink!(locatorWithFragments.jsonString)
        }
      }
    }
  }
  
  private func getLocatorFragments(_ locatorJson: String, _ isVerticalScroll: Bool) async -> Locator? {
    switch await self.evaluateJavascript("window.epubPage.getLocatorFragments(\(locatorJson), \(isVerticalScroll));") {
      case .success(let jresult):
        let locatorWithFragments = try! Locator(json: jresult as? Dictionary<String, Any?>, warnings: readiumBugLogger)!
        return locatorWithFragments;
      case .failure(let err):
        print(TAG, "getLocatorFragments failed! \(err)")
        return nil;
      }
  }

  private func scrollTo(locations: Locator.Locations, toStart: Bool) async -> Void {
    let json = locations.jsonString ?? "null"
    print(TAG, "scrollTo: Go to locations \(json), toStart: \(toStart)")

    let _ = await evaluateJavascript("window.epubPage.scrollToLocations(\(json),\(isVerticalScroll),\(toStart));")
  }

  func goToLocator(locator: Locator, animated: Bool) async -> Void {
    let locations = locator.locations
    let shouldScroll = canScroll(locations: locations)
    let shouldGo = readiumViewController.currentLocation?.href != locator.href
    let readiumViewController = self.readiumViewController

    if shouldGo {
      print(TAG, "goToLocator: Go to \(locator.href)")
      let goToSuccees = await readiumViewController.go(to: locator, options: NavigatorGoOptions(animated: false));
      if (goToSuccees && shouldScroll) {
        await self.scrollTo(locations: locations, toStart: false)
        self.emitOnPageChanged()
      }
      // TODO: Check result and actually respond to Flutter with it.
    } else {
      print(TAG, "goToLocator: Already there, Scroll to \(locator.href)")
      if(shouldScroll) {
        await self.scrollTo(locations: locations, toStart: false)
        self.emitOnPageChanged()
      }
    }
  }

  private func setLocation(locator: Locator, isAudioBookWithText: Bool) async -> Result<Any, Error> {
    let json = locator.jsonString ?? "null"

    return await evaluateJavascript("window.epubPage.setLocation(\(json), \(isAudioBookWithText));")
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
        await self.setLocation(locator: locator, isAudioBookWithText: isAudioBookWithText)
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
    case "setLocation":
      let args = call.arguments as! [Any]
      print(TAG, "onMethodCall[setLocation] locator = \(args[0] as! String)")
      let locator = try! Locator(jsonString: args[0] as! String, warnings: readiumBugLogger)!
      let isAudioBookWithText = args[1] as? Bool ?? false
      Task.detached(priority: .high) {
        await self.setLocation(locator: locator, isAudioBookWithText: isAudioBookWithText)
        await MainActor.run() {
          result(true)
        }
      }
      break
    case "getLocatorFragments":
      let args = call.arguments as? String ?? "null"
      Task.detached(priority: .high) {
        do {
          let data = try await self.evaluateJavascript("window.epubPage.getLocatorFragments(\(args), true);").get()
          await MainActor.run() {
            return result(data)
          }
        } catch (let err) {
          print(TAG, "getLocatorFragments error \(err)")
          await MainActor.run() {
            return result(false)
          }
        }
      }
      break
    case "getCurrentLocator":
      let args = call.arguments as? String ?? "null"
      print(TAG, "onMethodCall[currentLocator] args = \(args)")
      Task.detached(priority: .high) { [isVerticalScroll] in
        let json = await self.readiumViewController.currentLocation?.jsonString ?? nil
        if (json == nil) {
          await MainActor.run() {
            return result(nil)
          }
        }
        let data = await self.getLocatorFragments(json!, isVerticalScroll)
        await MainActor.run() {
          return result(data?.jsonString)
        }
      }
      break
    case "isLocatorVisible":
      let args = call.arguments as! String
      print(TAG, "onMethodCall[isLocatorVisible] locator = \(args)")
      let locator = try! Locator(jsonString: args, warnings: readiumBugLogger)!
      if locator.href != self.readiumViewController.currentLocation?.href {
        result(false)
        return
      }
      evaluateJSReturnResult("window.epubPage.isLocatorVisible(\(args));", result: result)
      break
    case "ttsStart":
      self.onMethodTTSStart(call, result: result)
      break
    case "ttsStop":
      self.onMethodTTSStop(call, result: result)
      break
    case "isReaderReady":
      self.evaluateJSReturnResult("""
                (function() {
                    if (typeof window.epubPage !== 'undefined' && typeof window.epubPage.isReaderReady === 'function') {
                        return window.epubPage.isReaderReady();
                    } else {
                        return false;
                    }
                })();
            """, result: result)
      break
    case "setPreferences":
      let args = call.arguments as! [String: String]
      print(TAG, "onMethodCall[setPreferences] args = \(args)")
      let preferences = EPUBPreferencesHelper.mapToEPUBPreferences(args)
      setUserPreferences(preferences: preferences)
      break
    case "dispose":
      print(TAG, "Disposing readiumViewController")
      readiumViewController.view.removeFromSuperview()
      readiumViewController.delegate = nil
      synthesizer?.delegate = nil;
      synthesizer = nil;
      result(nil)
      break
    default:
      print(TAG, "Unhandled call \(call.method)")
      result(FlutterMethodNotImplemented)
      break
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    print(TAG, "onListen: \(String(describing: arguments))")
    self.eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  func onMethodApplyDecorations(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as! [Any?]
    let identifier = args[0] as! String
    let decorations = args[1] as! [Decoration]
    print(TAG, "onMethodApplyDecorations: \(decorations) identifier: \(identifier)")
    self.readiumViewController.apply(decorations: decorations, in: identifier)
    result(true)
  }
}

class ReadiumBugLogger: ReadiumShared.WarningLogger {
  func log(_ warning: Warning) {
    print(TAG, "Error in Readium: \(warning)")
  }
}

private let readiumBugLogger = ReadiumBugLogger()

private func tryType<T>(_ json: T?) throws -> Data? where T: Encodable {
  return json != nil ? try JSONEncoder().encode(json) : nil
}

private func jsonEncode(_ json: Any?) -> String {
  if json == nil {
    return "null"
  }
  let data =
  try! tryType(json as? Bool) ?? tryType(json as? Int) ?? tryType(json as? Double) ?? tryType(
    json as? String) ?? JSONSerialization.data(withJSONObject: json!, options: [])
  return String(data: data, encoding: .utf8)!
}

private func canScroll(locations: Locator.Locations?) -> Bool {
  guard let locations = locations else { return false }
  return locations.domRange != nil || locations.cssSelector != nil || locations.progression != nil
}

/// Extension handling TTS for ReadiumReaderView
extension ReadiumReaderView : PublicationSpeechSynthesizerDelegate {

  func publicationSpeechSynthesizer(_ synthesizer: ReadiumNavigator.PublicationSpeechSynthesizer, stateDidChange state: ReadiumNavigator.PublicationSpeechSynthesizer.State) {
    print(TAG, "publicationSpeechSynthesizerStateDidChange: \(state)")
    var playingUtteranceLocator: Locator? = nil
    var playingRangeLocator: Locator? = nil

    switch state {
    case .playing(let utt, let range):
      playingUtteranceLocator = utt.locator
      playingRangeLocator = range
      if let newLocator = range {
        // TODO: this should likely be throttled somewhat
        // See https://github.com/readium/swift-toolkit/blob/master/docs/Guides/TTS.md#turning-pages-automatically
        Task.detached(priority: .high) {
          await self.goToLocator(locator: newLocator, animated: true)
        }
      }
      print(TAG, "tts playing: \(utt.text) in \(String(describing: utt.language?.locale.identifier))")
      break
    case .paused(let utt):
      playingUtteranceLocator = utt.locator
      print(TAG, "tts paused at: \(utt.text)")
      break
    case .stopped:
      print(TAG, "tts stopped")
      break
    }

    var decorations: [Decoration] = []
    if let locator = playingUtteranceLocator {
        decorations.append(Decoration(
            id: "tts-utterance",
            locator: locator,
            style: .highlight(tint: .blue)
        ))
    }
    if let locator = playingRangeLocator {
        decorations.append(Decoration(
            id: "tts-utterance-range",
            locator: locator,
            style: .underline(tint: .red)
        ))
    }
    self.readiumViewController.apply(decorations: decorations, in: "tts")
  }

  func publicationSpeechSynthesizer(_ synthesizer: ReadiumNavigator.PublicationSpeechSynthesizer, utterance: ReadiumNavigator.PublicationSpeechSynthesizer.Utterance, didFailWithError error: ReadiumNavigator.PublicationSpeechSynthesizer.Error) {
    print(TAG, "publicationSpeechSynthesizerUtteranceDidFail: \(error)")
  }

  func onMethodTTSStart(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as! [Any?]
    let ttsLang = args[0] as! String
    let lang = Language(stringLiteral: ttsLang)
    var locator: Locator? = nil
    if (args[1] is String) {
      locator = try! Locator(jsonString: args[1] as! String, warnings: readiumBugLogger)!
    }

    if (self.synthesizer == nil) {
      self.synthesizer = PublicationSpeechSynthesizer(
        publication: self.readiumViewController.publication,
        config: PublicationSpeechSynthesizer.Configuration(
          defaultLanguage: lang
        )
      )
      self.synthesizer?.delegate = self
    }
    Task.detached(priority: .high) { [self] in
      // If no locator provided, start from current visible element.
      if (locator == nil) {
        locator = await (self.readiumViewController as VisualNavigator).firstVisibleElementLocator()
      }
      await MainActor.run() {
        self.synthesizer?.start(from: locator)
        return result(true)
      }
    }
  }

  func onMethodTTSPause(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    self.synthesizer?.pause()
    result(true)
  }

  func onMethodTTSResume(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    self.synthesizer?.resume()
    result(true)
  }

  func onMethodTTSNext(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    self.synthesizer?.next()
    result(true)
  }

  func onMethodTTSPrevious(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    self.synthesizer?.previous()
    result(true)
  }

  func onMethodTTSTogglePlay(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    self.synthesizer?.pauseOrResume()
    result(true)
  }

  func onMethodTTSStop(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    self.synthesizer?.stop()
    result(true)
  }
}
