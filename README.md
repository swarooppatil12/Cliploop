# Cliploops

Music source separation app — split stems with **Spleeter** (Method 1) or analyse structure with **Whisper** (Method 2). **All processing runs on your device** — no server or cloud required.

## Prerequisites

- Flutter SDK (stable)
- Android SDK / Xcode (for device builds)

Add Flutter to your PATH:

```bash
export PATH="$HOME/flutter/bin:$PATH"
```

## Setup

```bash
cd cliploops
flutter pub get
```

## Run (debug)

```bash
flutter run
```

## App icon

Icons are generated from `assets/icon/app_icon.png` using `flutter_launcher_icons`:

```bash
dart run flutter_launcher_icons
```

## Build release

### Android APK (split per ABI)

```bash
flutter build apk --release --split-per-abi
```

Output:

- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`

Install on a connected device:

```bash
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### iOS (optional)

```bash
flutter build ios --release
```

Open `ios/Runner.xcworkspace` in Xcode to archive and distribute.

## Tests

```bash
flutter analyze
flutter test
```

## Project structure

```
cliploops/          # Flutter app (on-device processing)
PRD.md              # Product requirements
```

## Known issues

- **Release signing**: Android release builds currently use the debug keystore. Configure a release keystore before Play Store submission.
