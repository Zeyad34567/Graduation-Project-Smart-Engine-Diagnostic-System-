# Application

## Flutter Mobile App (Application)



### 2.1 Core Tooling

| Tool | Required Version | Notes |
|---|---|---|
| **Flutter SDK** | `^3.12.2` (Dart SDK constraint in `pubspec.yaml`: `sdk: ^3.12.2`) | Install via [flutter.dev](https://flutter.dev). Run `flutter doctor` to verify. |
| **Dart SDK** | Bundled with Flutter (≥ 3.12.2) | — |
| **Android Studio** | Recent stable (Giraffe/Koala or newer recommended) | For Android SDK/emulator management and Gradle integration. |
| **Android SDK / Platform Tools** | `compileSdk = 36`, `targetSdk = 36`, `minSdk = 24` (Android 7.0+) | Install Android SDK Platform 36 + Build-Tools via Android Studio SDK Manager. |
| **Android NDK** | Version pinned by Flutter (`flutter.ndkVersion`) | Auto-resolved by the Flutter Gradle plugin; install via SDK Manager if prompted. |
| **JDK (Java)** | JDK 17 recommended (Gradle/AGP 8.x requirement); app's Java/Kotlin source/target compatibility set to `1.8` | Required to run Gradle builds. |
| **Kotlin** | `2.2.20` (Android Gradle plugin) | Declared in `android/settings.gradle.kts`. |
| **Gradle** | `8.14.5` (via wrapper) | Declared in `gradle-wrapper.properties`; downloaded automatically by `./gradlew`. |
| **Android Gradle Plugin (AGP)** | `8.11.1` | Declared in `android/settings.gradle.kts`. |
| **Git** | Any recent version | For source control / cloning. |
| **A physical Android device or emulator** | Android 7.0 (API 24) or newer | App requires microphone access; an emulator with audio passthrough or a real device is recommended for the "record audio" feature. |

> ⚠️ The project is configured for **Android only** in this archive (no `ios/`, `web/`, `linux/`, `macos/`, or `windows/` folders were present). If iOS/desktop support is needed, those platform folders must be generated with `flutter create .` and the relevant platform SDKs (Xcode, CocoaPods, etc.) installed separately.

### 2.2 Flutter/Dart Package Dependencies (`pubspec.yaml`)

**Runtime dependencies:**

| Package | Version Constraint | Purpose |
|---|---|---|
| `flutter` | (SDK) | Core Flutter framework |
| `cupertino_icons` | `^1.0.8` | iOS-style icon set |
| `file_picker` | `^8.1.2` | Lets the user pick audio files from device storage to analyze |
| `path_provider` | `^2.1.2` | Resolves platform-specific filesystem paths (temp/app storage) for saving processed audio |
| `permission_handler` | `^11.3.1` | Requests/manages runtime permissions (microphone, storage) |
| `device_info_plus` | `^10.1.0` | Retrieves device metadata (used for diagnostics/about screen, history, etc.) |
| `ffmpeg_kit_flutter_new` | `4.2.1` (pinned, not caret) | Audio decoding/transcoding (e.g., converting arbitrary uploaded audio formats to a usable PCM/WAV format for feature extraction). Bundles native FFmpeg binaries for Android. |

**Dev dependencies:**

| Package | Version Constraint | Purpose |
|---|---|---|
| `flutter_test` | (SDK) | Flutter's testing framework |
| `flutter_lints` | `^6.0.0` | Recommended lint rules for Dart/Flutter code style |

> All packages are pulled from **pub.dev**. Run `flutter pub get` inside `app6/` to fetch them (requires internet access).

### 2.3 Android Manifest / Permissions Required

Declared in `android/app/src/main/AndroidManifest.xml`:

- `RECORD_AUDIO` — microphone access for recording engine audio
- `FOREGROUND_SERVICE` — keeps audio recording alive on Android 8+ (required by recording dependencies)
- `MODIFY_AUDIO_SETTINGS` — adjusts audio routing during recording
- `READ_EXTERNAL_STORAGE` (maxSdkVersion 32) — legacy storage access for older Android versions
- `READ_MEDIA_AUDIO` — scoped storage audio access (Android 13+)
- `INTERNET` (debug/profile build only) — required by Flutter tooling for hot reload/debugging, not used in release builds

### 2.4 Native/Build System Files Already Present

- `android/build.gradle.kts`, `android/app/build.gradle.kts`, `android/settings.gradle.kts`
- `android/gradle/wrapper/gradle-wrapper.properties` (Gradle 8.14.5, downloaded automatically)
- `android/gradlew` / `android/gradlew.bat` — Gradle wrapper scripts (no manual Gradle install needed)
- `android/local.properties` — **machine-specific**, contains hardcoded paths to `flutter.sdk` and `sdk.dir` (Android SDK). **This file must be regenerated/edited for each developer's machine** (it currently points to a Windows path: `C:\Users\Zeyad\AppData\Local\Android\sdk` and `C:\src\flutter`). Flutter normally regenerates this automatically on first build, or you can edit it manually.

> Note: `android/gradle.properties` contains a comment referencing `tflite_flutter` JVM target settings (Java 11 / Kotlin 17 workaround), but `tflite_flutter` is **not** in the current `pubspec.yaml` dependency list — the project has since moved to pure-Dart RF inference. This leftover setting is harmless but can be ignored/cleaned up.

### 2.5 Bundled Model/Config Assets (already included, no extra download needed)

Declared under `flutter: assets:` in `pubspec.yaml`, located in `app6/assets/`:

| File | Size (approx.) | Purpose |
|---|---|---|
| `random_forest_v1.json` | ~44.6 MB | Serialized fault-classification Random Forest (300 trees, 12 classes) + StandardScaler |
| `ood_gate_rf_v1.json` | ~5.2 MB | Serialized OOD-gate Random Forest (300 trees, binary) + StandardScaler |
| `config.json` | <1 KB | Fault model config: confidence threshold (0.60), number of classes (12), sample rate, feature count (418), etc. |
| `ood_gate_config.json` | <1 KB | OOD gate config: OOD threshold (0.75 in config / 0.50 default in code), OOD category labels |
| `engine_knowledge_base.json` | ~39 KB | Reference/explanatory text shown in the app for each fault type |

### 2.6 Build & Run Commands

```bash
cd app6
flutter pub get          # fetch Dart/Flutter packages
flutter doctor            # verify toolchain (Android SDK, Java, etc.)
flutter run                # run on a connected device/emulator (debug)
flutter build apk --release   # produce a release APK
```
