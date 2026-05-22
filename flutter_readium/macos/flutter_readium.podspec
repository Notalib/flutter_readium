#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_readium.podspec` to validate before publishing.
#
# NOTE: macOS support is planned but not yet implemented. The plugin registers
# on macOS but only handles `getPlatformVersion`; no Readium dependencies are
# pulled in. Once the Swift sources are shared with iOS, this podspec should
# mirror ../ios/flutter_readium.podspec.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_readium'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin wrapper for Readium toolkits.'
  s.description      = <<-DESC
Flutter plugin for reading EPUB, audiobook, and WebPub publications. Wraps the
Readium toolkits on iOS, macOS (planned), Android, and Web.
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
