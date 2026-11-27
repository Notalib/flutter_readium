plugins {
  id("com.android.application")
  // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
  id("dev.flutter.flutter-gradle-plugin")
}

android {
  namespace = "com.example.flutter_readium_example"
  compileSdk = maxOf(flutter.compileSdkVersion, 37)
  ndkVersion = flutter.ndkVersion

  compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_18
    targetCompatibility = JavaVersion.VERSION_18
  }

  kotlin {
    compilerOptions {
      jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_18
    }
  }

  defaultConfig {
    applicationId = "com.example.flutter_readium_example"
    // You can update the following values to match your application needs.
    // For more information, see: https://flutter.dev/to/review-gradle-config.
    minSdk = 24
    targetSdk = flutter.targetSdkVersion
    ndkVersion = flutter.ndkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
  }

  buildTypes {
    release {
      // Signing with the debug keys for now, so `flutter run --release` works.
      signingConfig = signingConfigs.getByName("debug")
    }
  }

  buildFeatures {
    buildConfig = true
  }
}

flutter {
  source = "../.."
}

dependencies {
  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

// Keep direct flutter run/test builds from packaging an incomplete native reader.
val checkNativeHelpers by tasks.registering(Exec::class) {
  commandLine("bash", rootProject.file("../../../bin/check_native_helpers").absolutePath)
}

tasks.named("preBuild") {
  dependsOn(checkNativeHelpers)
}
