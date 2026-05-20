plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.File

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

fun getEnvProperty(key: String): String {
    // 1. Intentar de local.properties
    val prop = localProperties.getProperty(key)
    if (!prop.isNullOrEmpty()) return prop
    
    // 2. Intentar de .env.local
    val envLocalFile = rootProject.file("../.env.local")
    if (envLocalFile.exists()) {
        val lines = envLocalFile.readLines()
        for (line in lines) {
            val trimmed = line.trim()
            if (trimmed.startsWith("#") || trimmed.isEmpty()) continue
            val parts = trimmed.split("=", limit = 2)
            if (parts.size == 2 && parts[0].trim() == key) {
                return parts[1].trim().removeSurrounding("\"").removeSurrounding("'")
            }
        }
    }
    
    // 3. Intentar de .env
    val envFile = rootProject.file("../.env")
    if (envFile.exists()) {
        val lines = envFile.readLines()
        for (line in lines) {
            val trimmed = line.trim()
            if (trimmed.startsWith("#") || trimmed.isEmpty()) continue
            val parts = trimmed.split("=", limit = 2)
            if (parts.size == 2 && parts[0].trim() == key) {
                return parts[1].trim().removeSurrounding("\"").removeSurrounding("'")
            }
        }
    }
    
    // 4. Intentar de variables de entorno del sistema
    val envVar = System.getenv(key)
    if (!envVar.isNullOrEmpty()) return envVar

    return ""
}

val mapsApiKey = getEnvProperty("MAPS_API_KEY").ifEmpty { getEnvProperty("GOOGLE_MAPS_API_KEY") }

android {
    namespace = "mx.edu.tecnm.colima.sinait"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "mx.edu.tecnm.colima.sinait"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["mapsApiKey"] = mapsApiKey
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
