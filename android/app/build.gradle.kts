import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.expense_tracker"
    compileSdk = 37
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlin {
        compilerOptions {
            jvmTarget = JvmTarget.JVM_11
        }
    }

    defaultConfig {
        applicationId = "com.example.expense_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    buildToolsVersion = "36.1.0 rc1"

    dependencies {
        implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.4.20")
        implementation("androidx.core:core-ktx:1.19.1")
        implementation("com.squareup.okhttp3:okhttp:5.5.0")
        implementation("com.google.code.gson:gson:2.14.0")
        implementation("androidx.appcompat:appcompat:1.8.0")
        implementation("com.google.android.material:material:1.14.0")
        implementation("androidx.constraintlayout:constraintlayout:2.2.2")
        implementation("com.google.android.gms:play-services-location:21.4.0")
        implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
        implementation("androidx.work:work-runtime-ktx:2.12.0")
        implementation("com.google.code.gson:gson:2.14.0")
    }
}

flutter {
    source = "../.."
}
