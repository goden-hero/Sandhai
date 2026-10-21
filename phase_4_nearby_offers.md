# Phase 4 — Persisted nearby offers and immediate expiry

Implemented 2026-10-20/21, starting from `0c82de0` (Phase 3). The working tree
was clean. Repository/parent instructions, README, Phase 3 report, models, rules,
indexes and git status were inspected first; no AGENTS.md was present. No commits,
resets, app-data clears or developer collection resets were performed. Explicit
application modes, restored sessions, private vendor dashboards, foreground-only
location, real photo publication and USB `automaticHostMapping: false` remain.

## Query and schema decisions

`NearbyGeometry` covers the bounding rectangle of a spherical 5,000 m cap.
Latitude is clamped at the poles; longitude uses `asin(sin(radius/R)/cos(lat))`,
with full longitude at a pole and split intervals across the antimeridian. Small
padding expands **bounds only**, never the distance test. All intersecting cells
are enumerated, adapting geohash precision from 6 to 1 until at most 32 prefixes
cover the rectangle. Stored hashes remain precision 6. This does not assume nine
adjacent stored cells cover 5 km; typical queries use larger precision-5 cells.
At high latitudes, coverage remains complete but coarse cells increase false
positives/read cost.

Each prefix opens this collection-scoped query:

```dart
collection('offers').where('status', isEqualTo: 'active')
  .orderBy('geohash').startAt([prefix]).endAt(['$prefix~']);
```

The committed new composite index is **status ASC, geohash ASC**. Existing vendor
and category indexes are preserved. No unbounded offers query or vendors scan is
used by the customer feed. Categories/search filter the bounded candidate set in
memory. `active` is the existing published status; the existing **`expiryTime`**
field remains the expiry timestamp, without an `expiresAt` schema rename.

Server-acknowledged snapshots are diffed separately per bound. Cache-only/pending
snapshots cannot establish a successful empty result or overwrite acknowledged
rows. A complete initial search waits for every bound and required legacy vendor
lookup, with a 25-second connection timeout. A bound/vendor error terminates all
watches and produces an explicit retryable error, never partial/empty success.
Overlapping results merge by document ID; unchanged snapshots do not overwrite a
newer version. Removal handling preserves a newer move that already arrived in
another bound and prevents deleted overlap members from resurrecting a record.

Candidates require active status, real required timestamps, valid finite flat
coordinates, a canonical six-character geohash, valid prices/field types,
confirmed location evidence, unrounded distance <= 5,000 m, and expiry strictly
later than now. Malformed records are skipped without taking down the feed.
Nearest distance sorts first, then document ID breaks ties deterministically.
Display rounding never controls inclusion. Real HTTP photos and stored category
IDs are shown; only demo mode uses samples or fabricated display distances.

New offers snapshot **`locationConfirmedAt`** from the store alongside immutable
coordinates/geohash. Rules allow this optional field for older-client
compatibility, require a provided marker to equal the confirmed store on create,
and forbid removing/changing an existing marker. A reviewed matching legacy offer
can acquire it under the rules. Earlier Phase 3 offers without a marker require a
bounded public vendor-document watch: the current confirmed store must still
match the offer's coordinates/hash, and confirmation must predate publication.
This excludes older sample positions confirmed only after publication. Moving or
reconfirming a store can hide a marker-less old offer; any backfill must review
its location and supply the currently required schema/category. No bulk migration
or blind confirmation was performed. New marker-bearing publication snapshots
remain valid when the store later moves.

**5 km is discovery filtering, not access control.** Existing rules still allow
direct reads of active public offers from any distance. Private draft/dashboard
reads retain their existing UID protections; a rule test proves both behaviors.

References: [Firebase geohash queries](https://firebase.google.com/docs/firestore/solutions/geoqueries)
and [Firestore index management](https://firebase.google.com/docs/firestore/query-data/indexing).
The local implementation uses the existing flat schema rather than introducing a
nested geospatial field or downloading the collection.

## Location, lifecycle and time

Customers explicitly select **Use my location**. The shared foreground service
handles permission/service/platform/timeout failures; the screen exposes loading,
location error/settings, query error/retry, empty, search/category and refresh
states. Updating location replaces the center; refresh uses the existing center.
Account changes clear location/results and invalidate pending location futures.
Searches own their query/vendor subscriptions and expiry timer. Generation and
vendor-watch tokens reject late callbacks; disposal/logout/refresh cancel obsolete
work. Tests deliberately invoke captured callbacks after cancellation/disposal.

Time comes from **`DateTime.now()` on the customer device/browser**, not a claimed
server clock. The next-expiry timer rechecks the earliest included expiry, capped
at one minute to detect wall-clock changes and avoid browser timer overflow for
far-future legacy timestamps. Each event and application resume rechecks expiry.
No Firestore write or status automation is required. The injected `NearbyClock`
controls both time and scheduling for deterministic tests; resume is also tested
through Flutter lifecycle transitions. Correct expiry depends on system time.

Native integration uncovered an actual cancellation hang in an `async* await for`
adapter while a Firestore stream was quiet. That attempt was interrupted and is
recorded as failed (`native-nearby.log`), not counted as passing. The adapter now
uses `Stream.multi` and forwards cancellation directly, including without another
SDK event. A regression covers quiet cancellation, cache-to-server initial
snapshots, pending acknowledgements and removals.

## Preserved fixtures and emulator isolation

All evidence is under **`/tmp/sandhai-phase4-a8hxyt6g/`**; pointer:
`/tmp/sandhai-phase4-current`. `before.tar` archives the clean starting revision.
Before changes, the running actual project was exported:

```bash
cd /tmp/sandhai-phase4-a8hxyt6g
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:export /tmp/sandhai-phase4-a8hxyt6g/before-export --config /home/hisham/projects/sandhai/firebase.json --project sandhai-5km-demo
```

A CLI 15.31.0 defect was diagnosed during verification: separate ports/projects
still share `os.tmpdir()/firebase/storage/blobs`. Isolated Storage test shutdown
deleted blobs needed by the live suite, causing an ENOENT and a CLI exit. The
surviving current Firestore data was checkpointed **before** stopping its orphan:

```bash
mkdir -p /tmp/sandhai-phase4-a8hxyt6g/surviving-firestore
curl --noproxy '*' -fsS http://127.0.0.1:8080/emulator/v1/projects/sandhai-5km-demo:export -X POST -H 'Content-Type: application/json' -d '{"database":"projects/sandhai-5km-demo/databases/(default)","export_directory":"/tmp/sandhai-phase4-a8hxyt6g/surviving-firestore","export_name":"firestore_export"}'
kill -TERM 109209
```

`restart-import/` combines that latest Firestore export with the pre-change
Auth/Storage export. Original fixtures were retained; Auth accounts created only
by the first failed Phase 4 probe after the checkpoint were lost in that CLI
exit, while their Firestore records remain. No original account was recreated.
The actual configured suite was restored with its own temporary directory:

```bash
cd /tmp/sandhai-phase4-a8hxyt6g
env TMPDIR=/tmp/sandhai-phase4-a8hxyt6g/live-tmp NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:start --debug --config /home/hisham/projects/sandhai/firebase.json --only firestore,storage,auth --project sandhai-5km-demo --import=/tmp/sandhai-phase4-a8hxyt6g/restart-import --export-on-exit=/tmp/sandhai-phase4-a8hxyt6g/recovered-export
```

`tool/test_emulators.sh` now gives every rules run a separate TMPDIR **and** the
existing isolated ports/project. It retains logs in the printed temporary folder.
A full rules run then completed while the live suite remained healthy; a new
`recovery-checkpoint/` export succeeded. `preservation-check.json` independently
confirms both original Phase 2 Auth UIDs/store names and the Phase 3 Auth UID,
plus exact bytes of the original 180,248-byte grocery JPEG (SHA-256
`cebf8f3e186790c2705a31759b214bb5bfa29ffd1d72b1f7722addf4ebc55263`).
All earlier Phase 2/3 exports/screenshots and unsuccessful probe evidence remain.

## Distance fixture evidence

Spherical model: R = **6,371,000 m**. `tool/nearby_fixture_evidence.py` independently
uses 3-D unit-vector cross/dot `atan2` distance, rather than the app's Haversine.
`independent-distances.json` records:

| Center | Fixture latitude, longitude | Independent metres | Expected |
| --- | --- | --- | --- |
| 0, 0 | 0.044876148135344655, 0 | 4,990.0 | Include |
| 0, 0 | 0.044966080295936524, 0 | 5,000.0 | Include |
| 0, 0 | 0.045056012456528396, 0 | 5,010.0 | Exclude |

```bash
python3 tool/nearby_fixture_evidence.py > /tmp/sandhai-phase4-a8hxyt6g/independent-distances.json
```

The Dart coverage test checks 120 bearings at four distances for five centers
(equator, physical-store vicinity, date-line crossing, near south pole, north pole):
**2,400 projected targets**. Other tests cover deduplication/overlap, moves between
bounds, removal, inactive/expired offers, malformed values, legacy confirmation,
clock/timer expiry without events, resume, location changes, stale callbacks,
account switches, quiet cancellation, query failure/retry, category filtering,
real-photo rendering and separate permission/loading/empty/error states.

## Verification commands and results

Toolchain: Flutter **3.47.5**, Dart **3.13.4**, full Temurin JDK **21.0.12.1+1**
(`/tmp/sandhai-phase1-jdk`), Node **22.23.1**, Firebase CLI **15.31.0**,
Chrome **152.0.7977.82**. SM J810GF serial **373c972d**, Android **10 / API 29**.
Firebase SDK versions remain unchanged; `fake_async 1.3.3` is now an explicit test
dependency (already locked transitively before this phase).

Commands below run from the repository root unless noted.

| Exact command | Result |
| --- | --- |
| `dart format lib test integration_test` | Passed |
| `flutter analyze` | Passed, zero issues (`analyze-final.log`) |
| `flutter test` | Passed, **56 Dart/widget tests** (`flutter-test-final.log`) |
| `npm test` | Passed, **16 checks** (`npm-test-final.log`) |
| `npm run test:emulators` | Passed, **26 rules tests**, isolated ports/TMPDIR (`rules-isolated.log`) |
| `flutter build web --dart-define=APP_MODE=demo` | Passed (`web-demo-final.log`) |
| `JAVA_HOME=/tmp/sandhai-phase1-jdk flutter build apk --debug --dart-define=APP_MODE=demo` | Passed (`apk-demo-final.log`) |
| `flutter build web --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --output=build/emulator-web` | Passed (`web-emulator-final.log`) |
| `JAVA_HOME=/tmp/sandhai-phase1-jdk flutter build apk --debug --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1` | Passed (`apk-emulator-final.log`) |
| `JAVA_HOME=/tmp/sandhai-phase1-jdk flutter test integration_test/nearby_offers_test.dart -d 373c972d --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=FIREBASE_EMULATOR_PROJECT_ID=sandhai-5km-demo` | Passed, 1 native test in 15 seconds after installation (`native-nearby-fixed.log`); includes quiet cancellation, live move/removal, timer expiry and warm-cache re-subscription |
| `JAVA_HOME=/tmp/sandhai-phase1-jdk flutter test integration_test/location_images_test.dart -d 373c972d --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=FIREBASE_EMULATOR_PROJECT_ID=sandhai-5km-demo` | Passed, 1 existing native test in 17 seconds after installation (`native-images-regression.log`); registration, confirmed location, real SDK upload metadata and idempotent publication |
| `env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= SANDHAI_ARTIFACTS=/tmp/sandhai-phase4-a8hxyt6g/browser-final node tool/verify_phase4_browser.cjs` | Passed, 5 grouped Chrome checks (`browser-final.log`, `browser-final/checks.json`) |
| `env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= SANDHAI_ARTIFACTS=/tmp/sandhai-phase4-a8hxyt6g/phase3-regression node tool/verify_phase3_browser.cjs` | Passed, 15 existing browser checks (`phase3-browser-regression.log`) |
| `env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= SANDHAI_ARTIFACTS=/tmp/sandhai-phase4-a8hxyt6g/phase2-regression node tool/verify_phase2_browser.cjs` | Passed, 11 existing browser checks (`phase2-browser-regression.log`) |

Incomplete/failed attempts are not counted as passes. The photo integration's
first installation was interrupted by USB disconnection (`native-images-usb-interrupted.log`);
the connected device was detected again and all three reverse mappings reapplied
before retrying.

## Device/browser evidence

Normal phone installation and actual USB connectivity commands:

```bash
cp build/app/outputs/flutter-apk/app-debug.apk /tmp/sandhai-phase4-a8hxyt6g/sandhai-emulator-final.apk
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d install -r /tmp/sandhai-phase4-a8hxyt6g/sandhai-emulator-final.apk
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse tcp:9099 tcp:9099
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse tcp:8080 tcp:8080
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse tcp:9199 tcp:9199
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell svc power stayon true
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell am start -n com.sandhai.app/.MainActivity
```

Chrome's controlled geolocation is based near the previously measured real
physical store fix; it is **not** a claim of browser hardware GPS. The phone
requests actual foreground GPS through the shared service without an app bridge
or injected native location. Separate Chrome vendor/customer contexts and the
phone customer use the same `sandhai-5km-demo` project.

### Recorded paired flow and expiry

The paired flow used the **final matching normal emulator APK/web build**:

```bash
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= SANDHAI_ARTIFACTS=/tmp/sandhai-phase4-a8hxyt6g/paired-complete SANDHAI_PHONE=1 node tool/verify_phase4_browser.cjs
python3 tool/verify_phase4_android.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase4-a8hxyt6g/paired-complete --stage customer
python3 tool/verify_phase4_android.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase4-a8hxyt6g/paired-complete --stage observe
python3 tool/verify_phase4_android.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase4-a8hxyt6g/paired-complete --stage expiry
python3 tool/verify_phase4_android.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase4-a8hxyt6g/paired-complete --stage resume
```

All four Android stages **passed**. The first customer attempt found the phone's
launcher in front; the driver now explicitly brings MainActivity forward before
checking the session. Its failed log/ADB commands are retained. Customer force-close/
reopen changed PIDs **23058 → 25304**, restored the correct customer route, and
requested real foreground GPS. A Chrome vendor confirmed its suggested point,
selected the actual grocery JPEG/category and published through the real form.
The new photo offer appeared live in the separate Android and Chrome customer
sessions. A separately projected 10 km north fixture was excluded. Groceries
filtering hid the Fresh Produce offer; All restored it. The picture was inspected
in `android-02-live-photo-nearby.png`, and the final chip contrast was corrected.

A deliberately denied **new** bound query on Chrome showed an error, then retry
and a location replacement restored results. Fresh bounds are deliberate: emulator
rule changes need not re-authorize an already active SDK target. The owner endpoint
then shortened the real offer's expiry once to `2026-10-20T18:41:18.846Z`.
Both foreground customer feeds removed it without refresh or another write.
`paired-complete/independent-expiry-proof.json` contains before/after backend
reads with unchanged **updateTime `2026-10-20T18:40:18.900223Z`**, status still
`active`, plus the Android PASS result.

The paired Chrome automation exited at an **incorrect exact-text selector after
expiry had already succeeded**: Flutter merged the empty-state text into an
accessibility group label. Its preserved `failure-1.png` and `failure-1.html`
visibly/semantically show the empty feed and absence of the offer. This is not
reported as an automated paired-script PASS. Manual screenshot/DOM inspection and
the independent unchanged backend read establish that step; after fixing the
selector, the entire separate final Chrome probe passed, including expiry,
reload, new bounds, and the 4.99/5.00/5.01 km fixtures. Earlier failed selector and
pre-fix attempts remain in `paired*` evidence directories.

For the physical background check, the trusted fixture extended that **same real
publication** once. It appeared, Android HOME was pressed, it expired while in the
background, and reopening MainActivity removed it with no refresh. The backend
remained active with updateTime **`2026-10-20T18:42:51.544960Z`** unchanged during
that window; `phone-background.json` and `android-04/05` PNG/XML record PASS.
No write occurred during either expiry window; the second setup write is recorded
separately from the first window's evidence. No customer edit/delete feature was
introduced to create this short-lived fixture.

`boundary-backend.json` independently reads the final browser's three raw fixture
documents and recalculates **4990.0, 5000.0, 5010.0 metres**, with inclusion
**true, true, false**, through the Python vector-distance calculator. Chrome
`chrome-radius-boundaries.png` and the probe assertions show the first two and
exclude the third. Browser-controlled positioning is test setup; the real phone
GPS and existing Phase 3 physical store-fix evidence are separate.

### Final restoration and export

Both native tests passed after the fixes/reconnection. The phone was restored to
its **normal emulator APK**, not the integration-test runner, and signed back into
the original verified Phase 3 vendor with its real grocery photo. The original
Phase 3 state/evidence was copied to `final-phone/` before using the restoration
driver, so earlier evidence was not overwritten:

```bash
python3 tool/restore_phase3_phone.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase4-a8hxyt6g/final-phone
```

`final-phone-restore.log` reports **PASS**, with force-close/reopen PIDs
**22789 → 24112**. PNG/XML `final-phone/10-final-account-restored` and
`11-final-session-restored` record the final source and restored photo. The APK
SHA-256 is **`03884b510b8542d4848655c791292a9d0f969ba0eb06c1c360d2a54cbf54d5f2`**
(`apk-sha256.txt`). After integration testing, that verified normal APK was also
copied back to `build/app/outputs/flutter-apk/app-debug.apk`, so the canonical
output is not the integration runner:

```bash
cp /tmp/sandhai-phase4-a8hxyt6g/sandhai-emulator-final.apk build/app/outputs/flutter-apk/app-debug.apk
```

`sdk-version.txt` records Flutter/Dart versions directly.
The original stay-awake value was restored to **0**, read back as 0, and all three
USB reverse mappings retained:

```bash
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell settings put global stay_on_while_plugged_in 0
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell settings get global stay_on_while_plugged_in
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse --list
```

`final-export/` retains all final test fixtures. A second checkpoint after the
original account sign-in also captures updated Auth login metadata; use
**`final-restored-export/`** for a subsequent emulator restart:

```bash
cd /tmp/sandhai-phase4-a8hxyt6g
env TMPDIR=/tmp/sandhai-phase4-a8hxyt6g/live-tmp NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:export /tmp/sandhai-phase4-a8hxyt6g/final-restored-export --config /home/hisham/projects/sandhai/firebase.json --project sandhai-5km-demo
```

The running configured suite remains available. Synthetic accounts/offers/photos,
including failed-probe fixtures, remain in the exports; no cleanup was performed.
`git diff --check` passed. No remaining local build/test/device blocker is known.

## Limitations / blocked verification

- **Blocked: cloud composite-index readiness/staging query verification.** Only
  the demo emulator project and rejected placeholder production Firebase options
  are configured. The emulator cannot prove deployed cloud index readiness.
- **Production remains unverified**, with no deployment or production connection.
- Distance uses a mean-radius sphere and customer wall clock; it is not a claim
  of ellipsoidal survey accuracy, trusted server time, or geo-based access control.
- Device fixes are foreground snapshots. The app does not track a moving customer
  automatically or retain a customer's center across process restarts.
- During SDK reconnects, the last acknowledged rows may remain until a query
  error/event/expiry; manual refresh requires a new server confirmation and times
  out visibly if it cannot obtain one. No offline synchronization was added.
- Polar coverage can read many false positives; the number of bounded queries is
  capped, rather than claiming a fixed small read count at every latitude.
- No administration, push notification, scheduled expiry job or full offer
  edit/delete lifecycle was added. Legacy migration requires reviewed locations.

## Changed files

- `README.md`
- `firestore.indexes.json`
- `firestore.rules`
- `integration_test/nearby_offers_test.dart`
- `lib/core/location/location_service.dart`
- `lib/core/location/nearby_geometry.dart`
- `lib/core/utils/geohash_utils.dart`
- `lib/data/nearby_offer_repository.dart`
- `lib/data/nearby_query_source.dart`
- `lib/features/customer/nearby_feed_controller.dart`
- `lib/features/customer/screens/customer_home_screen.dart`
- `lib/features/customer/widgets/offer_card.dart`
- `lib/features/vendor/services/offer_service.dart`
- `lib/models/offer_model.dart`
- `package.json`
- `phase_4_nearby_offers.md`
- `pubspec.lock`
- `pubspec.yaml`
- `test/nearby_offers_test.dart`
- `test/nearby_widget_test.dart`
- `test/persistence_widget_test.dart`
- `test/rules.test.js`
- `test/support/nearby_fakes.dart`
- `tool/nearby_fixture_evidence.py`
- `tool/test_emulators.sh`
- `tool/verify_phase2_browser.cjs`
- `tool/verify_phase3_browser.cjs`
- `tool/verify_phase4_android.py`
- `tool/verify_phase4_browser.cjs`
