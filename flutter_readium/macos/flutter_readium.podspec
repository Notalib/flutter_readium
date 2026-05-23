#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_readium.podspec` to validate before publishing.
#
# NOTE: Native macOS desktop (`flutter run -d macos`) is not supported. The plugin
# registers a no-op stub on the Flutter macOS platform channel so apps still compile
# and launch; all calls return FlutterMethodNotImplemented. The upstream
# swift-toolkit declares `platforms: [.iOS("15.0")]` and links UIKit, and upstream
# has marked native macOS support as `not_planned` (see
# https://github.com/readium/swift-toolkit/issues/783).
#
# However, the iOS build of this plugin runs unmodified on Apple Silicon Macs via
# "Designed for iPad" — Apple Silicon Macs can execute iOS .ipa binaries natively,
# and swift-toolkit is maintained with that mode in mind (`#available(macOS …)`
# checks throughout the source). To distribute on Mac App Store, ship the iOS app
# and leave the "Mac App Store: Designed for iPad" checkbox enabled in App Store
# Connect.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_readium'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin wrapper for Readium toolkits.'
  s.description      = <<-DESC
Flutter plugin for reading EPUB, audiobook, and WebPub publications. Wraps the
Readium toolkits on iOS, Android, and Web.
                       DESC
  s.homepage         = 'http://github.com/notalib/flutter_readium'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Nota' => 'tech-contact@nota.dk' }
  s.source           = { :http => 'https://github.com/notalib/flutter_readium' }
  s.source_files     = 'Classes/**/*'

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
