# Egg Empire

Egg Empire is a Flutter idle game for Android.

## Run locally

Install Flutter stable and an Android SDK, then run:

```sh
flutter pub get
flutter run
```

## Build a release APK

```sh
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. For
distribution through an app store, configure a private Android upload/signing
key in the local Gradle properties and release signing configuration; do not
commit keystores or passwords. The Android launcher icon is defined in
`android/app/src/main/res/drawable/ic_egg_empire.xml`.

## Balance values

PLACEHOLDER and TUNABLE values are centralized in
`lib/config/balance.dart` or the JSON files under `assets/data/`.
