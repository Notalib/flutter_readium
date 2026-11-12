import AVKit
import Flutter
import UIKit

/// Hosts the system `AVRoutePickerView` (AirPlay and other audio outputs) as a Flutter platform view.
class AudioRoutePickerViewFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "dk.nota.flutter_readium/audio-route-picker"

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return AudioRoutePickerPlatformView(frame: frame, arguments: args as? [String: Any])
  }

  // Undocumented, but boilerplate function required for creationParams to not silently become nil!
  // https://github.com/flutter/flutter/issues/28124
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

private class AudioRoutePickerPlatformView: NSObject, FlutterPlatformView {
  private let pickerView: AVRoutePickerView

  init(frame: CGRect, arguments: [String: Any]?) {
    pickerView = AVRoutePickerView(frame: frame)
    super.init()
    pickerView.prioritizesVideoDevices = false
    pickerView.backgroundColor = .clear
    if let tint = Self.color(arguments?["tintColor"]) {
      pickerView.tintColor = tint
    }
    if let activeTint = Self.color(arguments?["activeTintColor"]) {
      pickerView.activeTintColor = activeTint
    }
  }

  func view() -> UIView {
    return pickerView
  }

  /// Decodes an ARGB int sent from Dart's `Color.toARGB32()`.
  private static func color(_ value: Any?) -> UIColor? {
    guard let argb = (value as? NSNumber)?.uint32Value else { return nil }
    return UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }
}
