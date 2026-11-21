# Android release build

1. Create an upload key once and keep it (and its passwords) outside the repository:
   `keytool -genkeypair -v -keystore bavtrix-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000`
2. Create `android/keystore.properties` (git-ignored):
   ```
   storeFile=../../keys/bavtrix-upload.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```
3. Build the bundle for Google Play: `cd android` then `.\gradlew.bat :app:bundleRelease`
   (output: `app/build/outputs/bundle/release/app-release.aab`).

Without `keystore.properties` the release build is produced unsigned. Release builds use R8
shrinking (`app/proguard-rules.pro`). Raise `versionCode` in `app/build.gradle.kts` for every upload.