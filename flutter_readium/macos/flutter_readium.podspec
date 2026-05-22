#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_readium.podspec` to validate before publishing.
#
# NOTE: macOS support is NOT implemented and NOT planned. The plugin registers on
# macOS so that apps can compile and launch, but all method calls return
# FlutterMethodNotImplemented. The upstream swift-toolkit is iOS-only; there is no
# macOS Readium navigator available.
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
