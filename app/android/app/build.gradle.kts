plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.solenstay.app"
    // url_launcher가 끌어오는 androidx.browser 1.9.0 이 compileSdk 36 을 요구
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.solenstay.app"
        minSdk = flutter.minSdkVersion
        multiDexEnabled = true
        targetSdk = 34
        // pubspec.yaml의 version 필드 한 곳만 바꾸면 됨 (예: 0.1.1+2)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // debug 키로 서명 (별도 release 키스토어 미사용).
            // 같은 PC에서 빌드하면 업데이트 덮어쓰기됩니다.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
