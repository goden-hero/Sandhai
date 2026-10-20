# Sandhai Phase 2 — Authentication and persistence

Date: 2026-10-20

## Result and scope

Demo and Firebase repositories are separate. Emulator/production errors never
substitute a mock account, profile, upload URL, offer, or dashboard. The existing
explicit `APP_MODE` and emulator host settings remain in place.

The session entry flow restores Firebase Auth, waits for server profile snapshots,
and routes customers, vendors, and incomplete registrations. Session errors have
retry/sign-out controls. Vendor approval is observed continuously; pending,
approved, rejected, and revoked states update without another login. Server
rules and a fresh approval read still authorize publication.

Vendor registration creates the user/store profiles in one online transaction
after Auth creation. Failure after Auth creation keeps the form and authenticated
UID. Retrying completes that UID without creating another account. After restart,
the signed-in account is routed to completion (or can sign in with the same
credentials). Existing roles, approval, and creation timestamps are preserved.

Profile saves update store details and the user display name atomically. Offer
saves use stable form document IDs, online transactions, and server reconciliation
after an uncertain response. Pending UI remains pending until confirmed. Errors
propagate to the screen, retain form values, and permit retry. Upload errors stop
the offer write. Known unreferenced uploads are cleaned up when possible; uncertain
commits retain their image to avoid deleting a referenced object. Storage owners
can delete their uploads after approval revocation.

Vendor dashboards subscribe to persisted Firestore offers using the signed-in
`vendorId` and creation ordering, including private drafts. Loading, empty, and
error/retry states are explicit. Account changes clear session/profile/navigation
state and cancel prior subscriptions. Customer discovery stays deferred and shows
an explicit placeholder in Firebase modes; sample feeds/location/settings are
demo-only. Real image selection stays deferred; Firebase-mode synthetic image
attachment is disabled while byte-upload service behavior is tested separately.

## Web session restoration

The locked `firebase_auth_web 5.15.3` waits for restored Auth during Firebase core
initialization. Connecting the emulator only afterward discarded an unsigned
emulator session on reload. The emulator-only JS adapter initializes Auth with
the same dependency configuration as FlutterFire and immediately connects it to
the selected emulator before restoration. It imports the same JS 11.9.1 modules
used by `firebase_core_web 2.24.1`. Demo never invokes these imports.

This ordering also follows the Firebase SDK's requirement to connect immediately
after Auth initialization. See the [SDK emulator source](https://github.com/firebase/firebase-js-sdk/blob/firebase%4011.9.1/packages/auth/src/core/auth/emulator.ts).
The previous FlutterFire localhost/debug emulator hint is cleared before starting
Firebase so that it cannot override the explicit current mode/host. Recheck this
small adapter and the real browser workflow when upgrading FlutterFire.

## Toolchain

- Flutter 3.47.5 stable, revision `6a19cca564`.
- Dart 3.13.4.
- Chrome 152.0.7977.82.
- Node 22.23.1; Firebase CLI 15.31.0.
- Android build: full Temurin JDK 21.0.12.1+1 at
  `/tmp/sandhai-phase1-jdk`, `javac 21.0.12.1`.
- JavaScript test dependencies: `@firebase/rules-unit-testing 5.0.2`,
  `firebase 12.19.0`, `playwright-core 1.57.0`. The first two align the manifest
  with the versions already present in the supplied lockfile/installation.
- Android runner/SDK configuration and Flutter dependency lockfile retained from
  Phase 1. Samsung SM J810GF, Android 10 / API 29, is available as `373c972d`.

## Verification commands and results

Commands below ran from `/home/hisham/projects/sandhai` unless otherwise noted.

| Exact command | Result |
| --- | --- |
| `dart format lib test` | Passed |
| `flutter analyze` | Passed, zero issues |
| `flutter test` | Passed, 30 real Dart tests |
| `npm test` | Passed, existing source-check entry point |
| `node test/widget_and_model_test.js` | Passed, 15 checks plus parent suite (16 reported) |
| `npm ls --depth=0` | Passed, all three pinned test dependencies resolved |
| `git diff --check` | Passed |
| `flutter build web --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --output=build/emulator-web` | Passed |
| `flutter build web --dart-define=APP_MODE=demo` | Passed; `build/web/` |
| `env JAVA_HOME=/tmp/sandhai-phase1-jdk flutter build apk --debug --dart-define=APP_MODE=demo` | Passed; `build/app/outputs/flutter-apk/app-debug.apk` |
| `node /tmp/sandhai-phase1-web-launch.cjs` | Passed; welcome/navigation, no page errors or Firebase API requests |
| `env JAVA_HOME=/tmp/sandhai-phase1-jdk flutter run -d 373c972d --dart-define=APP_MODE=demo --no-resident` | Passed; built, installed, and started on SM J810GF / Android 10 |
| `/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d exec-out screencap -p > /tmp/sandhai-phase2-android-demo.png` | Passed; screenshot visually confirms the welcome screen and demo-mode banner |

The final Firebase rules/browser command is:

```bash
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:exec --only firestore,storage,auth --project sandhai-5km-demo "node --test /home/hisham/projects/sandhai/test/rules.test.js && node /home/hisham/projects/sandhai/tool/verify_phase2_browser.cjs"
```

It runs from `/tmp/sandhai-phase2-emulators-0psj7ttb`, containing copies of the
repository's Firebase configuration/rules/indexes. This keeps generated emulator
logs out of the pre-existing tracked log. The scripts load current rules from the
repository. Final result: **20/20 emulator tests and all 11 customer/vendor browser
workflow checks passed**, including the stale-host regression. Emulator
permission-denied messages are expected negative-test output.

The browser probe drives the compiled Flutter UI with Chrome and real Firebase
Auth/Firestore emulators. Test-only privileged SDK contexts seed isolated fixtures,
observe saved documents, and change approval; the application has no test bridge.
It checks:

1. A stale remembered FlutterFire host cannot override the selected configuration.
2. UI vendor registration creates both profiles with pending approval.
3. Reload restores the pending vendor session.
4. Approval changes to approved appear during the active session.
5. A published offer is confirmed in Firestore and survives reload.
6. A deliberately rejected profile transaction shows an error, retains the edited
   value, shows no success, and changes neither profile document.
7. Restoring the original local rules and retrying confirms the save; reload
   preserves the updated profile.
8. Revocation disables publication without another login.
9. Logout/account switch removes vendor A's data and shows only vendor B's private
   dashboard offer.
10. An Auth-only interrupted registration survives reload and completes under its
    original UID, with pending approval and no duplicate account.
11. A customer registers, reloads into the customer flow, and sees actual profile
    data with no sample offers, mock location, or synthetic notification setting.

The denial check temporarily tightens one rule in disposable emulators; `finally`
restores the repository rules. Screenshot: `/tmp/sandhai-phase2-browser.png`.
The demo Chrome probe checks welcome/navigation, zero page errors, and zero
Firebase API requests. Its screenshots are
`/tmp/sandhai-phase1-chrome-welcome.png` and
`/tmp/sandhai-phase1-chrome-registration.png`.

Normal developer commands, mode selection, emulator export/import, and the
reproducible browser test command are documented in `README.md`. The npm emulator
wrappers now use the explicitly installed Firebase CLI, without fetching latest
on each test run.

## Physical Android follow-up — 2026-10-20

Device: Samsung SM J810GF, serial `373c972d`, Android 10 / API 29,
720 × 1480 display. This follow-up uses real Android UI interactions and
force-stops, with independent, uncached Firestore REST requests from the host.
It does not infer persistence from the phone's displayed/cached values.

### Defects found and fixed

1. FlutterFire's default `automaticHostMapping` rewrote an explicit native
   `127.0.0.1` host to `10.0.2.2`. USB reverse forwarding therefore did not reach
   the Auth emulator; phone registration timed out with a network error.
   `bootstrap.dart` now passes `automaticHostMapping: false` for Auth, Firestore,
   and Storage. `AppConfig` retains the Android emulator default `10.0.2.2`,
   and explicit physical-device/browser/LAN hosts are used as configured.
2. A registration error was stored in a banner above the scrolled phone viewport,
   leaving no visible failure near the submit button. Auth, completion, profile,
   and offer forms now also show an error SnackBar, retain their fields, and clear
   obsolete feedback on retry. The narrow-form regression verifies that a failed
   registration is visibly reported and retry reuses the Auth account. Vendor
   category controls also expand to the available width; category data is unchanged.

### Exact setup and verification commands

The existing working tree was snapshotted at
`/tmp/sandhai-android-phase2-before-vkfjgab8/`. No app data was cleared and no
existing accounts or offers were deleted. The Firebase configuration/rules/indexes
remain byte-for-byte unchanged from that snapshot.

The emulators run with the actual repository configuration and project, from a
temporary working directory so existing tracked debug logs are preserved:

```bash
cd /tmp/sandhai-phase2-android-hik2zdnv
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:start --config /home/hisham/projects/sandhai/firebase.json --only firestore,storage,auth --project sandhai-5km-demo
```

From `/home/hisham/projects/sandhai`, the physical device uses USB reverse ports
and the explicit loopback host (not the Android virtual-device alias):

```bash
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse tcp:9099 tcp:9099
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse tcp:8080 tcp:8080
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse tcp:9199 tcp:9199
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse --list
env JAVA_HOME=/tmp/sandhai-phase1-jdk flutter build apk --debug --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=FIREBASE_EMULATOR_PROJECT_ID=sandhai-5km-demo
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d install -r /home/hisham/projects/sandhai/build/app/outputs/flutter-apk/app-debug.apk
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell am force-stop com.sandhai.app
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell am start -n com.sandhai.app/com.sandhai.app.MainActivity
python3 tool/verify_phase2_android.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase2-android-hik2zdnv/final
```

The phone was kept awake/unlocked for UI automation using `shell input keyevent
KEYCODE_WAKEUP`, `shell wm dismiss-keyguard`, and `shell svc power stayon true`.
The original `stay_on_while_plugged_in` value was `0`; after verification it was
restored and read back as `0` with:

```bash
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell settings put global stay_on_while_plugged_in 0
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell settings get global stay_on_while_plugged_in
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell getprop ro.build.version.sdk
```

The device API query returned `29`. ADB/platform-tools version was
`37.0.1-15733141` (ADB 1.0.41). Android's initial install/start can race package cleanup, and
this phone needs roughly 12 seconds for a cold Flutter startup. The driver retries
a null UI Automator root and only accepts a freshly dumped hierarchy. It does not
reuse XML from an earlier screen or count an `am start` return as a restored session.

Phone screenshots/XML, the complete executed ADB argument list, process IDs, and
independent server document snapshots are written under the artifact directory.
`result.json` is the machine-readable result; `adb-commands.json` records every
device command. The REST client reads
`http://127.0.0.1:8080/v1/projects/sandhai-5km-demo/databases/(default)/documents/…`
directly, with emulator-only owner authorization and no Firestore client cache.
The failed-save check temporarily adds a deny condition for one synthetic name
through the local emulator's `:securityRules` endpoint, verifies both documents
remain unchanged, and restores the original repository rules in `finally`.

### Follow-up results

**PASS — all five requested phone workflows completed.** The driver exited `0`
with six passing assertion groups, retaining all accounts and app data.

| Requested check | Actual device/server result |
| --- | --- |
| Register/sign in, force-close, reopen, correct routing | Both vendors registered through the phone. Pending registration restored to the pending vendor dashboard; approved sessions restored to the approved dashboard with the correct account and offers. Existing accounts were signed into again through the phone sign-in form. |
| Approval changes during an active session | Vendor A changed pending → approved → suspended → approved through emulator REST while the phone remained signed in. The badge and publication control updated without login; revocation disabled publication. |
| Saved profile and offer persist | Vendor A's profile name and both vendors' offers were saved through the existing phone forms. Force-stop/reopen retained them. Separate uncached REST reads confirmed `users`, `vendors`, and `offers` documents; a second host process used curl to recheck both vendors and raw server `updateTime` values. |
| Failed save and retry | A temporary emulator rule rejected one profile name. The phone displayed the server error and retained that name, without a success message. Independent reads proved both profile documents were unchanged. Restoring the original rule and retrying the same values saved both documents; the result survived another force-stop/reopen. |
| Two-account isolation and clearing | A → B → A → B sign-ins showed only the current vendor's offer. Logout returned to the emulator welcome screen with neither prior offer. Vendor B's private draft persisted across restart and was absent from vendor A's dashboard. |

Five asserted restoration transitions changed process IDs:
`17596 → 18896` (pending vendor A), `18896 → 20204` (saved A data),
`20204 → 20833` (retried profile), `20833 → 23035` (vendor B/private draft),
and `23035 → 23868` (vendor A after signing in again). The driver also performed
a preliminary restart before creating this run's accounts.

| Local fixture | Firebase Auth UID | Offer document |
| --- | --- | --- |
| `android-a-1792500988@example.com` | `SNpI0w68gZdWWasYRXpxwEEmEcuV` | `Mc062YgSm8KUOsCVa6QO` (`active`) |
| `android-b-1792500988@example.com` | `2m5MR6cyBytmY7wI2JvZIQFJEXzg` | `f5uFK7N246k3EmA0ahsT` (`draft`) |

The synthetic local fixture password is `AndroidPhase2Pass123`. Final store names
are `Android Retried A 1792500988` and `Android Store B 1792500988`.
Vendor B's offer was first published through the phone and checked as active,
then marked draft through emulator REST to test private dashboard isolation.

Evidence is in `/tmp/sandhai-phase2-android-hik2zdnv/final/`:

- `result.json`: assertions, UIDs, offer IDs, process transitions, and before/after
  server document snapshots.
- `adb-commands.json`: the complete device command argument list.
- `server-recheck.json`: fresh raw curl responses for both user/store profiles and
  offers, including server creation/update timestamps.
- `03-a-pending-restored.png`, `04-a-live-approved.png`, `05-a-live-revoked.png`.
- `08-a-data-restored.png`, `09-a-save-denied-input-retained.png`,
  `10-a-retry-confirmed.png`.
- `11-b-only-private-offer.png`, `12-switched-back-a-only.png`,
  `13-switched-back-b-only.png`, with matching fresh UI hierarchy XML files.

The second independent check used these actual GET requests (and equivalent paths
for the vendor profiles and vendor B's documents), outside the phone and driver:

```bash
curl --noproxy '*' --fail --silent -H 'Authorization: Bearer owner' 'http://127.0.0.1:8080/v1/projects/sandhai-5km-demo/databases/(default)/documents/users/SNpI0w68gZdWWasYRXpxwEEmEcuV'
curl --noproxy '*' --fail --silent -H 'Authorization: Bearer owner' 'http://127.0.0.1:8080/v1/projects/sandhai-5km-demo/databases/(default)/documents/offers/Mc062YgSm8KUOsCVa6QO'
```

The recheck confirmed vendor A's final profile name and active offer with server
offer update time `2026-10-20T13:00:14.532937Z`, and vendor B's name/private draft
with update time `2026-10-20T13:04:08.364703Z`.

| Exact regression command | Result |
| --- | --- |
| `flutter analyze` | Passed, zero issues |
| `flutter test` | Passed, 31 Dart tests |
| `npm test` | Passed |
| `python3 -m py_compile tool/verify_phase2_android.py` | Passed; Python 3.14.8 |
| Emulator-mode APK command above | Passed; installed on the device |
| `flutter build web --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --output=build/emulator-web` | Passed |
| `flutter build web --dart-define=APP_MODE=demo` | Passed |
| `env JAVA_HOME=/tmp/sandhai-phase1-jdk flutter build apk --debug --dart-define=APP_MODE=demo` | Passed; the installed phone build remains emulator mode |
| Phone driver command above | Passed, all five requested workflows / six assertion groups |

The browser regression was rerun against the same running emulators, using
separate synthetic accounts and preserving the phone's documents:

```bash
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= node tool/verify_phase2_browser.cjs
```

Result: **PASS, all 11 browser checks**, including reload, denied-save retry,
registration completion, and customer routing. The rules suite was not rerun
against this retained phone dataset because its setup clears Firestore; the
20-test result above remains the earlier rules verification, and the rules files
are unchanged in this follow-up.

The verified emulator data was exported successfully, from the temporary working
directory, using:

```bash
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:export /tmp/sandhai-phase2-android-hik2zdnv/emulator-export --config /home/hisham/projects/sandhai/firebase.json --project sandhai-5km-demo
```

Export metadata confirms Auth, Firestore, and Storage exports. The emulators and
the three USB reverse mappings are left running for inspection; Emulator UI is
`http://127.0.0.1:4000`. The phone remains signed into vendor B in emulator mode,
with its original stay-awake setting restored. The final local
`build/app/outputs/flutter-apk/app-debug.apk` artifact was rebuilt in emulator
mode with the exact host/project defines above. Demo web/APK regression builds
also passed as recorded in the table.

To restore this dataset after stopping the current emulators, use the same start
command with
`--import=/tmp/sandhai-phase2-android-hik2zdnv/emulator-export`. This is a temporary
validation-host export, not committed application data.

Follow-up changed files: `lib/app/bootstrap.dart`,
`lib/core/widgets/operation_error.dart`, the auth registration/sign-in/completion
screens, vendor profile/offer forms, `test/persistence_widget_test.dart`,
`tool/verify_phase2_android.py`, `tool/verify_phase2_browser.cjs` (error text selector
accepts inline and SnackBar feedback), `.gitignore` (Python cache), `README.md`, and
this report. Production, location collection, real image selection, and nearby
discovery were not implemented or deployed in this follow-up.

## Remaining limits and unverified behavior

- Production end-to-end verification remains **unverified because production Firebase
  configuration is unavailable**. Placeholder options continue to produce a visible startup
  error. No production resources/rules were deployed.
- The requested vendor authentication/persistence flows are now **verified on the
  SM J810GF against local emulators**, as recorded above. Native customer routing
  and incomplete-registration recovery were not exercised in this follow-up;
  their existing Dart/browser coverage is recorded in the initial verification.
- Offline transactions cannot confirm saves. The SDK may keep retrying while
  offline; pending UI remains pending. Unsaved form values survive an operation
  failure while mounted, not a process restart. Emulator CLI restarts require
  export/import to retain emulator data.
- Real image selection, real location collection, nearby discovery, administration,
  and category migration remain deferred. Existing registration coordinate
  defaults remain a known limitation; missing stored coordinates are no longer
  synthesized while reading a vendor profile.
- Upload failure/cleanup is covered by Dart service tests and Storage emulator
  rules tests. A real image picker/upload from a device is unverified because that
  UI remains deferred. Cleanup after an unavailable/uncertain outcome is best
  effort and can leave an orphaned Storage object.
- Android builds on this host need the full JDK override above; the default Java
  installation is runtime-only. The temporary JDK is not a repository dependency.

## Working-tree preservation

Repository instructions, README, Phase 1 report, and git status were inspected
before changes. No applicable AGENTS.md was found. The initial working tree and
diff are preserved in `/tmp/sandhai-phase2-before-9eefmn6_/`. No reset, clean, or
commit was performed by this work. A checkpoint commit appeared during the task;
the file inventory below compares with the start-of-phase snapshot, rather than
assuming that HEAD represents that starting state.

`firebase.json`, `firestore.indexes.json`, `pubspec.yaml`, and `pubspec.lock` were
checked byte-for-byte against that snapshot and retained. The pre-existing
architecture/task documents and tracked Firebase debug log were not edited.

## Files changed by this phase

- `README.md`
- `phase_1_baseline.md` (append user-reported device confirmation)
- `phase_2_persistence.md` (this report)
- `package.json`, `package-lock.json`
- `firestore.rules`, `storage.rules`
- `lib/app/app.dart`, `lib/app/bootstrap.dart`, `lib/app/router.dart`
- `lib/app/web_emulator_auth.dart`, `lib/app/web_emulator_auth_web.dart`
- `lib/core/constants/offer_categories.dart`, `lib/core/errors/app_failure.dart`
- `lib/data/account_repository.dart`, `lib/data/firebase_account_repository.dart`,
  `lib/data/demo_account_repository.dart`
- `lib/data/offer_repository.dart`, `lib/data/firebase_offer_repository.dart`,
  `lib/data/demo_offer_repository.dart`
- `lib/features/auth/services/auth_service.dart`
- `lib/features/auth/screens/session_gate.dart`,
  `lib/features/auth/screens/sign_in_screen.dart`,
  `lib/features/auth/screens/register_customer_screen.dart`,
  `lib/features/auth/screens/register_vendor_screen.dart`
- `lib/features/customer/screens/customer_home_screen.dart`
- `lib/features/profile/screens/profile_screen.dart`
- `lib/features/vendor/services/offer_service.dart`
- `lib/features/vendor/screens/create_offer_screen.dart`,
  `lib/features/vendor/screens/vendor_dashboard_screen.dart`,
  `lib/features/vendor/screens/vendor_profile_screen.dart`
- `lib/models/user_model.dart`, `lib/models/vendor_model.dart`
- `lib/models/offer_model.dart`, `lib/mock_data/mock_data.dart` (formatting only)
- `test/persistence_test.dart`, `test/persistence_widget_test.dart`,
  `test/support/fakes.dart`, `test/rules.test.js`, `test/widget_and_model_test.js`
- `tool/verify_phase2_browser.cjs`
- `web/index.html`, `web/firebase_emulator_bootstrap.js`
