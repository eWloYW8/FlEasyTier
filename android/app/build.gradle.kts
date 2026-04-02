import org.gradle.internal.os.OperatingSystem

val releaseStoreFile = System.getenv("ANDROID_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ewloyw8.fleasytier"
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
        applicationId = "com.ewloyw8.fleasytier"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Prefer a real release keystore when provided by the environment.
            // Fall back to the debug key for local development builds.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

val prepareAndroidJniLibraries by tasks.registering(Exec::class) {
    group = "build"
    description = "Cross-compiles EasyTier Android JNI/FFI libraries and embeds them into jniLibs."

    val repoRoot = rootProject.layout.projectDirectory.dir("..").asFile
    val script = if (OperatingSystem.current().isWindows) {
        File(repoRoot, "tool/prepare_easytier_android.ps1")
    } else {
        File(repoRoot, "tool/prepare_easytier_android.sh")
    }

    workingDir = repoRoot
    inputs.dir(File(repoRoot, "third_party/EasyTier"))
    outputs.dir(layout.projectDirectory.dir("src/main/jniLibs"))

    if (OperatingSystem.current().isWindows) {
        commandLine(
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script.absolutePath,
        )
    } else {
        commandLine("bash", script.absolutePath)
    }

    onlyIf { System.getenv("FLEASYTIER_SKIP_ANDROID_JNI_BUILD") != "1" }
}

tasks.named("preBuild") {
    dependsOn(prepareAndroidJniLibraries)
}
