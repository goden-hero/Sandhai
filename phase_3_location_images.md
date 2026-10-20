# Phase 3 — Confirmed store locations, offer categories, and real photos

Date: 2026-10-20. Baseline: `5b91324 Phase-2_Persistence`; working tree was clean
when this phase started. No commits/resets/clean operations were performed.
Existing Phase 1/2 code, temporary evidence, explicit modes, session/account
isolation, and `automaticHostMapping: false` for physical Android USB forwarding
were retained.

## Implementation and schema

### Store location

Registration creates the store **without** latitude, longitude, geohash, or a
confirmation timestamp. Missing model coordinates remain nullable, never a sample
city or `(0,0)`. Finite values within latitude [-90,90] and longitude [-180,180]
are valid, including `(0,0)` **only when explicitly confirmed**. Six-character
base32 geohashes are always derived using `GeohashUtils.encode`.

The shared `LocationService` obtains one foreground fix on request. Denial,
permanent denial, disabled services, timeout, and platform limitations produce
useful errors with retry/manual entry. Web needs HTTPS/localhost. No background
permission, location stream, or background service is requested.

Business profile and the offer form open a location editor. A suggestion never
saves automatically: editing clears consent, and the vendor must check the
confirmation box and save. Firebase writes `locationConfirmedAt` and `updatedAt`
with **server timestamps**. Real native verification found that the phone clock
was about a second ahead; using device time could wrongly reject confirmation as
future-dated. This was fixed. The repository returns only after the transaction
is acknowledged.

Existing coordinates without `locationConfirmedAt`, or with an inconsistent
geohash, remain unconfirmed. A fresh server profile read gates publication. Offers
snapshot the confirmed coordinates/geohash, and rules require that snapshot to
match the confirmed store on creation. Existing offer location fields are
immutable on update, preserving their publication snapshot.

### Offer categories and images

| Field | New writes / compatibility |
| --- | --- |
| `category` | Required stable ID: `groceries`, `fresh_produce`, `bakery_dairy`, `snacks_beverages`, `services`, `other`. UI labels are separate. |
| Legacy category | Missing/unknown maps to `other`; recognized old display labels map to their stable ID. No text/title guessing. |
| `imageUrl` | Required string, empty for an offer without a photo. |
| `imagePath`, `imageContentType`, `imageSize` | All present for a new photo; otherwise absent. Size is persisted as integer bytes. |
| Image path | `offers/{vendorUid}/{offerId}/{sha256}.{jpg|png|webp}`. MIME and extension come from the bytes, never the picker filename. |
| Legacy image | Old URL-only offers remain readable. Updates may retain an unchanged legacy URL; modern records cannot remove metadata to masquerade as legacy records. |

Android/web use `image_picker`, decoded preview, cancellation, replacement, and
removal. Limits: **1–5,242,880 bytes (5 MiB), at most 40,000,000 pixels**, JPEG/PNG/
WebP. Signature + portable header parsing + Flutter codec decoding validate actual
content before upload. GIF, HEIC, SVG, fake and truncated data are rejected. The
original bytes are uploaded, with matching MIME metadata and a SHA-256 custom
metadata value. A real Chrome run found that Flutter web does not implement
`ImageDescriptor.width/height` for encoded images; the validator now reads headers
with the portable `image` package and decodes through `instantiateImageCodec`.

Demo photo data URIs are rendered from memory on Android; Firebase photos retain
normal HTTP loading. A widget regression covers demo rendering without HTTP.

Dart models, serializers, services, forms, dashboard, demo fixtures, and customer
category filtering carry category IDs. Customer discovery stays deferred.

### Save, retry, and recovery

Each form has one document ID. Before picker launch/publication, fields are saved
locally. Draft, picker-owner, and upload-journal keys include mode/project and UID.
Android lost picker data is retrieved on the signed-in vendor dashboard and offered
for explicit recovery with the original draft. A different account cannot consume
that photo. Resuming/new offer navigation respects an existing local draft.

The upload journal records a deterministic candidate before starting Storage.
Retries first reconcile the document on the server. Existing matching image
metadata permits reuse; content-hashed paths prevent duplicate objects and
Storage forbids changing existing photo content. Confirmed absent writes permit
orphan cleanup. Unknown commit outcomes retain the object until reconciliation;
cleanup errors are visible and retain the journal for retry. A referenced photo
cannot be deleted through orphan cleanup. Cleanup after approval revocation is
allowed for the owning vendor, while another vendor's deletion is denied.

Pending UI never reports success. Category and duration controls are disabled
while saving so they cannot diverge from the submitted values. Failures preserve form/photo in the mounted
form and show an inline error near the submit controls plus an error SnackBar.
A confirmed save remains successful even if clearing its local draft fails; a
later same-ID resume reconciles to that saved offer.

### Migration

Deploy the new Firestore/Storage rules together with the updated app. No automatic
bulk migration or approval change is performed. Store owners must review and
confirm legacy coordinates; never add confirmation timestamps blindly to sample
locations. Old offers remain readable. Future edits must supply a stable category;
legacy URL-only images can stay unchanged. No full offer edit/delete UI was added.

Rules validate schema allowlists, types, ownership, category IDs, finite bounded
coordinates, geohash format, matching confirmed store snapshots, positive finite
prices, and image metadata/path consistency. Rules cannot decode image bytes or
mathematically recompute geohashes; the client does those checks. Trusted backend
content scanning is outside this phase.

## Preserved evidence and emulator recovery

All new artifacts are under `/tmp/sandhai-phase3-34qby2tu/`. The source snapshot is
`before/`. Before any cleanup/restart, all live Auth/Firestore/Storage fixtures were
exported with:

```bash
cd /tmp/sandhai-phase3-34qby2tu
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:export /tmp/sandhai-phase3-34qby2tu/before-export --config /home/hisham/projects/sandhai/firebase.json --project sandhai-5km-demo
```

The old Phase 2 CLI process subsequently disappeared during verification, leaving
only its Firestore child running. Interrupted native/browser attempts were marked
failed, never counted as successful. The normal hub export then failed because
the hub/Auth/Storage processes were gone. The surviving current Firestore data
was exported directly before stopping that child:

```bash
mkdir -p /tmp/sandhai-phase3-34qby2tu/surviving-firestore
curl --noproxy '*' -fsS http://127.0.0.1:8080/emulator/v1/projects/sandhai-5km-demo:export -X POST -H 'Content-Type: application/json' -d '{"database":"projects/sandhai-5km-demo/databases/(default)","export_directory":"/tmp/sandhai-phase3-34qby2tu/surviving-firestore","export_name":"firestore_export"}'
```

`restart-import/` combines that current Firestore checkpoint with the preserved
pre-change Auth/Storage export. This retained the existing Phase 2 fixtures and
all surviving Firestore documents. Synthetic Phase 3 Auth accounts created after
the original export were lost when the old process stopped; their Firestore test
documents were retained, and subsequent probes use fresh unique accounts.
No original exports or Phase 2 phone/browser evidence were removed.

The actual repository configuration was restarted with export-on-exit:

```bash
cd /tmp/sandhai-phase3-34qby2tu
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:start --config /home/hisham/projects/sandhai/firebase.json --only firestore,storage,auth --project sandhai-5km-demo --import=/tmp/sandhai-phase3-34qby2tu/restart-import --export-on-exit=/tmp/sandhai-phase3-34qby2tu/recovered-export
```

## Toolchain and automated verification

Flutter **3.47.5**, Dart **3.13.4**, Node **22.23.1**, Firebase CLI **15.31.0**,
Chrome **152.0.7977.82**. Android uses full Temurin JDK **21.0.12.1+1** at
`/tmp/sandhai-phase1-jdk`. New locked packages include geolocator **14.1.2**,
image_picker **1.2.1**, image **4.12.0**, shared_preferences **2.5.6**, crypto **3.0.7**,
and Flutter's integration_test. Firebase dependency versions remain unchanged.
The Android build installed platform **35** and CMake **3.22.1** in addition to
the existing SDK 34/36, build-tools 36, and NDK 28.2 baseline.

Commands run from `/home/hisham/projects/sandhai`, except isolated emulator runs
use the temporary directory above so tracked debug logs remain untouched.

| Exact command | Actual result |
| --- | --- |
| `dart format lib test integration_test` | Passed |
| `flutter analyze` | Passed, zero issues (`analyze-final.log`) |
| `flutter test` | Passed, **43 actual Dart tests** (`flutter-test-final.log`) |
| `npm test` | Passed, existing source-check entry point |
| `node test/widget_and_model_test.js` | Passed, 15 subtests plus parent suite |
| `git diff --check` | Passed |
| `flutter build web --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --output=build/emulator-web` | Passed (`web-emulator-last.log`) |
| `flutter build web --dart-define=APP_MODE=demo` | Passed (`web-demo-last.log`) |
| `env JAVA_HOME=/tmp/sandhai-phase1-jdk flutter build apk --debug --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=FIREBASE_EMULATOR_PROJECT_ID=sandhai-5km-demo` | Passed (`apk-emulator-last.log`) |
| `env JAVA_HOME=/tmp/sandhai-phase1-jdk flutter build apk --debug --dart-define=APP_MODE=demo` | Passed (`apk-demo-last.log`) |

Rules test command, using separate ports/project so retained fixtures are never
cleared:

```bash
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:exec --config /home/hisham/projects/sandhai/firebase.phase3-tests.json --only firestore,storage,auth --project sandhai-phase3-tests 'node --test /home/hisham/projects/sandhai/test/rules.test.js'
```

Result: **24/24 passed** (`rules-final.log`). Coverage includes legacy/unconfirmed
location rejection, partial/invalid/non-finite coordinates, category/schema/type
injection, snapshot mismatch/immutability, image metadata downgrade rejection,
MIME/extension/size checks, immutable image content, approved/pending/revoked
vendors, owner cleanup, referenced-image protection, and cross-vendor deletion
denial. Original auth/completion/isolation tests also pass.

Browser command (ordinary emulators already running):

```bash
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= SANDHAI_ARTIFACTS=/tmp/sandhai-phase3-34qby2tu/browser-accepted node tool/verify_phase3_browser.cjs
```

Result: **15/15 workflow checks passed** on the final source, `browser-accepted.log` and
`browser-accepted/checks.json`. Chrome used actual file selection with the public grocery
photo fixture. It verified permission failure, explicit confirmation, invalid-image
rejection, selected category, preview, deliberately denied Firestore publication,
no false success, orphan cleanup, successful retry, and independent Firestore /
Storage metadata and byte reads. Reload restores the photo/offer. Phase 2 approval,
profile failure/retry, incomplete registration, session restoration, account
isolation, and customer-without-mocks checks passed. Browser geolocation was a
controlled Chrome fixture (11.1,77.2), not a claimed real browser GPS fix.

Native Dart integration command after forwarding all three ports:

```bash
env JAVA_HOME=/tmp/sandhai-phase1-jdk flutter test integration_test/location_images_test.dart -d 373c972d --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=FIREBASE_EMULATOR_PROJECT_ID=sandhai-5km-demo
```

Result: **1/1 passed**, `native-integration-last.log`, covering native Firebase
registration, absent defaults, confirmed coordinate fixture, live approval, real
upload metadata, idempotency and referenced-photo deletion denial. This integration
uses a tiny PNG/coordinate fixture; the separate physical flow below uses real
foreground location and the actual Android picker.

The original Phase 2 browser probe was also run with a separate evidence path:

```bash
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= SANDHAI_ARTIFACTS=/tmp/sandhai-phase3-34qby2tu/phase2-regression node tool/verify_phase2_browser.cjs
```

Result: **11/11 passed**, `phase2-browser-regression.log`. The compatibility
probes now explicitly confirm their documented test coordinates before publishing.
The Phase 2 browser probe accepts an evidence-directory override so its historical
screenshots remain intact.

## Physical Android evidence

SM J810GF, serial `373c972d`, Android 10/API 29. USB forwarding and explicit host
are preserved. The original verified emulator APK was copied before the demo build to:
`/tmp/sandhai-phase3-34qby2tu/sandhai-emulator.apk`, SHA-256
`d3dd5bfa8e4b7042041e9a893fe2d318cd4d4b2b5d7fc386475567b84b1f2dc1`.

```bash
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d install -r /tmp/sandhai-phase3-34qby2tu/sandhai-emulator.apk
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse tcp:9099 tcp:9099
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse tcp:8080 tcp:8080
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse tcp:9199 tcp:9199
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell am start -n com.sandhai.app/com.sandhai.app.MainActivity
python3 tool/verify_phase3_android.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase3-34qby2tu/phone --stage location
python3 tool/verify_phase3_android.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase3-34qby2tu/phone --stage gps
```

Registration created an unlocated pending store. Trusted local fixture setup
changed approval, observed in the active phone session. First foreground permission
request was denied: visible error, no fabricated coordinates. Retrying and allowing
foreground permission produced a real device fix. No mock location provider was
used. The vendor checked consent and saved. Independent uncached Firestore REST
reads verified coordinates, canonical geohash, and server confirmation time.
Evidence: `phone/01-empty-location`, `02-permission-denied`,
`03-device-location-result`, `04-confirmed-store` PNG/XML and `phone/state.json`.
The precise device coordinates stay in the local evidence rather than this report.
The initial driver's field-label wait was corrected to use the screen title;
Android accessibility omitted InputDecoration labels, while the visual UI showed
them. The same account/form was resumed with `--stage gps`, not re-registered.

The photograph is public test data, not a personal phone photo:

```bash
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell mkdir -p /sdcard/Download/Sandhai-Phase3
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d push test/fixtures/grocery-photo.jpg /sdcard/Download/Sandhai-Phase3/grocery-photo.jpg
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Download/Sandhai-Phase3/grocery-photo.jpg
python3 tool/verify_phase3_android.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase3-34qby2tu/phone --stage photo
```

**PASS — all requested physical workflows completed.** The real public JPEG
(180,248 bytes) and `fresh_produce` category were selected on Android. System Back
cancelled selection without losing the draft. While the picker was open, the
background app process was reclaimed with `am kill`; selecting the staged photo
started a different process and the dashboard offered recovery. The original
same-ID draft and photo were restored and reviewed.

```bash
python3 tool/verify_phase3_picker_recovery.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase3-34qby2tu/phone
python3 tool/verify_phase3_android.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase3-34qby2tu/phone --stage finish
```

The first helper executed `adb -s 373c972d shell am kill com.sandhai.app` while
DocumentsUI was foreground, checked that the old PID disappeared, and selected
only `grocery-photo.jpg`. PIDs changed **19682 → 23754**. Evidence:
`06a-recovery-offered` and `06b-recovered-photo-draft` PNG/XML.

The finish helper temporarily denied this synthetic UID's Storage writes through
the local `/internal/setRules` endpoint, then restored the original policy in
`finally`. The phone displayed an upload error, retained its photo/fields, and
created no offer. A separate Firestore deny condition then rejected publication
after upload. The phone again displayed an error and retained inputs; independent
owner-authorized Storage listing confirmed no unreferenced object remained.
Restoring rules and retrying published exactly one offer and photo. An unauthorized
listing is treated as a failed check, never as an empty/successful cleanup.

Independent host REST/byte reads verified the saved real coordinates, `tdr4n5`
geohash, category, content-hashed JPG path, `image/jpeg`, size, and the exact
fixture bytes. Offer **`4VRZR89AQncTGd6iORVj`** belongs to synthetic UID
**`usPQy6S7ZH4zrfX7rMcmukmwXm5w`**. Restart changed PIDs **25206 → 26590**;
the correct signed-in dashboard restored the saved offer and visibly loaded its
photo. The screenshot was visually inspected.

Passing evidence: `phone-finish-3.log`, `phone/state.json` (`result: PASS`),
`06c-upload-denied-retained`, `07-publication-denied`, `08-published-offer`, and
`09-restarted-offer-photo` PNG/XML. Device commands are retained per stage in
`phone/adb-commands-*.json`. Earlier interrupted/failed attempts remain separate
logs and are not counted as passing verification.

The verified phone data was exported immediately to `phone-verified-export/`:

```bash
cd /tmp/sandhai-phase3-34qby2tu
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:export /tmp/sandhai-phase3-34qby2tu/phone-verified-export --config /home/hisham/projects/sandhai/firebase.json --project sandhai-5km-demo
```

After the final demo renderer regression, the native integration was rerun
(`native-integration-last.log`, 1/1 passed) and both APKs rebuilt. The final normal
emulator APK is `sandhai-emulator-final.apk` (SHA-256
`fe10ccad3d6b0d888fc4a10c0eb7c87ae053879751889f2072f7c5805a1d0833`); it was reinstalled and the existing
verified vendor was signed in again using `tool/restore_phase3_phone.py`. A second
force-stop/reopen verified that same saved offer/photo on the final normal build.
The earlier restoration evidence is retained under `phone/before-final-renderer/`.

Final installation/restore command:

```bash
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d install -r /tmp/sandhai-phase3-34qby2tu/sandhai-emulator-final.apk
# Reapply all three USB reverse commands above, then start MainActivity.
python3 tool/restore_phase3_phone.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase3-34qby2tu/phone
```

An `aapt dump permissions` inspection of the installed APK confirmed foreground
coarse/fine location only, with no background-location permission.

The final normal APK was installed after the pending-control fix and signed back
into the same real-photo fixture account. `phone-complete.log` reports PASS,
with PIDs **9570 → 10660**; `10-final-account-restored` and
`11-final-session-restored` PNG/XML show the final source. An additional independent
host process re-read the raw store/offer documents, image metadata and exact bytes,
and confirmed both original Phase 2 Auth UIDs, vendor names, and active/private
offers remain present (`backend-final-recheck.json`, PASS):

```bash
python3 /tmp/sandhai-phase3-34qby2tu/recheck-backend.py
```

The phone remains on the normal **emulator** build, signed into that vendor.
Its original stay-awake setting was restored to `0` and read back as `0`; all
three USB reverse mappings remain available:

```bash
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell settings put global stay_on_while_plugged_in 0
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell settings get global stay_on_while_plugged_in
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse --list
```

Final fixtures (including all current photos/accounts and retained Phase 2 data)
were exported to `/tmp/sandhai-phase3-34qby2tu/final-export`:

```bash
cd /tmp/sandhai-phase3-34qby2tu
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:export /tmp/sandhai-phase3-34qby2tu/final-export --config /home/hisham/projects/sandhai/firebase.json --project sandhai-5km-demo
```

Use this final export for a later emulator restart. Earlier snapshots and failed
probe logs remain available. The final debug server was started with the actual
config, `--debug`, `--import=/tmp/sandhai-phase3-34qby2tu/restart-import-2`, and
`--export-on-exit=/tmp/sandhai-phase3-34qby2tu/recovered-export-2`; its output is
`emulator-debug.log`.

## Limits and remaining verification

- Two unexplained Firebase CLI exits interrupted earlier checks, leaving only
  Firestore alive. A second current Firestore checkpoint is in
  `surviving-firestore-2/`; `restart-import-2/` retains it with the original
  Auth/Storage snapshot. The known synthetic phone account was recreated under
  its **same UID** using the emulator's trusted owner endpoint; its approval/store
  documents were retained. `before-native-denial/` is a complete subsequent
  Auth/Firestore/Storage export including that account. No production account or
  original Phase 2 fixture was recreated/changed. The final debug CLI run passed
  direct resumable-upload 403 checks and the real phone failures/retry; the earlier
  CLI exits have no established cause. Export-on-exit does not replace manual
  checkpoints after an abnormal process exit.
- **Blocked / unverified: production verification**, because real Firebase configuration is unavailable;
  there was no production connection, deployment, or approval bypass.
- Android denial and successful foreground GPS were checked physically. Permanent
  denial, disabled services, timeout, and unsupported-platform outcomes have Dart
  coverage; each combination was not manually reproduced on the phone.
- Browser permission/geolocation is controlled through Chrome's APIs; real browser
  hardware positioning is not established.
- Unpublished photo bytes are not generally persisted across arbitrary process
  restarts. Android lost picker results are recovered; otherwise reselect a photo
  when resuming fields. Pending-upload paths survive and reconcile on retry.
- Abandoned local upload journals/orphans have no scheduled garbage collector.
  Cleanup is conservative, owner-authorized, and retryable; unknown commits retain
  their image. A future maintenance workflow must reconcile before deletion.
- No iOS/desktop runner, discovery, administration, category migration job, or full
  offer edit/delete lifecycle was added.

## Changed files

- `README.md`
- `android/app/src/main/AndroidManifest.xml`
- `firebase.phase3-tests.json`
- `firestore.rules`
- `integration_test/location_images_test.dart`
- `lib/core/constants/offer_categories.dart`
- `lib/core/images/image_selection_service.dart`
- `lib/core/images/offer_draft_store.dart`
- `lib/core/images/selected_image.dart`
- `lib/core/location/location_service.dart`
- `lib/core/location/store_location.dart`
- `lib/core/location/store_location_editor.dart`
- `lib/core/utils/geohash_utils.dart`
- `lib/core/widgets/offer_photo.dart`
- `lib/data/account_repository.dart`
- `lib/data/demo_account_repository.dart`
- `lib/data/demo_offer_repository.dart`
- `lib/data/firebase_account_repository.dart`
- `lib/data/firebase_offer_repository.dart`
- `lib/features/auth/screens/register_vendor_screen.dart`
- `lib/features/auth/services/auth_service.dart`
- `lib/features/customer/screens/customer_home_screen.dart`
- `lib/features/vendor/screens/create_offer_screen.dart`
- `lib/features/vendor/screens/vendor_dashboard_screen.dart`
- `lib/features/vendor/screens/vendor_profile_screen.dart`
- `lib/features/vendor/services/offer_service.dart`
- `lib/mock_data/mock_data.dart`
- `lib/models/offer_model.dart`
- `lib/models/vendor_model.dart`
- `package.json`
- `phase_3_location_images.md`
- `pubspec.lock`
- `pubspec.yaml`
- `storage.rules`
- `test/fixtures/README.md`
- `test/fixtures/grocery-photo.jpg`
- `test/location_images_test.dart`
- `test/location_images_widget_test.dart`
- `test/persistence_test.dart`
- `test/persistence_widget_test.dart`
- `test/rules.test.js`
- `test/support/phase3_fixtures.dart`
- `test/widget_and_model_test.js`
- `tool/restore_phase3_phone.py`
- `tool/verify_phase2_android.py`
- `tool/verify_phase2_browser.cjs`
- `tool/verify_phase3_android.py`
- `tool/verify_phase3_browser.cjs`
- `tool/verify_phase3_picker_recovery.py`

Primary plugin/API references: [Geolocator](https://pub.dev/packages/geolocator),
[image_picker recovery](https://pub.dev/packages/image_picker), the checked-in
Flutter 3.47.5 web UI implementation inspected locally for unsupported descriptor
dimensions, and `test/fixtures/README.md` for photo provenance.
