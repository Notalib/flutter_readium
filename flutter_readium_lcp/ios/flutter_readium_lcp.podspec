#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_readium_lcp.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_readium_lcp'
  s.version          = '0.0.1'
  s.summary          = 'Readium LCP add-on for flutter_readium.'
  s.description      = <<-DESC
Opens LCP-protected publications through flutter_readium. The app supplies EDRLab's LCP client.
                       DESC
  s.homepage         = 'http://github.com/notalib/flutter_readium'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Nota' => 'tech-contact@nota.dk' }
  s.source           = { :http => 'https://github.com/readium/podspecs' }
  s.source_files     = 'flutter_readium_lcp/Sources/flutter_readium_lcp/**/*.swift'
  s.dependency 'Flutter'
  s.dependency 'flutter_readium'
  s.dependency 'ReadiumShared', '~> 3.11.1'
  s.dependency 'ReadiumLCP', '~> 3.11.1'

  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
