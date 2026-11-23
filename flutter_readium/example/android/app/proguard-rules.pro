# The readium-lcp toolkit finds the LCP client library by reflection, so R8 must not rename or strip
# it. In an app with EDRLab's liblcp the same rule applies to that library. The example's test
# client lives in the same package.
-keep class org.readium.lcp.sdk.** { *; }
