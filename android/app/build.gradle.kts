import java.io.File
import org.gradle.internal.os.OperatingSystem
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

val repoRoot = rootProject.layout.projectDirectory.dir("..").asFile
val easyTierRoot = File(repoRoot, "third_party/EasyTier")

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

fun readEasyTierAndroidVersion(): String {
    val cargoToml = File(easyTierRoot, "easytier/Cargo.toml")
    val content = cargoToml.readText()
    val match = Regex("""(?m)^version\s*=\s*"([^"]+)"""").find(content)
    return match?.groupValues?.getOrNull(1) ?: "unknown"
}

fun readEasyTierAndroidCommit(): String {
    val gitHead = File(easyTierRoot, ".git")
    if (!gitHead.exists()) {
        return "unknown"
    }
    return try {
        val process = ProcessBuilder("git", "rev-parse", "--short", "HEAD")
            .directory(easyTierRoot)
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.bufferedReader().use { it.readText().trim() }
        if (process.waitFor() != 0) {
            "unknown"
        } else {
            output.ifEmpty { "unknown" }
        }
    } catch (_: Exception) {
        "unknown"
    }
}

val easyTierAndroidVersion =
    "easytier-ffi ${readEasyTierAndroidVersion()}-${readEasyTierAndroidCommit()}"

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

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
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
        buildConfigField(
            "String",
            "EASYTIER_ANDROID_VERSION",
            "\"$easyTierAndroidVersion\"",
        )
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

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

val prepareAndroidJniLibraries by tasks.registering(Exec::class) {
    group = "build"
    description = "Cross-compiles EasyTier Android JNI/FFI libraries and embeds them into jniLibs."

    val script = if (OperatingSystem.current().isWindows) {
        File(repoRoot, "tool/prepare_easytier_android.ps1")
    } else {
        File(repoRoot, "tool/prepare_easytier_android.sh")
    }

    workingDir = repoRoot
    inputs.dir(easyTierRoot)
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
