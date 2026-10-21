# Phase 4.1 — Production readiness and staging validation

Date: 2026-10-21. Branch: `main`, starting HEAD `0c82de0`.

## Executive summary and readiness decision

**READY WITH LIMITATIONS** for a small, controlled staging validation after the
operator supplies a dedicated project and authorizes its deployment. **Cloud
index readiness and staging workflows are BLOCKED; production is UNVERIFIED.**
This is not approval for a production rollout or a claim of measured cloud scale.

The audit retained the flat coordinate/geohash architecture and explicit modes.
No unresolved P0 or P1 failure remains in the locally verified scope. It fixed P2 listener, retry, offline-state and
write-validation defects, plus a P3 image-path validation issue. Local analysis,
unit/widget and isolated rules results are recorded below. Device/browser
results are recorded separately from cloud status.

No cloud project was guessed, created or used. No rules/index/app deployment,
billing change, commit, push, collection reset or destructive Git action ran.

## Inspection, plan and preservation

Read the Phase 4 report, README, Firebase configuration/rules/indexes, nearby
geometry/source/repository/controller/feed/card, location service/store model,
vendor publication/service/repository, auth/bootstrap/mode code, and existing
Dart/widget/native/Node/rules/browser/device tests. No applicable `AGENTS.md`
was found in the repository or its ancestor directories.

The initial plan, stated before edits, was: preserve source/fixtures; delegate
independent audits; reproduce findings and apply focused fixes; run full local
checks and available device/browser flows; produce an approval-gated staging
procedure and severity/readiness report.

The checkout already contained uncommitted Phase 4 work. Before changes its
status, binary diff and copies of dirty/untracked files were retained in
`/tmp/sandhai-phase4-1-vdqqm507/{git-status-before.txt,before.diff,before/}`.
Existing Phase 2/3/4 evidence remains in place. The live Auth/Firestore/Storage
fixtures were exported to `before-export/` in that directory before audit work.
No existing fixture was cleared. New verification uses uniquely named fixtures.

```bash
cd /tmp/sandhai-phase4-1-vdqqm507
env TMPDIR=/tmp/sandhai-phase4-a8hxyt6g/live-tmp NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:export /tmp/sandhai-phase4-1-vdqqm507/before-export --config /home/hisham/projects/sandhai/firebase.json --project sandhai-5km-demo
```

Export returned success. TMPDIR matches the already-running development suite
so the CLI can discover its hub. Security tests instead use fresh TMPDIRs,
separate project/ports and serial test files; they never clear this live suite.

## Findings and fixes

| Severity | Finding | Resolution/evidence |
| --- | --- | --- |
| P2 | Legacy rows opened vendor listeners before distance, expiry and schema checks; listeners survived expiry. | Validate eligibility first, distinguish absent versus malformed-null markers, resync on expiry/resume. Both new regressions failed before the fix and pass after it. |
| P2 | Refresh/reposition could start new listeners before old asynchronous cancellation acknowledged. Repeated disposal did not share a completion future. | Shared search disposal future; controller serializes teardown and checks account/location epoch before attaching replacements. Adversarial cancellation-gate tests pass. |
| P2 | A synchronous query/vendor subscription setup exception could bypass search error handling and leave prior subscriptions/timers alive. | Catch setup failures, forward a visible query error and cancel the whole search. Tests cover both setup paths. |
| P2 | Cache-only metadata after initial server success was silently ignored; offline rows could appear confirmed and later empty. | Initial cache cannot establish readiness. A bound returning to cache invalidates initial readiness; after initial success a five-second reconfirmation grace tolerates native limbo resolution, then sustained loss terminates with a connection/retry error and clears results. Pending-only snapshots remain ignored. Reconnect then Retry creates a fresh search. |
| P2 | Profile navigation retained the hidden feed's listeners/timer; navigating during a pending fix could leave a permanent locating screen. | Pause/await teardown before navigation, resume a fresh search or an actionable location prompt; guard repeated taps. Real Navigator/widget regression coverage. |
| P2 | Owner user updates allowed missing/non-string email and malformed optional updatedAt, potentially breaking deserialization. | Required keys and email/timestamp validation on create/update. Rules regressions pass. |
| P2 | Client-only 24-hour publication policy could be bypassed with expired, future-created or indefinitely extended offers. | Create time within server request time ±5 minutes, expiry future and <=createdAt+24h. Changed expiry also bounded by original creation+24h. Unchanged legacy expiry remains editable/readable for compatibility. Rules regressions include exact 24 h, 25 h,future/expired and resurrection attempts. |
| P2 | Revocation between upload and failed publication prevented missing-ID reconciliation, retaining a known orphan. | Pending/revoked vendors may get a nonexistent offer ID. Existing private documents remain protected; writes/uploads still require approval. Rules prove absence→failed publish→owner cleanup, and deny other private reads/queries. Service regression verifies same-ID retry after reapproval. |
| P3 | Regex interpolation of offer ID could bind a different offer's image path when an ID contained regex syntax. | Compare path segments literally; only filename uses regex. A literal metacharacter ID can reference its own path, never another ID. |

The existing upload journal and conservative unknown-outcome handling remain:
network-failed reconciliation retains a potentially referenced image. It must
not delete an object merely because a commit response was lost. Recovery may
require connectivity and approval restoration; automatic orphan sweeping is
outside this phase. Storage reference checks protect a concurrent commit.

## Geospatial correctness

The boundary is **inclusive**: raw double Haversine distance **<=5,000 m**.
R=6,371,000 m defines the spherical metric. Display rounding never changes
membership. This does not compensate for GPS uncertainty or ellipsoidal distance.

- Customer fixes are foreground, explicit requests. The shared service handles
  denial/permanent denial/services disabled/timeouts/platform failures; the
  StoreLocation value validates finite latitude[-90,90]/longitude[-180,180].
- Bounds cover the spherical cap's padded bounding rectangle, split the date
  line and cover every longitude at poles. Precision 6 is reduced as necessary
  to keep at most 32 disjoint prefix ranges. This is not nine precision6 cells.
- Source queries only `status==active` and the bound geohash range. Merge by
  document ID; changed bound membership cannot let an old removal delete a new
  location version. Existing overlap/removal tests remain passing.
- Decode requires valid timestamps/prices/strings/UID, active status, future
  expiry, canonical six-character hash matching finite coordinates, and valid
  confirmation evidence. A missing legacy marker requires the current store to
  match and its confirmation to predate publication; explicit-null markers are
  malformed. Legacy categories use documented `other`, never title guessing.
- Sort uses raw distance, then document ID. Location/account changes clear old
  rows immediately, invalidate callbacks, and await old listener cancellation.
- Seven new independent geometry tests exercise 22,344 projected cap points,
  grid corners, pole transitions, date line, antipodes, millimetre-side cutoff,
  malformed hashes/coordinates and false-positive cells. No geometry defect was
  discovered. Existing and new repository/widget tests cover malformed legacy
  rows, duplicates, live moves/removals, timeout/error/retry, account changes,
  disposal, category filtering and expiry.

Independent vector-distance evidence (`atan2(norm(cross),dot)`, not production
Haversine) is saved in `distance-fixtures.json` and reproducible with
`python3 tool/nearby_fixture_evidence.py`:

| Latitude at center(0,0), longitude0 | Independent distance | Expected |
| --- | --- | --- |
| 0.044876148135344655 | 4,990m | Include |
| 0.044966080295936524 | 5,000m | Include |
| 0.045056012456528396 | 5,010m | Exclude |

## Queries, indexes and efficiency

| Actual query | Required composite | Local assessment |
| --- | --- | --- |
| offers where status==active, orderBy geohash ASC, startAt(prefix), endAt(prefix+'~') | status ASC, geohash ASC, COLLECTION | Declared; bounded cursors compatible with public-active rules. |
| offers where vendorId==signed-in UID, orderBy createdAt DESC | vendorId ASC, createdAt DESC, COLLECTION | Declared; private vendor query remains scoped. |
| Legacy vendors/{uid} confirmation watch | Document lookup | No composite required; only potentially visible legacy offers now open these. |

All four indexes are retained. Earlier geohash/status/createdAt and
category/geohash definitions are preserved; current category filtering is local
to the bounded candidate set and does not issue another query. No full offers
collection listener or unbounded client query was found. Rebuilds do not create
queries; a controller owns each search. Refresh/navigation/account change
regressions assert cancellation counts and stale-callback exclusion.

No arbitrary query `limit` is added: that could omit valid nearby results.
There is no document-volume cap, so spatial bounds do not bound read count.
Dense cells and expired records still stored as active can be expensive. The
repository re-decodes candidates and sorts visible offers on updates/rechecks.

`dart run tool/benchmark_nearby.dart` uses seed41021 and no network. It records
query count, simulated candidate/duplicate/final counts; zero duplicates across
current disjoint prefixes. Results assume canonical active records and exclude
billing/SDK transport/index/expiry behavior:

| Generated offers | City20km-square,9targets: candidates/final | Polar80–90N,32targets: candidates/final | Dense shared store: final |
| ---: | ---: | ---: | ---: |
| 100 | 52/18 | 55/0 | 100 |
| 1,000 | 542/213 | 576/6 | 1,000 |
| 10,000 | 5,221/2,022 | 5,580/42 | 10,000 |
| 100,000 | 52,483/19,580 | 56,172/445 | 100,000 |

Actual local repository instrumentation at (0,0) used 16 targets and 100/1k/10k/100k
marker-bearing records: initial candidate deliveries equal the document count, no
vendor reads, zero active listeners after cancel/failure. Final full-suite
100k diagnostic timings: initial 1.117 s (includes local partition simulation),
expiry recheck 0.900 s, one-record update 0.838 s. Flutter debug-host measurements
have no acceptance threshold and are **not emulator/cloud benchmarks**.

**P2 scaling limitation:**100k dense candidates are not a reasonable mobile UX
claim. For a controlled staging cohort use low-volume fixtures and monitor
reads/latency. A targeted subsequent improvement is caching unchanged decoded
locations/distances and incrementally updating results; a separate trusted
expiry-retention policy can reduce accumulated active-expired reads. Do not
truncate queries silently or rewrite discovery during this audit.

Cloud verification remains blocked. Emulator rules compilation/query execution
cannot establish deployed composite availability. The installed CLI15.31.0
source confirms `firestore:indexes --pretty` includes READY/CREATING state;
index-spec JSON strips state. `deploy --dry-run` can enable APIs, so it was not
used as read-only validation. See the dedicated staging procedure for exact
operator-scoped commands and approval-gated deployment.

## Security assessment and residual risks

No P0/P1 privilege or account-isolation bypass was identified. Tests cover
pending/revoked publication/upload rejection, immutable role/approval,
atomic-registration escalation, UID forging, customer/other-vendor writes,
private user/offer reads and private vendor queries, finite/bounded prices and
coordinates, category/type/allowlist constraints, immutable location snapshots,
publication horizon, image path/MIME/size, immutable image bytes, published-image
protection, and authorized orphan cleanup versus another vendor's deletion.

**P2 residual location integrity:** rules validate ranges/hash format and equality
with an owner-editable store, not mathematical geohash correspondence. A
malicious approved vendor can submit a mismatched store pair and copy it into
an offer. Feed canonical validation skips it, preventing discovery through a
false hash; server acceptance is still not canonical integrity. Nor does a
canonical hash prove physical location. Smallest robust server mitigation: a
trusted publication endpoint that derives hash from submitted coordinates and
writes an immutable location snapshot; rules would prohibit direct client
publication. Stage with trusted vendors while this trust boundary is explicit.
No speculative rules-side base32 implementation or new backend was added.

**P2 policy/trust limitation:** revocation blocks new writes/uploads immediately
but existing active offers remain public until status changes or expiry. There
is no automatic cross-collection unpublish operation. Decide that policy before
untrusted public onboarding; a trusted status update can remove them live.
Customer/feed code does not read private vendor user profiles.

**P2/P3 media/privacy limitations:** vendor store profiles and offer image reads
are intentionally public. Do not put private customer/vendor-only data in those
paths. Rules enforce metadata/type/size but do not decode image contents or
verify a claimed SHA; a malicious approved vendor can also supply an arbitrary
HTTP(S) image URL with plausible metadata. Client validation is not a server
security guarantee. The smallest hardening is trusted media validation and
bucket-origin URL/path derivation. This was documented, not disguised as a
proven guarantee.

The 5 km filter does **not** prevent a direct read of an otherwise-public active
offer outside the radius. Expired status-active offers can also remain directly
readable. No physical Firestore deletion/automatic expiry function was added.

## Clock and real-time lifecycle

Device/browser `DateTime.now()` is the time source, injected in tests. The next
visible expiry schedules a timer, capped at one minute to catch clock changes;
application resume rechecks immediately. Fake-clock tests and real workflows
separate client removal from server mutation. A user with an incorrect wall
clock can see premature/late expiry; trusted server time is not established.

Cache/pending snapshots never establish initial server success. A post-success
cache transition has a five-second grace for native limbo/query reconciliation;
reconfirmation cancels that timeout. Sustained unconfirmed state is a query
error with retry. Last confirmed rows remain briefly and expiry continues during
the grace. Initial cached emptiness never establishes successful loading. There
is no automatic retry loop. Restoring connectivity
then selecting Retry starts one fresh bounded search. Initial confirmation has
a 25 s timeout. SDK network-loss detection can itself be delayed, so instant
physical-network detection is not promised.

## Verification commands and actual results

Toolchain: Flutter **3.47.5 stable**, Dart **3.13.4**, Node **22.23.1**,
Firebase CLI **15.31.0**, Temurin JDK **21.0.12.1**. Flutter commands below
resolve to `/home/hisham/development/flutter/bin/flutter`; the audit invoked that
absolute binary. Android builds/tests used `JAVA_HOME=/tmp/sandhai-phase1-jdk`.
Device: **373c972d, SM J810GF, Android10/API29**. Chrome: **152.0.7977.82**.
Dependencies were resolved from the retained lockfiles; no upgrades were made.

| Command | Actual final result | Evidence under `/tmp/sandhai-phase4-1-vdqqm507/` |
| --- | --- | --- |
| `flutter --version` | Flutter3.47.5/Dart3.13.4 | `flutter-version.log` |
| `flutter analyze` | Exit0, zero issues | `final-analyze.log` |
| `flutter test --reporter expanded` | Exit0, **88 passed** | `final-dart-tests.log` |
| `npm test` | Exit0, **16 passed** | `node-final.log` |
| `npm run test:emulators` | Exit0, **38 passed**, isolated suite shut down | `rules-final.log` |
| `flutter build web --dart-define=APP_MODE=demo` | Exit0, succeeded | `final-demo-web.log` |
| `flutter build web --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --output=build/emulator-web` | Exit0, succeeded | `final-emulator-web.log` |
| `env JAVA_HOME=/tmp/sandhai-phase1-jdk flutter build apk --debug --dart-define=APP_MODE=demo` | Exit0, succeeded | `final-demo-apk.log` |
| `env JAVA_HOME=/tmp/sandhai-phase1-jdk flutter build apk --debug --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=FIREBASE_EMULATOR_PROJECT_ID=sandhai-5km-demo` | Exit0, succeeded | `final-emulator-apk.log` |
| `dart run tool/benchmark_nearby.dart` | Exit0; deterministic local counts, no cloud traffic | `geometry-benchmark.json` |
| `python3 tool/nearby_fixture_evidence.py` | Exit0;4990/5000/5010m independent distances | `distance-fixtures.json` |
| `git diff --check` | Exit0 | Run again before completion |

The final tests comprise 56 prior tests plus 7 geometry, 8 performance/lifecycle,
16 controller/widget and 1 publication-revocation regression. The Node checks
are source-text checks; they are not substitutes for the executed Dart/rules/UI
behavior tests. Initial audit test runs exposed assertion/timing issues and the
first native run exposed the metadata regression described below. Failed logs
are retained under `before-final-reconfirmation/` and `native-nearby.log`, not
counted as passes.

Native commands actually executed against persistent development emulators:

```bash
env JAVA_HOME=/tmp/sandhai-phase1-jdk flutter test integration_test/nearby_offers_test.dart -d 373c972d --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=FIREBASE_EMULATOR_PROJECT_ID=sandhai-5km-demo
env JAVA_HOME=/tmp/sandhai-phase1-jdk flutter test integration_test/location_images_test.dart -d 373c972d --dart-define=APP_MODE=emulator --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=FIREBASE_EMULATOR_PROJECT_ID=sandhai-5km-demo
```

Both final commands exited0, **1 test each / 2 total**. Logs:
`native-nearby-final.log`, `native-images-final.log`. The former verifies native
server queries, exact4990/5000/5010m, moved/deactivated/deleted documents, expiry
without a write, warm-cache resubscription, **real Firestore SDK disableNetwork,
visible repository failure after grace, enableNetwork and fresh retry**. This
is SDK transport interruption, not a physical airplane-mode/cellular test. The
latter verifies native registration, approval, confirmed-location fixture,
actual Storage PNG metadata, persisted publication/idempotence and protected
referenced images; it does not automate Android's gallery picker UI.

### Chrome and phone workflow evidence

All browser commands use this local proxy bypass. They bind localhost and target
only `sandhai-5km-demo` on the retained development emulators:

```bash
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= SANDHAI_PHONE=1 SANDHAI_ARTIFACTS=/tmp/sandhai-phase4-1-vdqqm507/paired node tool/verify_phase4_browser.cjs
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= SANDHAI_ARTIFACTS=/tmp/sandhai-phase4-1-vdqqm507/browser-phase2 node tool/verify_phase2_browser.cjs
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= SANDHAI_ARTIFACTS=/tmp/sandhai-phase4-1-vdqqm507/browser-phase3 node tool/verify_phase3_browser.cjs
```

Results: paired Phase4 browser **PASS,5 groups**; Phase2 browser **PASS,11 checks**;
Phase3 browser **PASS,15 checks**. These include reload/session restoration,
interrupted-registration completion under the same UID, pending→approved active
updates, profile/offer persistence, visible operation failure and retry, two
vendor accounts/private dashboards, confirmed location, real JPEG picker/upload,
matching Storage MIME/bytes, categories, live publication, denied query/retry,
exact-radius fixtures and expiry with unchanged server updateTime.

The paired run uses separate Chrome vendor/customer contexts and the phone as
another customer session on the same emulator project. Chrome location is
browser-controlled; the phone uses foreground GPS. It published the real
180,248-byte grocery JPEG; independent backend document/metadata/downloaded
bytes match. Android sees it live, excludes the independently placed10km
fixture, applies category filtering, removes expiry without refresh, and removes
another expiry after HOME/background/resume with unchanged server updateTime.

Exact physical-device connectivity and paired driver commands:

```bash
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse tcp:9099 tcp:9099
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse tcp:8080 tcp:8080
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse tcp:9199 tcp:9199
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d install -r /tmp/sandhai-phase4-1-vdqqm507/sandhai-emulator.apk
```

For each stage `customer`, `observe`, `expiry`, `resume`, this exact command was
executed with the corresponding `--stage` value, sequentially after the paired
browser emitted its readiness/publication files:

```bash
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= python3 tool/verify_phase4_android.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase4-1-vdqqm507/paired --stage customer
```

All four stages exited0/PASS. Evidence is in `paired/phone-ready.json`,
`phone-observed.json`, `phone-expired.json`, `phone-background.json`,
`checks.json`, PNG/XML captures and per-stage ADB command records. Cold-start
UIAutomator initially returned null roots; it retried until fresh UI existed,
without reusing old XML. The phone was woken normally; no PIN bypass occurred.
Browser probes temporarily deny only synthetic test identities in local rules
for failure checks and restore the source rules in `finally`. These tools must
never be repointed to staging/cloud.

The paired UI workflow preceded the native cache-grace refinement. After that
fix, the final native integration exercised the actual Android query/network
behavior, all 16 lifecycle cases passed, and the **rebuilt** Chrome app repeated
all 5 nearby groups successfully:

```bash
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= SANDHAI_ARTIFACTS=/tmp/sandhai-phase4-1-vdqqm507/browser-final node tool/verify_phase4_browser.cjs
```

Evidence: `browser-final.log` and `browser-final/checks.json` (exit0/PASS).
This distinction identifies which normal UI build and which final native build
were exercised; the earlier paired captures were not relabeled as a new run.

After integration tests replaced the APK, the final normal emulator APK was
reinstalled and launched. A private copy of the original Phase3 synthetic vendor
state was placed in `phone-restored/state.json`; the source state/evidence was
preserved. Actual restoration command:

```bash
env NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= python3 tool/restore_phase3_phone.py --adb /home/hisham/Android/Sdk/platform-tools/adb --serial 373c972d --artifacts /tmp/sandhai-phase4-1-vdqqm507/phone-restored
```

Exit0/PASS: original vendor signed in, existing real-photo offer loaded, then
force-close/reopen restored it (PID10532→11495). PNG/XML and command evidence:
`phone-restored/`, `phone-restored.log`. The final normal emulator APK SHA256 is
`eee87e2b6c06399f79bb603053ecff878e9af0d40f91148930facbf216383220`;
both build hashes are in `apk-sha256.txt`. All three Firebase USB reverse ports
remain in `adb-reverse-final.txt`. The phone's original stay-awake setting0 was
restored and read back as0.

```bash
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell settings put global stay_on_while_plugged_in 0
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d shell settings get global stay_on_while_plugged_in
/home/hisham/Android/Sdk/platform-tools/adb -s 373c972d reverse --list
cd /tmp/sandhai-phase4-1-vdqqm507
env TMPDIR=/tmp/sandhai-phase4-a8hxyt6g/live-tmp NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy= firebase emulators:export /tmp/sandhai-phase4-1-vdqqm507/after-export --config /home/hisham/projects/sandhai/firebase.json --project sandhai-5km-demo
```

Final Auth/Firestore/Storage export completed successfully without stopping
the development suite. Evidence: `export-final.log` and `after-export/`.


An independent retained-photo read compared the original vendor's180,248-byte
photo with the before-audit Storage export: byte-for-byte match,
SHA256`cebf8f3e186790c2705a31759b214bb5bfa29ffd1d72b1f7722addf4ebc55263`.
Evidence: `retained-photo.json`. Synthetic fixtures remain retained for review;
no existing live collection/account was reset. A final byte-comparison guard
confirmed 19 existing dirty paths outside the intended edits were unchanged
(`preservation-check.json`); intended edits retain their before copies. Emulator exports and artifacts
contain test account data and token-bearing URLs: retain privately, do not commit.

### Verification boundaries

| Environment | Status |
| --- | --- |
| Pure Dart/widgets + local simulated volume | Verified as above; no cloud throughput claim. |
| Isolated Firebase security emulators |38passed; separate TMPDIR/project/ports, shut down. |
| Persistent emulator Chrome + physical Android | Verified as above; no physical network-toggle test. |
| Dedicated staging Firestore indexes/rules/workflows | **BLOCKED**, no project/options/authorization supplied. |
| Production configuration/deployment/runtime | **UNVERIFIED**. |

Staging shell examples (`bash -n`,5 blocks) and ordinary-client probe
(`node --check`) passed syntax checks only. Those checks did not execute any
cloud deployment or prove cloud behavior.


The first native integration attempt failed during a normal moved-document
update because the initial audit fix treated every post-ready cache transition
as an immediate outage. That on-device evidence prompted the five-second grace
above. This failed run is retained in `native-nearby.log`; final rerun results
are recorded in the verification table. It was not counted as a passing run.

## Files changed during this audit

Relative to the preserved uncommitted Phase4 snapshot (not merely HEAD):

- `lib/data/nearby_offer_repository.dart`, `nearby_query_source.dart`: validation,
  vendor-listener eligibility, setup failures, metadata state, shared disposal.
- `lib/features/customer/nearby_feed_controller.dart` and
  `screens/customer_home_screen.dart`: serialized teardown, pause/resume,
  actionable navigation/location state, repeated-tap guard.
- `firestore.rules`: user schema, bounded timestamps, literal image-path scope,
  revoked-vendor absent-ID reconciliation. `storage.rules` inspected unchanged.
- `test/phase_4_1_geospatial_test.dart`, `phase_4_1_performance_test.dart`,
  `phase_4_1_lifecycle_test.dart`, `phase_4_1_lifecycle_widget_test.dart`,
  `phase_4_1_rules.test.js`: independent new regressions.
- `test/nearby_offers_test.dart`, `nearby_widget_test.dart`,
  `persistence_test.dart`, `integration_test/nearby_offers_test.dart`: updated
  contracts, retry synchronization, revocation cleanup, real SDK network test.
- `tool/benchmark_nearby.dart`, `tool/test_emulators.sh`: local diagnostic and
  serial isolated security suites.
- `README.md`, this report and `docs/phase_4_1_staging_procedure.md`.

Previously dirty indexes, schema, location/image/auth/Android connectivity code
and Phase4 reports/tools are retained; their presence in git status does not
mean this audit rewrote them. `firestore.indexes.json` required no further change.

## Subagent Execution Summary

| Subagent | Assigned scope | Work completed | Files changed | Findings |
| --- | --- | --- | --- | --- |
| Geospatial (`geospatial_audit`) | Correctness | Independent projected boundary/pole/dateline/hash tests; 7 passed | `test/phase_4_1_geospatial_test.dart` | No geometry defect; 22,344 point coverage evidence. |
| Security (`security_audit`) | Firebase rules | Rule audit, 12 regressions; first 10 focused tests passed, final 12 included in main 38-test run | `test/phase_4_1_rules.test.js` | P2 schema/expiry/cleanup, P3 path interpolation, residual server-trust limits. |
| Performance (`performance_audit`) | Queries/indexes | Deterministic geometry/read-volume simulation; 8 repository instrumentation tests passed in the final suite | `tool/benchmark_nearby.dart`, `test/phase_4_1_performance_test.dart` | P2 legacy fanout/expiry reproduced before fix; dense-volume limitation and matching index. |
| Testing (`regression_audit`) | Regression coverage | 16 deterministic lifecycle/widgets passed in the final suite; diagnosed root-zone fake cancellation in existing retry test | `test/phase_4_1_lifecycle_test.dart`, `test/phase_4_1_lifecycle_widget_test.dart`, `test/nearby_widget_test.dart` | P2 setup/cancellation/navigation/cache issues verified fixed. |
| Staging (`staging_audit`) | Deployment readiness | Read-only config/installedCLI inspection; safe operator procedure and syntax checks | `docs/phase_4_1_staging_procedure.md` | Missing dedicated project/config; index-state and dry-run caveats. |

All five specialists actually ran. The environment supports four total active
agents: geospatial/security/performance ran concurrently with main; testing
started when geospatial finished; staging started when security finished, while
performance/testing/main work continued. Security also reviewed the targeted
cleanup follow-up. Source ownership avoided overlapping production edits.

Main retained responsibility for preservation/exports, production fixes,
conflict/recommendation review, integration of regressions, complete checks,
Android/Chrome verification, staging deployment gate, and this readiness decision.

## Staging procedure and blockers

Follow [the full staging procedure](docs/phase_4_1_staging_procedure.md). It
provides exact local-copy/env commands, explicit project/app/database/index
readiness reads, approval-gated rules/Storage/index deployment commands,
ordinary-client server query probes, cloud-mode launch/build, real publication,
independent4990/5000/5010m discovery, live changes/expiry, negative authorization
checks, and precise manifest-based cleanup. None of those cloud operations ran.

Missing prerequisites: operator-designated dedicated staging project/default
Native Firestore database and bucket, reviewed web/Android Firebase options,
Email/Password Auth and accepted web origin, scoped credentials/IAM,
Storage↔Firestore authorization integration, and explicit deployment/fixture
administration approval. Do not create these resources or enable billing by
inference. Production options remain placeholders and production is UNVERIFIED.

The readiness decision permits proceeding to an explicitly approved small staging
validation once those inputs exist. It does not mark the outstanding cloud
checks complete or remove the recorded volume/trust/time limitations.
