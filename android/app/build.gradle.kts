import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = if (rootProject.file("key.properties").exists()) {
    rootProject.file("key.properties")
} else {
    file("key.properties")
}
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.muchovi.flylog"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            val keyPath = keystoreProperties.getProperty("storeFile") ?: "flylog-release.jks"
            val keyFile = when {
                file(keyPath).exists() -> file(keyPath)
                rootProject.file(keyPath).exists() -> rootProject.file(keyPath)
                rootProject.file("app/$keyPath").exists() -> rootProject.file("app/$keyPath")
                else -> file("flylog-release.jks")
            }
            storeFile = keyFile
            storePassword = keystoreProperties.getProperty("storePassword") ?: "flylog2026"
            keyAlias = keystoreProperties.getProperty("keyAlias") ?: "flylog"
            keyPassword = keystoreProperties.getProperty("keyPassword") ?: "flylog2026"
        }
    }

    defaultConfig {
        applicationId = "com.muchovi.flylog"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
