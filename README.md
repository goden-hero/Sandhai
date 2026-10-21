# 🛒 5KM Sandhai — Hyperlocal Geo-Fenced Clearance Marketplace

**5KM Sandhai** is a hyperlocal clearance marketplace platform built with **Flutter** and **Firebase**. It connects local retail vendors selling excess stock, fresh produce, and time-sensitive clearance items directly with nearby customers within a **5 KM radius**.

---

## Existing feature scaffold

### 👤 1. Authentication & Role-Based Access Control
- **Dual Role System**: Separate registration and navigation paths for **Customers** and **Vendors**.
- **Vendor Approval Workflow**: Newly registered vendors start with `PENDING` approval status. Offer creation is guarded in the UI and enforced at the Firebase Security Rules level until store verification.
- **Restored sessions**: Firebase Auth restores the account on startup/reload. The entry screen waits for the account profile, routes missing profiles to registration completion, and shows retry/sign-out controls for session errors.
- **Recoverable registration**: If the profile transaction fails after Auth account creation, retry completes the original UID; after restart, sign in with the same email/password to complete registration. User/vendor profiles are created together. Completion preserves any existing role, approval, and creation time.

### 🏬 2. Vendor Profile & Store Management
- Store profile creation and editing (Store Name, Phone, Category, Address, Description).
- Approval status indicators (`PENDING APPROVAL` vs `VERIFIED STORE` vs `SUSPENDED`).
- Profile edit protection (`PopScope` unsaved changes warning).
- Profile edits update the store and user display name atomically. Approval is observed while signed in, including rejection/revocation.
- Vendor dashboards subscribe to Firestore offers filtered by the current vendor UID, with loading, empty, error, and retry states. Logout/account changes dispose the previous account's subscriptions and navigation stack.

### 🏷️ 3. Clearance Offer Posting & Image Upload
- Material 3 offer posting form collecting product title, description, category, original price, clearance price, and offer validity duration (hours).
- **Client & Server Price Validation**: Real-time validation enforcing `clearancePrice <= originalPrice` and positive numeric prices.
- **Firebase Storage Integration**: The service accepts image bytes and awaits upload and URL retrieval. Upload paths are `offers/{vendorUid}/{offerId}/{filename}`, with image MIME and size limits (`<= 5MB`). Android and web use the real system/gallery picker, with decoded preview, cancellation, and Android activity-loss recovery. JPEG, PNG, and WebP only; up to 5 MiB (5,242,880 bytes) and 40 megapixels. The app checks signatures, dimensions, and decoded content; MIME and filename extension are derived from content.
- **Confirmed saves**: Online Firestore transactions distinguish pending operations from confirmed saves. Failed profile/offer saves display errors and retain form values for retry. Each offer form keeps a stable document ID to reconcile lost responses without duplicate offers. Failed uploads stop publication; confirmed unreferenced uploads are cleaned up when possible. An uncertain commit retains its image until the outcome can be checked.

### 📍 4. Spatial Geolocation & Deterministic Geohashing
- **Deterministic Base32 Geohash Utility (`GeohashUtils`)**: Generates 6-character spatial geohashes (~1.2 km x 0.6 km bounding box) for stored spatial indexing. Nearby queries cover a radius-derived bounding rectangle at adaptive precision, merge live results, and apply an unrounded 5,000 m distance filter.
- **Vendor Store Location Resolution**: Offers automatically inherit registered vendor store coordinates (`latitude`, `longitude`, `geohash`) from `vendors/{uid}`.
- **Strict Location Validation**: The offer service rejects invalid coordinates, but registration starts without coordinates. Vendors explicitly confirm or correct a foreground device-location suggestion, or manually enter coordinates. A server confirmation timestamp gates publication; legacy coordinates without confirmation cannot publish.

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

For Android, install the Android SDK command-line tools, platforms **android-36**, **android-35**, and **android-34** (the plugins), CMake **3.22.1**,
build-tools **36.0.0**, and NDK **28.2.13676358**, and accept the SDK licenses:

```bash
sdkmanager "platform-tools" "platforms;android-36" "platforms;android-34" "platforms;android-35" "cmake;3.22.1" "build-tools;36.0.0" "ndk;28.2.13676358"
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
other emails select the customer path. Registration also works locally. Sample customer feeds and distances are demo-only. Photo selection is real in every mode; demo uploads remain in memory. The vendor dashboard shows only offers created by that demo account.

### Firebase emulators

Node.js 22 and a Java runtime are needed for the existing emulator tests. Install
the Node test dependencies and Firebase CLI if they are not already available:

```bash
npm ci
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
The app disables FlutterFire's automatic host rewriting: an explicit
`127.0.0.1` remains loopback for USB forwarding, while the Android emulator
default is already selected as `10.0.2.2` by `AppConfig`.
`FIREBASE_EMULATOR_PROJECT_ID` can override `sandhai-5km-demo`; the CLI project ID
and app define must match. Android debug builds permit cleartext HTTP for the
local emulators; release builds retain Android's default policy.

Initialization/configuration failures in emulator and production modes display
an error screen and do not open demo mode. Successful Firebase initialization
configures the SDK; it does not prove the emulator services are reachable.
The Firebase project configuration and query indexes are retained. Rules support
atomic registration, private vendor queries, and owner upload cleanup after
revocation. Firebase-mode customers explicitly request foreground location and receive persisted active nearby offers. Permission, loading, query errors and empty results have separate states; errors never substitute demo data.

Auth sessions persist locally, while Firestore disk persistence is disabled.
Writes use online transactions and are acknowledged by the server before success
is displayed. An unavailable server can leave an operation pending while the SDK
retries; pending text remains visible and the app does not claim it was saved.
Offer fields are also checkpointed locally before photo selection and publication. A vendor can resume that draft after restart; photo bytes must be reselected unless Android returns a lost picker result. Drafts, picker results, and pending-upload records are scoped by application mode/project and vendor UID. Profile/auth form edits remain in memory. Saved profiles/offers survive restart as long as emulator data
is retained. For emulator data across CLI restarts, use:

```bash
firebase emulators:start --only firestore,storage,auth --project sandhai-5km-demo --import=.firebase/local-data --export-on-exit=.firebase/local-data
```

Omit `--import` on the first start when no export exists. Export-on-exit protects graceful shutdowns; take explicit checkpoints before verification because an abnormal emulator process exit can lose in-memory Auth/Storage changes. For local approval
testing, change your own emulator user's `approvalStatus` to `approved`,
`rejected`, or `suspended` in the Emulator UI at `http://127.0.0.1:4000`.
Clients cannot change approval through application writes. Administration is a
later phase.

The locked FlutterFire web Auth plugin restores sessions during Firebase core
initialization. `web/firebase_emulator_bootstrap.js` connects Auth before that
restoration in emulator mode. Its JS SDK version/dependencies match
`firebase_core_web 2.24.1` / `firebase_auth_web 5.15.3` in `pubspec.lock`; review
the adapter and rerun the browser workflow when upgrading FlutterFire. The
previous localhost/debug emulator hint is cleared before Firebase starts, so a
remembered emulator cannot override the selected mode or host.

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
flutter test test/persistence_test.dart test/persistence_widget_test.dart
```

The original Node checks are retained as supplementary source-text checks and
Firebase security-rules tests; they do not compile or execute Dart:

```bash
npm test
npm run test:emulators
```

`npm run test:emulators` uses the Firebase CLI installed above, local proxy bypass, separate test ports/project, and a unique TMPDIR for Storage isolation. `emulators:exec` runs tests and shuts down; use
`emulators:start` when running the app interactively.

The browser regression uses a built emulator-mode app, real Auth/Firestore SDKs,
and headless Chrome through the pinned `playwright-core` development dependency.
It verifies registration, reload restoration, live approval/revocation, confirmed
profile/offer persistence, a deliberately rejected profile transaction and retry,
private dashboards across account switches, and Auth-only registration recovery.
Run with disposable local emulators; the test temporarily tightens a local rule
to reject one profile name and restores the repository rules in `finally`.

```bash
flutter build web --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --output=build/emulator-web
firebase emulators:exec --only firestore,storage,auth --project sandhai-5km-demo "node tool/verify_phase2_browser.cjs"
# Equivalent wrapper with proxy bypass configured
npm run test:browser:emulators
```

Chrome defaults to `/usr/bin/google-chrome`; set `CHROME_EXECUTABLE` to override
it. On hosts with proxy environment variables, prefix emulator test commands
with `env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy=`.

For the SM J810GF device regression, install an emulator-mode APK, configure the
three USB reverse mappings above, start the local emulators, and keep the phone
awake and unlocked. The driver uses existing forms and UI Automator plus
independent Firestore REST reads; it creates synthetic local vendor accounts and
temporarily tightens a local rule for the failure/retry check. It never clears
app data. See the Phase 2 report for the tested toolchain, exact installation and
connectivity commands, artifacts, and results.

```bash
python3 tool/verify_phase2_android.py --adb /absolute/path/to/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-android-verification
```

---

The recorded command results, toolchain details, and complete changed-file list
are in [the Phase 1 baseline report](phase_1_baseline.md) and
[the Phase 2 persistence report](phase_2_persistence.md).

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
│   ├── data/                         # Separate Firebase and demo repositories
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
│   ├── persistence_test.dart          # Session, registration, save/upload failures
│   ├── persistence_widget_test.dart   # Form retry, approval, logout subscriptions
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


## Phase 3: store location, categories, and photos

1. Register/sign in as a vendor. New stores have **no default location**. Approval
   still comes from trusted backend administration (or the local Emulator UI).
2. Open **Business profile → Confirm / edit store location**. Choose **Suggest
   device location**, review or edit both coordinates, check **I confirm this is
   my store location**, then save. Foreground location only; no background tracking.
   Denied permission, permanent denial, disabled services, timeouts, and unsupported
   platforms show errors and allow manual entry. Browser location needs HTTPS or
   localhost. Android location permission is requested only when this button is used.
3. Open **Post Clearance Offer**, select a category, and use **Choose photo**.
   Cancel keeps the previous selection. A valid photo previews before publication.
   Files larger than 5 MiB, images over 40 MP, fake/truncated content, HEIC, GIF,
   and SVG are rejected. Convert unsupported formats before selecting them.
4. Publish while approved. The offer captures the server-confirmed store position.
   A failed upload/save keeps fields and a visible error. Retry uses the same offer
   ID and content-hashed image path. An uncertain commit is read from the server
   before retrying or deleting any object. Confirmed referenced images are protected
   from orphan cleanup. Cleanup failures retain a local pending-upload record and
   report the error; retry reconciles it. Abandoned records are not automatically
   garbage-collected. Full offer editing/deletion remains a subsequent phase.
5. After Android destroys the picker activity, the dashboard offers **Recover
   selected photo and draft**. Review and submit it explicitly. No recovered photo
   or draft is shown to another account. Published offers/photos load on restart.

Stable offer category IDs are `groceries`, `fresh_produce`, `bakery_dairy`,
`snacks_beverages`, `services`, and `other`. Labels are separate. Missing/unknown
legacy categories read as `other`; recognized historical labels map to their ID.
Categories are never guessed from titles/descriptions. Old offers remain readable.
Do not bulk-mark old store coordinates as confirmed: owners must review them.
See [Phase 3 schema and migration notes](phase_3_location_images.md).

### Verification without clearing existing fixtures

Export existing emulators before changing/resetting them. Keep exports outside
tracked source and preserve older exports:

```bash
firebase emulators:export /tmp/sandhai-before-phase3 --config firebase.json --project sandhai-5km-demo
npm test
flutter analyze
flutter test
# Separate ports/project and TMPDIR: clears only its test database.
npm run test:emulators
```

`firebase.phase3-tests.json` uses Firestore 8180, Storage 9299, Auth 9198,
hub 4401, logging 4501, and websocket 9250, with project `sandhai-phase3-tests`.
Do not point the destructive rules suite at retained developer fixtures. Firebase CLI 15.31.0 also shares Storage temporary blobs across projects by default: `tool/test_emulators.sh` isolates TMPDIR as well as ports, keeps its logs in the printed temporary directory, and prevents test shutdown from deleting live Storage files. If you set TMPDIR when starting development emulators, use that same TMPDIR when running `emulators:export` so the CLI can find its hub.

With the ordinary Auth/Firestore/Storage emulators running on 9099/8080/9199:

```bash
flutter build web --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --output=build/emulator-web
SANDHAI_ARTIFACTS=/tmp/sandhai-phase3-browser npm run test:browser:phase3

# Reapply these after reconnecting USB or a test runner removes forwarding.
adb -s 373c972d reverse tcp:9099 tcp:9099
adb -s 373c972d reverse tcp:8080 tcp:8080
adb -s 373c972d reverse tcp:9199 tcp:9199
JAVA_HOME=/absolute/path/to/jdk-21 flutter test integration_test/location_images_test.dart -d 373c972d --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=FIREBASE_EMULATOR_PROJECT_ID=sandhai-5km-demo
```

The browser probe drives Chrome's actual file picker with the public grocery-photo
fixture. Browser geolocation is injected through Chrome's permission/geolocation
API for reproducibility; this does not prove a real browser GPS fix. The native
Dart integration uses a documented coordinate/PNG fixture and real Firebase SDKs.
`tool/verify_phase3_android.py` separately drives the physical foreground-location
permission/GPS and actual Android photo picker. See the Phase 3 report for exact
phone commands, evidence, and any unverified checks. Production remains unverified
until real Firebase configuration is supplied.

## Nearby customer offers (Phase 4)

In emulator/production mode, sign in as a customer and select **Use my location**.
The shared service requests one foreground fix; it does not track in the background.
Enable location services and grant app/browser permission (web requires HTTPS or
localhost). Permission failures expose retry/settings controls. **Update customer
location** replaces the center and subscriptions; pull to refresh or **Refresh
nearby offers** queries the current center again. Search and category chips filter
the bounded candidate set locally. Demo mode alone uses sample offers/distances.

Each Firestore query is:

```dart
FirebaseFirestore.instance.collection('offers')
  .where('status', isEqualTo: 'active').orderBy('geohash')
  .startAt([bound.start]).endAt([bound.end]);
```

`NearbyGeometry` projects the spherical 5,000 m cap to a latitude/longitude
rectangle, splits date-line crossings, and enumerates all intersecting geohash
cells. Precision adapts from 6 down to 1 to keep at most 32 bounds. Prefix ranges
are `[prefix, prefix + '~']`; the stored geohash remains six characters. This
covers the whole radius; nine adjacent stored cells would not. At extreme
latitudes, larger cells mean more false-positive reads. It never issues an
unbounded offers query. The committed composite index is **status ASC, geohash
ASC**, collection scope. Existing vendor indexes remain. Deploy rules/indexes to
your configured staging project and wait for index readiness before cloud testing:

```bash
firebase deploy --only firestore:rules,firestore:indexes --project <staging-project-id>
```

Do not infer cloud index readiness from the emulator: it does not enforce cloud
composite-index availability. No staging/production configuration is currently
available; cloud index verification remains blocked.

Results merge by document ID, apply canonical finite coordinates and confirmation
checks, and sort by unrounded Haversine distance then document ID. The spherical
Earth radius is **6,371,000 m**; inclusion is `distanceMetres <= 5000` and
`expiryTime > now`. Display rounding never determines inclusion. `expiryTime`
is the existing schema field (there is no `expiresAt` rename).

New publications also snapshot `locationConfirmedAt` from the confirmed store;
rules require it to match and preserve it thereafter. Earlier Phase 3 offers
without this field are discoverable only when the current store's confirmed
coordinates/geohash still match and its confirmation predates the publication.
Older sample/unconfirmed positions are excluded. Reconfirming/moving a store can
therefore hide an old marker-less offer; a reviewed matching snapshot can be
backfilled under the rules, or republished in a future offer lifecycle workflow.
Never bulk-confirm legacy coordinates. Missing/unknown categories still use
`other`. Malformed documents are skipped rather than breaking discovery.

The time source is the **customer device/browser wall clock (`DateTime.now`)**,
not an asserted server time. A cancellable timer targets the earliest visible
expiry, capped at one minute for wall-clock adjustment checks and browser timer limits, and checks again on firing; application resume rechecks immediately before
showing offers. Query events also re-evaluate expiry. Correct expiry depends on
a reasonably correct system clock. Tests inject both clock and timer behavior.
Expiry filtering does not modify Firestore or automatically change offer status.

Any bound/vendor-read failure terminates the search and shows an error with retry;
no partial list or mock fallback is presented as a successful empty result. The
initial search requires server-confirmed snapshots and reports a connection error
if those do not arrive within 25 seconds. Refresh, account change and disposal
cancel obsolete watches/timers; generation guards reject late callbacks.

**5 km is a discovery filter, not access control.** Rules still permit direct
reads of active public offers regardless of the reader's distance. Private vendor
dashboard queries remain scoped to that vendor UID.

```bash
flutter test test/nearby_offers_test.dart test/nearby_widget_test.dart
npm run test:emulators
flutter build web --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --output=build/emulator-web
# With the regular developer emulators already running; creates synthetic fixtures
SANDHAI_ARTIFACTS=/tmp/sandhai-phase4-browser npm run test:browser:phase4
JAVA_HOME=/absolute/path/to/jdk-21 flutter test integration_test/nearby_offers_test.dart -d 373c972d --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=FIREBASE_EMULATOR_PROJECT_ID=sandhai-5km-demo
```

For the paired normal-app phone/Chrome probe, set `SANDHAI_PHONE=1` on the browser
command. After its `READY` message, run `tool/verify_phase4_android.py` with
`--adb <absolute-adb-path> --serial 373c972d --artifacts <same-directory>` and
`--stage customer`, then `--stage observe` after `published.json`, and
`--stage expiry` after `expiry-start.json`. Install a normal emulator APK first
and apply all three USB reverse mappings. The customer stage signs out the current
phone account, signs into the synthetic customer, verifies force-close/reopen,
and requests real GPS. Browser positioning is controlled for reproducibility;
`SANDHAI_CENTER` can specify a JSON latitude/longitude near the physical phone.
No production endpoint, app-data reset, or collection reset is involved. Preserve
fixture exports before running probes. See [the Phase 4 report](phase_4_nearby_offers.md)
for recorded device evidence, commands and limitations.

## Phase 4.1 audit and controlled staging

See [phase_4_1_staging_readiness.md](phase_4_1_staging_readiness.md) for actual
verification evidence and [the staging procedure](docs/phase_4_1_staging_procedure.md)
for the approval-gated cloud steps. No dedicated staging project is configured;
emulator success does not verify deployed cloud indexes or production behavior.
Do not use production as a staging substitute or treat `deploy --dry-run` as
read-only (the installed CLI may enable APIs).

Nearby searches use an **inclusive, unrounded distance <= 5,000 m** on a sphere
of radius 6,371,000 m. Device wall time determines expiry; the feed rechecks on
resume and at the next expiry (at most a minute between wall-clock rechecks).
Expiry removes a visible offer without deleting its Firestore document. A
post-confirmation loss of server confirmation lasting five seconds clears
results and shows a retry error; brief query-reconciliation metadata transitions
may recover within that grace window. Expiry filtering continues meanwhile;
reconnect and select **Retry nearby offers**. Initial cached results never
establish a confirmed empty feed. Opening the profile releases nearby listeners;
returning opens a fresh search at the retained center. Changing accounts clears
that center and the previous results.

At most 32 disjoint prefix queries bound the search geographically, but there is
no candidate-document limit: dense areas and coarse polar cells can still be
expensive. This diagnostic generates deterministic local fixtures and records
query, candidate, duplicate and final-result counts; it performs no cloud reads:

```bash
dart run tool/benchmark_nearby.dart
flutter test test/phase_4_1_geospatial_test.dart test/phase_4_1_performance_test.dart
flutter test test/phase_4_1_lifecycle_test.dart test/phase_4_1_lifecycle_widget_test.dart
npm run test:emulators
```

The isolated emulator script now runs both rules files serially, retaining its
unique TMPDIR and separate ports. New publications require a creation timestamp
within five minutes of server request time, future expiry, and a duration at
most 24 hours. Changing expiry cannot extend beyond 24 hours from original
creation. Existing legacy expiry values can remain unchanged on unrelated edits;
legacy reads require no bulk migration. A substantially incorrect device clock
can cause publication rejection; correct the clock and retry the retained form.
Profile updates must retain all required fields and timestamp types.

Rules validate coordinate bounds and geohash format/store equality, not the
mathematical correspondence or physical truth of a vendor's chosen location.
The feed rejects noncanonical coordinate/hash pairs. Approval revocation blocks
new writes/uploads but does not automatically deactivate already active offers.
The 5 km filter is discovery behavior, not an access-control boundary.
