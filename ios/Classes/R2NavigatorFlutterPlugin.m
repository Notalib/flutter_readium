#import "R2NavigatorFlutterPlugin.h"
#if __has_include(<flutter_readium/flutter_readium-Swift.h>)
#import <flutter_readium/flutter_readium-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "flutter_readium-Swift.h"
#endif

@implementation R2NavigatorFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftR2NavigatorFlutterPlugin registerWithRegistrar:registrar];
}
@end
