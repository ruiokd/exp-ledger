plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.yg.ledger"
    compileSdk = 34
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 的 AAR 要求开这个（minSdk < 26 时用于
        // 把 java.time 等 API 反向移植）。不开会在 checkReleaseAarMetadata 直接失败。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.yg.ledger"
        minSdk = 23
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            // 本地发布先用 debug 签名；正式分发再换成自己的 keystore。
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
