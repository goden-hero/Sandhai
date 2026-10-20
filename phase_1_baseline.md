# Sandhai Phase 1 — Development baseline

Date: 2026-10-20

Subsequent device confirmation from the user: demo launch verified on
Samsung SM J810GF, Android 10 / API 29. The automated checks below retain their
original Phase 1 results; Phase 2 device authentication/persistence was not covered
by that demo-only confirmation.

## Implementation

- Pin Flutter 3.47.5 stable (Dart 3.13.4) through `.fvmrc`, pubspec minimums,
  and README setup instructions. Retain the existing dependency choices and
  update the application lockfile for the supported SDK.
- Resolve invalid widget arguments/alignment symbols, the CardThemeData API
  mismatch, missing OfferService import, deprecated API use, async-context guards,
  and lint findings. Enable Flutter's standard lint set without disabling rules.
- Generate only Android/web runners in a temporary project, then copy those
  runners into Sandhai. Keep Firebase project/options/rules/indexes intact.
  Android application ID: `com.sandhai.app`. Include Gradle wrapper files; ignore
  local SDK paths, credentials/keystores, caches, logs, and build products.
- Select `demo`, `emulator`, or `production` using `APP_MODE`. Default to demo.
  Debug/release is independent of backend choice. Configure emulator hosts using
  `FIREBASE_EMULATOR_HOST`; defaults are browser loopback and Android 10.0.2.2.
- Demo startup and its in-memory account/profile/offer paths never instantiate
  Firebase services. Firebase startup errors/timeouts display a dedicated error
  screen. Production rejects the checked-in placeholder Firebase options.
- Add real Dart startup, navigation, registration, mode/host, and startup-error
  tests. Fix phone-width layout overflows revealed by the smoke test.

## Toolchain used

- Flutter: 3.47.5 stable, revision `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`.
- Dart: 3.13.4 (bundled with Flutter).
- Chrome: 152.0.7977.82.
- Android build JDK: Eclipse Temurin 21.0.12.1+1-LTS, with javac 21.0.12.1
  (Android bytecode target 17). The original OpenJDK 25.0.4.1 installation was
  runtime-only; its first APK attempt failed with missing JAVA_COMPILER capabilities.
- Android runner: Gradle 9.3.1; Android Gradle Plugin 9.1.0; Kotlin plugin 2.4.0;
  compile/target SDK 36; min SDK 24; NDK 28.2.13676358. The existing
  Firebase plugins also use Android SDK Platform 34.

## Verification

| Exact command | Result |
| --- | --- |
| `flutter --version --machine` | Flutter 3.47.5 / Dart 3.13.4 |
| `flutter doctor -v` | No issues; Android SDK and Chrome available |
| `flutter pub get` | Passed |
| `flutter analyze` | Passed, zero issues |
| `flutter test` | Passed, 11 actual Dart tests |
| `flutter build web --dart-define=APP_MODE=demo` | Passed; `build/web/` |
| `flutter build apk --debug --dart-define=APP_MODE=demo` | First attempt blocked by runtime-only Java 25 (no javac) |
| `env JAVA_HOME=/tmp/sandhai-phase1-jdk flutter build apk --debug --dart-define=APP_MODE=demo` | Passed; `build/app/outputs/flutter-apk/app-debug.apk` (approximately 149 MiB) |
| `node /tmp/sandhai-phase1-web-launch.cjs` | Passed; built demo launched in headless Chrome |
| `npm test` | Passed; existing supplementary source-text suite |

The temporary browser probe uses the host's Playwright installation and serves
`build/web/` on a temporary loopback port. It checks the welcome screen, demo label,
customer-registration navigation, zero JavaScript page errors, and zero Firebase
API requests, then closes the server/browser. Screenshots are saved at
`/tmp/sandhai-phase1-chrome-welcome.png` and
`/tmp/sandhai-phase1-chrome-registration.png`.
For an interactive launch use the documented command:
`flutter run -d chrome --dart-define=APP_MODE=demo`.

The temporary full JDK was fetched from the official Adoptium release metadata
at `https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&image_type=jdk&jvm_impl=hotspot&os=linux&vendor=eclipse`
and extracted only after checking SHA-256
`ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94`.
No system package installation or global Flutter JDK setting was changed. On a
normal development machine install a full JDK 21 and use the README build command;
the `/tmp` override is specific to this validation host.

No Android device was attached. Chrome is the supported target used for the basic
launch check. This phase does not claim Android device execution or production
Firebase connectivity. Nearby discovery, approval administration, image picking,
and persistence hardening remain subsequent work.

## Remaining environment limitations

All acceptance checks passed using the supported SDK and a full JDK 21. There is
no remaining source/build blocker with those prerequisites. The host's default
Java 25 is still a runtime-only installation; Android builds on this host require
the recorded JAVA_HOME override or a permanent full JDK installation. The JDK in
`/tmp` is a validation tool, not a repository dependency or permanent installation.
Android device execution was not checked because no Android device was attached;
the required basic launch was verified in Chrome. Production Firebase options
remain placeholders and are deliberately rejected at startup.

## Existing working-tree preservation

Instructions and git status were inspected before edits; no applicable AGENTS.md
was found. A snapshot and original diff are retained in
`/tmp/sandhai-phase1-before-3jw53d75/`. No reset, clean, or commit was performed.
Existing modifications in the auth/offer services were retained while adding
explicit demo branches and lazy Firebase access. Existing JavaScript tests,
Firebase rules/config/indexes, and GeohashUtils were verified byte-for-byte
against the snapshot. Existing task documents and the tracked Firebase debug log
were not edited.

## Files changed by this phase

These are changes relative to the initial working tree, not all differences
against HEAD. `README.md` and `pubspec.lock` already existed as untracked files.

- `.fvmrc`
- `.gitignore`
- `.metadata`
- `README.md`
- `analysis_options.yaml`
- `lib/app/app.dart`
- `lib/app/bootstrap.dart`
- `lib/app/config.dart`
- `lib/app/router.dart`
- `lib/app/theme.dart`
- `lib/features/auth/screens/register_customer_screen.dart`
- `lib/features/auth/screens/register_vendor_screen.dart`
- `lib/features/auth/screens/sign_in_screen.dart`
- `lib/features/auth/services/auth_service.dart`
- `lib/features/customer/screens/customer_home_screen.dart`
- `lib/features/customer/widgets/offer_card.dart`
- `lib/features/onboarding/screens/welcome_screen.dart`
- `lib/features/profile/screens/profile_screen.dart`
- `lib/features/vendor/screens/create_offer_screen.dart`
- `lib/features/vendor/screens/vendor_dashboard_screen.dart`
- `lib/features/vendor/screens/vendor_profile_screen.dart`
- `lib/features/vendor/services/offer_service.dart`
- `lib/features/vendor/widgets/metric_card.dart`
- `lib/main.dart`
- `pubspec.lock`
- `pubspec.yaml`
- `test/config_test.dart`
- `test/startup_test.dart`
- `phase_1_baseline.md` (this report)

Generated runner files:

- `android/.gitignore`
- `android/app/build.gradle.kts`
- `android/app/src/debug/AndroidManifest.xml`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/sandhai/app/MainActivity.kt`
- `android/app/src/main/res/drawable-v21/launch_background.xml`
- `android/app/src/main/res/drawable/launch_background.xml`
- `android/app/src/main/res/mipmap-hdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-mdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`
- `android/app/src/main/res/values-night/styles.xml`
- `android/app/src/main/res/values/styles.xml`
- `android/app/src/profile/AndroidManifest.xml`
- `android/build.gradle.kts`
- `android/gradle.properties`
- `android/gradle/wrapper/gradle-wrapper.jar`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `android/gradlew`
- `android/gradlew.bat`
- `android/settings.gradle.kts`
- `web/favicon.png`
- `web/icons/Icon-192.png`
- `web/icons/Icon-512.png`
- `web/icons/Icon-maskable-192.png`
- `web/icons/Icon-maskable-512.png`
- `web/index.html`
- `web/manifest.json`
