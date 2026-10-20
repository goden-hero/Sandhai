# 🛒 5KM Sandhai — Hyperlocal Geo-Fenced Clearance Marketplace

**5KM Sandhai** is a hyperlocal clearance marketplace platform built with **Flutter** and **Firebase**. It connects local retail vendors selling excess stock, fresh produce, and time-sensitive clearance items directly with nearby customers within a **5 KM radius**.

---

## Existing feature scaffold

### 👤 1. Authentication & Role-Based Access Control
- **Dual Role System**: Separate registration and navigation paths for **Customers** and **Vendors**.
- **Vendor Approval Workflow**: Newly registered vendors start with `PENDING` approval status. Offer creation is guarded in the UI and enforced at the Firebase Security Rules level until store verification.

### 🏬 2. Vendor Profile & Store Management
- Store profile creation and editing (Store Name, Phone, Category, Address, Description).
- Approval status indicators (`PENDING APPROVAL` vs `VERIFIED STORE` vs `SUSPENDED`).
- Profile edit protection (`PopScope` unsaved changes warning).

### 🏷️ 3. Clearance Offer Posting & Image Upload
- Material 3 offer posting form collecting product title, description, category, original price, clearance price, and offer validity duration (hours).
- **Client & Server Price Validation**: Real-time validation enforcing `clearancePrice <= originalPrice` and positive numeric prices.
- **Firebase Storage Integration**: The service supports upload bytes; the current UI attaches synthetic sample bytes rather than selecting a real photo. Image uploads target authorized paths `offers/{vendorUid}/{offerId}/{filename}` with file format (`png/jpg/jpeg/webp`) and size limits (`<= 5MB`).
- **Partial Failure Handling**: The service attempts cleanup after a failed Firestore write. Storage deletion authorization and propagation of save failures still need the subsequent persistence-hardening phase.

### 📍 4. Spatial Geolocation & Deterministic Geohashing
- **Deterministic Base32 Geohash Utility (`GeohashUtils`)**: Generates 6-character spatial geohashes (~1.2 km x 0.6 km bounding box) for stored spatial indexing. Radius-aware query coverage and exact distance filtering remain future work.
- **Vendor Store Location Resolution**: Offers automatically inherit registered vendor store coordinates (`latitude`, `longitude`, `geohash`) from `vendors/{uid}`.
- **Strict Location Validation**: The offer service rejects invalid coordinates, but vendor registration/model defaults still use sample coordinates; location acquisition is a later phase.

### 🛡️ 5. Firebase Security Rules
- **Firestore Security (`firestore.rules`)**: Strictly enforces role checks (`isApprovedVendor()`), path ownership (`request.auth.uid == vendorId`), profile field allowlists, price relationships, timestamp validity, and coordinate bounds (`-90 <= lat <= 90`, `-180 <= lng <= 180`).
- **Storage Security (`storage.rules`)**: Enforces path ownership `offers/{vendorId}/{offerId}/{fileName}`, `isApprovedVendor()`, MIME type matching, and max size limits.

---

## Supported development baseline

Use **Flutter 3.47.5 stable**, which includes **Dart 3.13.4**. This is the SDK
pair used for Phase 1 verification; `.fvmrc` records the Flutter pin for developers
who use FVM. With FVM, prefix the commands below with `fvm`. Otherwise put this
Flutter SDK on `PATH`. The Dart and Flutter minimums are also declared in
`pubspec.yaml`; newer SDKs must pass the same checks before adopting them.

Supported runners in this repository are **Android** (`com.sandhai.app`) and
**web**. iOS and desktop runner projects are not included.

```bash
flutter --version
flutter doctor -v
flutter pub get
```

For Android, install the Android SDK command-line tools, platforms **android-36** and **android-34** (the existing Firebase plugins),
build-tools **36.0.0**, and NDK **28.2.13676358**, and accept the SDK licenses:

```bash
sdkmanager "platform-tools" "platforms;android-36" "platforms;android-34" "build-tools;36.0.0" "ndk;28.2.13676358"
flutter doctor --android-licenses
```

The generated runner uses Gradle 9.3.1, Android Gradle Plugin 9.1.0, and Java 17
bytecode targets. Install a **full JDK 21**, including `javac`, such as
[Eclipse Temurin](https://adoptium.net/installation/). A JRE alone is insufficient,
even if `flutter doctor` reports a healthy Android toolchain. Verify both tools:

```bash
java -version
javac -version
flutter doctor -v
```

If Flutter selects a runtime without a compiler, set `JAVA_HOME` to the full JDK
when invoking the Android build, or configure the JDK in your local Flutter
settings. For example:

```bash
JAVA_HOME=/absolute/path/to/jdk-21 flutter build apk --debug --dart-define=APP_MODE=demo
```

Chrome is required for the browser launch check.
`android/local.properties` is generated for each developer and is ignored.
Commit `pubspec.lock` to keep application dependencies reproducible.

## Select an application mode

Mode is selected by the build-time `APP_MODE` Dart define. The default is `demo`.
Debug/profile/release build type never changes the selected backend. A misspelled
mode produces a visible startup error.

| Mode | Behavior |
| --- | --- |
| `demo` | Skips Firebase initialization. Demo accounts/profiles and posted offers are held in memory and reset on process restart. |
| `emulator` | Initializes Firebase and connects Auth/Firestore/Storage to the configured local host on ports 9099/8080/9199. |
| `production` | Uses `lib/firebase_options.dart` generated for your Firebase project. The checked-in placeholder options are rejected with a visible startup error. |

### Demo (no Firebase required)

```bash
flutter run -d chrome --dart-define=APP_MODE=demo
flutter devices
flutter run -d <android-device-id> --dart-define=APP_MODE=demo
```

Demo sign-in accepts an email and a nonempty password without creating a Firebase
account. Emails containing `vendor` select the existing pending-vendor demo path;
other emails select the customer path. Registration also works locally. Sample
feeds, photo selection, distances, and dashboard metrics remain demo features.

### Firebase emulators

Node.js 22 and a Java runtime are needed for the existing emulator tests. Install
the Node test dependencies and Firebase CLI if they are not already available:

```bash
npm install
npm install --global firebase-tools@15.31.0
firebase emulators:start --only firestore,storage,auth --project sandhai-5km-demo
```

Keep the emulators running in a separate terminal. All modes use the same app
entry point:

```bash
# Browser on the same machine as the emulators
flutter run -d chrome --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1

# Android Studio emulator; 10.0.2.2 refers to the host machine
flutter run -d <android-emulator-id> --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2

# Physical Android device after adb reverse (run all three forwards)
adb reverse tcp:9099 tcp:9099
adb reverse tcp:8080 tcp:8080
adb reverse tcp:9199 tcp:9199
flutter run -d <android-device-id> --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1
```

Without an explicit host, browser builds use `127.0.0.1` and native Android builds
use `10.0.2.2`. `FIREBASE_EMULATOR_HOST` accepts a hostname/IP, without a scheme,
port, or path. For a physical device over LAN, use the computer's LAN address and
configure the emulators' listening hosts and firewall accordingly.
`FIREBASE_EMULATOR_PROJECT_ID` can override `sandhai-5km-demo`; the CLI project ID
and app define must match. Android debug builds permit cleartext HTTP for the
local emulators; release builds retain Android's default policy.

Initialization/configuration failures in emulator and production modes display
an error screen and do not open demo mode. Successful Firebase initialization
configures the SDK; it does not prove the emulator services are reachable.
The Firebase configuration, rules, and indexes are preserved from the existing
project. Live nearby discovery and service persistence hardening are later phases.

### Production configuration

The repository does not contain working production Firebase credentials. Configure
your own project before selecting production mode:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=<firebase-project-id> --platforms=android,web
flutter run -d chrome --dart-define=APP_MODE=production
flutter run -d <android-device-id> --dart-define=APP_MODE=production
```

Review the generated Firebase files and project association before deploying
rules or indexes. Firebase resources are not deployed by a Flutter build.

## Verification commands

Run these from the repository root with the supported SDK:

```bash
flutter analyze
flutter test
flutter build web --dart-define=APP_MODE=demo
flutter build apk --debug --dart-define=APP_MODE=demo
flutter run -d chrome --dart-define=APP_MODE=demo
```

Build artifacts are `build/web/` and `build/app/outputs/flutter-apk/app-debug.apk`.
To package another mode, replace the `APP_MODE` define and include the emulator
host define when appropriate. A successful production compilation alone does not
validate production Firebase configuration or authorize a release.

The Dart suite includes a real `main()` startup/navigation/registration smoke
test proving demo runs with no Firebase apps, mode/host parsing tests, and visible
failure tests for both Firebase modes. It uses the in-process Flutter test runner:

```bash
flutter test test/startup_test.dart
flutter test test/config_test.dart
```

The original Node checks are retained as supplementary source-text checks and
Firebase security-rules tests; they do not compile or execute Dart:

```bash
npm test
firebase emulators:exec --only firestore,storage,auth --project sandhai-5km-demo "node --test test/rules.test.js"
```

`npm run test:emulators` is the existing convenience wrapper; it downloads
`firebase-tools@latest` through `npx`. Use the pinned CLI command above for the
recorded baseline. `emulators:exec` runs tests and shuts down; use
`emulators:start` when running the app interactively.

---

The recorded command results, toolchain details, and complete changed-file list
are in [the Phase 1 baseline report](phase_1_baseline.md).

## 📁 Project Structure

```text
sandhai/
├── lib/
│   ├── main.dart                      # App entry point; explicit-mode bootstrap
│   ├── firebase_options.dart          # Firebase project configuration options
│   ├── app/
│   │   ├── bootstrap.dart             # Mode setup and visible startup failures
│   │   ├── config.dart                # Demo/emulator/production definitions
│   │   ├── router.dart                # Centralized app routes
│   │   └── theme.dart                 # Material 3 design theme
│   ├── core/
│   │   └── utils/
│   │       └── geohash_utils.dart     # Base32 Geohash Utility (Precision 6)
│   ├── models/
│   │   ├── user_model.dart            # Customer & Vendor profile data model
│   │   ├── vendor_model.dart          # Vendor store profile data model
│   │   └── offer_model.dart           # Clearance offer data model
│   ├── features/
│   │   ├── auth/                      # Authentication & Registration screens/services
│   │   │   ├── screens/               # Welcome, SignIn, Register Customer, Register Vendor
│   │   │   └── services/              # AuthService singleton
│   │   ├── vendor/                    # Vendor screens, services & widgets
│   │   │   ├── screens/               # Vendor Dashboard, Create Offer, Vendor Profile
│   │   │   ├── services/              # OfferService singleton
│   │   │   └── widgets/               # Metric cards, status badges
│   │   └── customer/                  # Customer home & offer discovery screens
│   └── mock_data/
│       └── mock_data.dart             # Centralized sample data for standalone demo mode
├── test/
│   ├── startup_test.dart              # Real demo startup and Firebase failure smoke tests
│   ├── config_test.dart               # Application mode and emulator host tests
│   ├── widget_and_model_test.js       # Node.js static source-text checks
│   └── rules.test.js                  # Firebase Emulator security rules test suite
├── android/                           # Android runner (com.sandhai.app)
├── web/                               # Browser runner
├── firestore.rules                    # Cloud Firestore Security Rules
├── storage.rules                      # Firebase Storage Security Rules
├── firestore.indexes.json             # Firestore composite indexes definition
├── pubspec.yaml                       # Flutter dependencies & configuration
├── package.json                       # Node test scripts & Firebase emulator devDependencies
└── README.md
```

---

## 📊 Data Models & Schemas

### Cloud Firestore: `offers/{offerId}`
```json
{
  "id": "offer_doc_id",
  "vendorId": "auth_vendor_uid",
  "title": "Organic Alphonso Mangoes 1kg",
  "description": "Surplus clearance stock. Fresh and ready to consume.",
  "oldPrice": 160.0,
  "newPrice": 70.0,
  "imageUrl": "https://storage.googleapis.com/.../offers/vendorUid/offerId/item.jpg",
  "latitude": 13.0402,
  "longitude": 80.2337,
  "geohash": "tf340w",
  "createdAt": "Timestamp",
  "expiryTime": "Timestamp",
  "status": "active"
}
```

### Firebase Storage Path:
`offers/{vendorUid}/{offerId}/{filename}`

---

## 📄 License

This project is developed as a hyperlocal clearance marketplace demo application.
