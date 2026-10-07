import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = File(
    System.getenv("OSC_SIGNING_PROPERTIES")
        ?: "${System.getProperty("user.home")}/.secrets/osc-alert/android-release.properties"
)
val signingProps = Properties()
if (signingFile.isFile) signingFile.inputStream().use { signingProps.load(it) }
// Why the release key cannot be used, or null when it can.
val signingProblem: String? = run {
    if (!signingFile.isFile) {
        return@run "Release signing properties not found: $signingFile. Set OSC_SIGNING_PROPERTIES " +
            "to the properties file of the release key (see \"Signing key\" in the README)."
    }
    val missing = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .filter { signingProps.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) return@run "$signingFile is missing: ${missing.joinToString(", ")}"
    val store = File(signingFile.parentFile, signingProps.getProperty("storeFile"))
    if (store.isFile) null else "Keystore not found: $store (storeFile in $signingFile)"
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
        // The release key lives outside the repository (see "Signing key" in the README). Its
        // properties file has storeFile (relative to the file itself), storePassword, keyAlias and
        // keyPassword. Debug builds, the analyzer and the tests work without it; the release
        // tasks fail below when it is missing.
        create("release") {
            if (signingProblem == null) {
                storeFile = File(signingFile.parentFile, signingProps.getProperty("storeFile"))
                storePassword = signingProps.getProperty("storePassword")
                keyAlias = signingProps.getProperty("keyAlias")
                keyPassword = signingProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Never fall back to another key: the release build stops here when the signing key is missing.
tasks.configureEach {
    if (name == "validateSigningRelease" || name == "packageRelease") {
        doFirst { signingProblem?.let { throw GradleException(it) } }
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
