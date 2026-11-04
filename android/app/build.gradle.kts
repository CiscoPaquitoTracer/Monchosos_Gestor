import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release: android/key.properties (ignorado) apunta a la llave monchosos-release.jks.
// En Jenkins se genera desde las credenciales. Debe ser SIEMPRE la misma llave que la app Kotlin,
// o los teléfonos no aceptan la actualización.
val llaveProps = Properties().apply {
    val archivo = rootProject.file("key.properties")
    if (archivo.exists()) archivo.inputStream().use { load(it) }
}
val hayLlave = llaveProps.getProperty("storeFile") != null

android {
    namespace = "com.monchosos.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications usa APIs de Java 8+ (java.time) en Android viejos.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Mismo id que la app Kotlin: así la versión Flutter se instala encima como actualización.
        applicationId = "com.monchosos.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayLlave) {
            create("release") {
                storeFile = file(llaveProps.getProperty("storeFile"))
                storePassword = llaveProps.getProperty("storePassword")
                keyAlias = llaveProps.getProperty("keyAlias")
                keyPassword = llaveProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Sin key.properties se firma con la llave debug para que `flutter run --release` funcione
            // en local. Ese APK NO sirve para actualizar la app instalada.
            signingConfig = if (hayLlave) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
