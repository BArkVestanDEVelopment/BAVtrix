# Android release build

1. Create an upload key once and keep it, with its passwords, outside the repository (keytool -genkeypair ...).
2. Point the build at a properties file (storeFile, storePassword, keyAlias, keyPassword): set the
   BAVTRIX_KEYSTORE_PROPS environment variable or `bavtrix.keystoreProps` in `android/local.properties`.
3. Build the bundle for Google Play: `cd android` then `.\gradlew.bat :app:bundleRelease`
   (output: `app/build/outputs/bundle/release/app-release.aab`).

Without `keystore.properties` the release build is produced unsigned. Release builds use R8
shrinking (`app/proguard-rules.pro`). Raise `versionCode` in `app/build.gradle.kts` for every upload.