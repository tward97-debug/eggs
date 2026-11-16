import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyPropertiesFile = rootProject.file("key.properties")
val releaseKeyProperties = Properties()
if (releaseKeyPropertiesFile.isFile) {
    releaseKeyPropertiesFile.inputStream().use(releaseKeyProperties::load)
}

val releasePropertyNames = listOf(
    "storePassword",
    "keyPassword",
    "keyAlias",
    "storeFile",
)
val releasePropertyValues = releasePropertyNames.associateWith { name ->
    releaseKeyProperties.getProperty(name)?.trim()?.takeIf(String::isNotEmpty)
}
val hasReleaseSigningValues = releasePropertyValues.values.all { it != null }
val releaseStoreFile = releasePropertyValues["storeFile"]?.let(::file)

val validateReleaseSigning = tasks.register("validateReleaseSigningConfig") {
    doLast {
        if (!releaseKeyPropertiesFile.isFile) {
            throw GradleException(
                "Release signing requires android/key.properties. Add "
                    + "storePassword, keyPassword, keyAlias, and storeFile.",
            )
        }
        val properties = Properties()
        releaseKeyPropertiesFile.inputStream().use(properties::load)
        for (name in releasePropertyNames) {
            if (properties.getProperty(name)?.trim().isNullOrEmpty()) {
                throw GradleException(
                    "Release signing property '$name' is missing or empty "
                        + "in android/key.properties.",
                )
            }
        }
        val storeFile = file(properties.getProperty("storeFile").trim())
        if (!storeFile.isFile) {
            throw GradleException(
                "Release signing keystore does not exist at the configured "
                    + "storeFile path.",
            )
        }
    }
}

tasks.configureEach {
    if (name != "validateReleaseSigningConfig" && name.contains("Release")) {
        dependsOn(validateReleaseSigning)
    }
}

android {
    namespace = "com.triston.eggempire"
    // flutter_local_notifications needs 37 or newer.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.triston.eggempire"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
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
            if (hasReleaseSigningValues) {
                keyAlias = releasePropertyValues.getValue("keyAlias")!!
                keyPassword = releasePropertyValues.getValue("keyPassword")!!
                storeFile = releaseStoreFile
                storePassword = releasePropertyValues.getValue("storePassword")!!
            }
        }
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

dependencies {
    // Required by flutter_local_notifications for scheduled alerts.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
