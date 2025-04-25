#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_readium.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_readium'
  s.version          = '0.0.1'
  s.summary          = 'Flutter Readium'
  s.description      = <<-DESC
  A Flutter wrapper for Readium swift-toolkit.
                       DESC
  s.homepage         = 'https://nota.dk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Nota' => 'nota@nota.dk' }
  s.source           = { :http => 'https://github.com/readium/podspecs' }
  # s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'PromiseKit'
  s.dependency 'ReadiumShared', '~> 3.2.0'
  s.dependency 'ReadiumStreamer', '~> 3.2.0'
  s.dependency 'ReadiumNavigator', '~> 3.2.0'
  s.dependency 'ReadiumOPDS', '~> 3.2.0'
  s.dependency 'ReadiumAdapterGCDWebServer', '~> 3.2.0'
  # s.dependency 'ReadiumLCP', '~> 3.2.0'

  s.platform = :ios, '13.4'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.8.1'
end
