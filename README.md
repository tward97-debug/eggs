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

The economy follows the Egg, Inc. wiki: egg values and upgrade thresholds
(`assets/data/eggs.json`), per-level research prices
(`assets/data/common_research.json`), boost tiers (`assets/data/boosts.json`),
and the farm value, Soul Egg and silo formulas in `lib/game/engine.dart`.
Values marked TUNABLE or PLACEHOLDER in `lib/config/balance.dart` are our own
(hatchery rates, running chicken bonus, drone rewards, Golden Egg price scale).

`test/balance_sim_test.dart` is the pacing gate: a simulated player must reach
each of the first three egg upgrades in 10 to 30 minutes. Run `flutter test`
after any balance change.

## Garden

The Garden (More menu) replaces Prophecy Eggs. Crops grow in real time from a
planting timestamp, are ready for 45 minutes, then wither. The four corn crops
pay Soul Eggs, Candy Corn compounds the Soul Egg bonus (8 plots harvested
daily for a year is worth about 120 Prophecy Eggs), and the four utility crops
grow the strongest version of each boost, which can no longer be bought.
All tuning is in `assets/data/garden.json`; the rules are in
`lib/game/garden.dart` and tested in `test/garden_test.dart`.
