# Egg Empire

Egg Empire is a Flutter idle game for Android.

## Run locally

Install Flutter stable and an Android SDK, then run:

```sh
flutter pub get
flutter run
```

## Build a release APK

Create an upload keystore outside this project (for example,
`$HOME/.android/egg-empire-upload.jks`) and copy
`android/key.properties.example` to `android/key.properties`. Fill in the
keystore alias, passwords, and the absolute keystore path in the copied file.
Never commit `key.properties` or the keystore. Without `android/key.properties`,
release builds use the debug key for local testing and are not suitable for
distribution or updates.

```sh
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. For
distribution, keep the same application ID and signing key for every update.
Increase the version code (the integer after `+` in `pubspec.yaml`) for every
release so Android can recognize it as newer. The Android launcher icon is defined in
`android/app/src/main/res/drawable/ic_egg_empire.xml`.

## Balance values

PLACEHOLDER and TUNABLE values are centralized in
`lib/config/balance.dart` or the JSON files under `assets/data/`.
