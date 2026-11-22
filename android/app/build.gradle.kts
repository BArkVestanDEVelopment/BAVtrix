import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Upload key for store builds. The path of a properties file (storeFile, storePassword, keyAlias,
// keyPassword; kept outside the repository) comes from the BAVTRIX_KEYSTORE_PROPS environment
// variable or from `bavtrix.keystoreProps` in android/local.properties. Without it the release
// build stays unsigned.
val keystoreProps = Properties().apply {
    val local = Properties()
    rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { local.load(it) }
    val path = System.getenv("BAVTRIX_KEYSTORE_PROPS") ?: local.getProperty("bavtrix.keystoreProps")
    if (path != null && file(path).exists()) file(path).inputStream().use { load(it) }
}

android {
    namespace = "app.bavtrix"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.bavtrix"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
    }

    signingConfigs {
        if (keystoreProps.getProperty("storeFile") != null) {
            create("upload") {
                storeFile = file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfigs.findByName("upload")?.let { signingConfig = it }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    // The licence texts live in the repository's legal folder and are shipped as assets.
    sourceSets.getByName("main").assets.srcDir("../../legal")
}

dependencies {
    implementation(project(":core"))
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.3")
}
