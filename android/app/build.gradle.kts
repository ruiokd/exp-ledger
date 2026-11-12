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

    // 固定签名。
    // CI 的 runner 每次都是干净环境，临时生成的 debug keystore 每次都不同，
    // 结果就是每次构建签名都变，用户只能卸载重装——这是 v1.0.0 到 v1.0.1
    // 装不上去的真实原因。把 keystore 放进仓库，签名从此稳定。
    // 注意：这是标准 debug key，不是发布密钥，别拿去上架。
    signingConfigs {
        create("selfUse") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    defaultConfig {
        applicationId = "com.yg.ledger"
        minSdk = 23
        targetSdk = 34
        versionCode = 2
        versionName = "1.0.1"
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("selfUse")
        }
        release {
            // 自用分发：用上面固定的 keystore，保证可覆盖升级。
            signingConfig = signingConfigs.getByName("selfUse")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
