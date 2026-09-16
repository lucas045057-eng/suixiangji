import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingPropertiesPath = System.getenv("WEALTHMATE_SIGNING_PROPERTIES_PATH")
val signingPropertiesFile = if (signingPropertiesPath.isNullOrBlank()) {
    rootProject.file("key.properties")
} else {
    file(signingPropertiesPath)
}
val signingProperties = Properties()
if (!signingPropertiesFile.isFile) {
    throw GradleException("Android release signing properties file is missing")
}
signingPropertiesFile.inputStream().use { signingProperties.load(it) }

val requiredSigningProperties = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
requiredSigningProperties.forEach { propertyName ->
    require(!signingProperties.getProperty(propertyName).isNullOrBlank()) {
        "Android release signing property is missing: $propertyName"
    }
}

val storeFileValue = signingProperties.getProperty("storeFile").trim()
val signingStoreFile = File(storeFileValue).let { candidate ->
    if (candidate.isAbsolute) candidate else File(signingPropertiesFile.parentFile, storeFileValue)
}
if (!signingStoreFile.isFile) {
    throw GradleException("Android release keystore file is missing")
}

android {
    namespace = "com.example.wealthmate_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.wealthmate_flutter"
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
        create("release") {
            storeFile = signingStoreFile
            storePassword = signingProperties.getProperty("storePassword")
            keyAlias = signingProperties.getProperty("keyAlias")
            keyPassword = signingProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            // Release signing is loaded from the controlled properties file.
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
