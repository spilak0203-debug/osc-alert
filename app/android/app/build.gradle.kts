plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "kr.personal.oscalert"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on older Android versions.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "kr.personal.oscalert"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // The workflow passes --build-number (the run number) and --build-name 2.<run number>.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Every build must be signed with the same key as the Java app or updates will not
        // install over it. The workflow swaps in `release.keystore` from repository secrets
        // when they exist.
        create("release") {
            storeFile = file("release.keystore")
            storePassword = (project.findProperty("storePassword") as String?) ?: "oscalert"
            keyAlias = "osc"
            keyPassword = (project.findProperty("keyPassword") as String?) ?: "oscalert"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // MainActivity cancels the Java app's old WorkManager job.
    implementation("androidx.work:work-runtime:2.10.3")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
