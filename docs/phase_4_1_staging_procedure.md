# Phase 4.1 dedicated Firebase staging procedure

## Audit result and execution boundary

**Cloud composite-index readiness and staging queries are blocked.** On
2026-10-21 the repository identified only the emulator/demo project
`sandhai-5km-demo`; no operator-designated staging project or working staging
application configuration was supplied. This is a repository/configuration
finding, not a claim that the operator has no staging project elsewhere.

| Inspected evidence | Finding |
| --- | --- |
| `.firebaserc` | Only `projects.default = sandhai-5km-demo`; no staging alias. |
| `firebase.json` | Local rules/index paths and Auth/Firestore/Storage emulator ports; no dedicated staging association. |
| `lib/firebase_options.dart` | Placeholder `DEMO_...` API keys and demo project ID on every configured platform. |
| `lib/app/config.dart` | Modes are `demo`, `emulator`, `production`; no separate staging mode or project-ID override for cloud mode. |
| `lib/app/bootstrap.dart` | Cloud mode reads `DefaultFirebaseOptions`; rejects checked-in placeholders. `FIREBASE_EMULATOR_PROJECT_ID` affects emulator mode only. |
| `README.md`, `phase_4_nearby_offers.md` | Already disclose blocked cloud index verification. |
| `firestore.indexes.json` | Four collection-scoped `offers` indexes, including the nearby `status ASC, geohash ASC` index. |

The audit read repository files and installed CLI implementation files. It did
not enumerate cloud projects/accounts, read CLI login/token stores, fetch SDK
configuration, connect to a cloud project, deploy, enable services, change
billing, create resources, approve accounts, write fixtures, or delete anything.
The following procedure is **planned and not executed**. Local emulator tests
and a successful build cannot substitute for its cloud evidence.

`firebase --version` printed **15.31.0**, then failed its local update-store
permission check. No permission changes or escalation were attempted because
the installed source was sufficient for this audit.

## Operator inputs and existing resources

Before running cloud commands, the operator must identify a dedicated disposable
staging project and explicitly authorize testing there. Do not infer a project
from a logged-in account, choose one from a project listing, use the repository's
default, or substitute a production project.

Required operator inputs are the exact Firebase project ID, default Storage
bucket name, registered web/Android app IDs, an already generated and reviewed
staging `firebase_options.dart`, and a matching web SDK configuration JSON file.
Obtain configuration through the operator's existing process; do not print it in
logs or run `flutterfire configure` as an audit step, since app registration may
create resources. Keep any test account passwords in a separate permission-0600
file outside the repository. Never put service-account keys, refresh tokens,
passwords, or bearer tokens in this document or evidence artifacts.

The project must already have:

1. Firebase Authentication with the **Email/Password** provider enabled; web test
   origin accepted by the project's Auth configuration. See
   [Firebase password authentication](https://firebase.google.com/docs/auth/web/password-auth).
2. The **`(default)` Firestore database in Native mode**, with realtime/mobile/web
   access supported. The app uses `FirebaseFirestore.instance`; Storage rules
   also address `/databases/(default)`. A named-only or Datastore-mode database
   does not match this application. See
   [Firestore databases](https://firebase.google.com/docs/firestore/manage-databases).
3. A Firebase Storage bucket matching the supplied options exactly. Do not
   derive its suffix from the project ID: an existing bucket may use
   `appspot.com` or `firebasestorage.app`. The operator must already have the
   required Cloud Storage plan/billing arrangement; this procedure never
   upgrades it. Current requirements are documented in
   [Firebase Storage setup](https://firebase.google.com/docs/storage/web/start).
4. Reviewed versions of `firestore.rules`, `storage.rules`, and all four indexes
   from `firestore.indexes.json` already released to the intended resources.
   Storage's `firestore.get/exists` approval checks require the cross-product
   permission connection to be configured by the operator. See
   [Storage rules with Firestore](https://firebase.google.com/docs/storage/security/rules-conditions#enhance_with_firestore).
5. An authorized read-only CLI identity with project/app metadata, database get,
   and index-list access. Approval/fixture preparation/cleanup requires a
   separately authorized administrator. An Admin SDK success does not validate
   client Security Rules.

If any prerequisite is absent, record it as blocked and return it to the
operator. Provisioning, deploying rules/indexes, granting IAM, and billing
changes are separate mutations; none is an implicit part of this audit.

## Isolate the application configuration

Run these commands manually from the repository root after filling the
operator-provided values. These are local preparation commands, not cloud
validation. Use the supported Flutter/Node/JDK versions documented in README.

```bash
set -euo pipefail
umask 077
export SANDHAI_STAGING_PROJECT='OPERATOR_PROVIDED_PROJECT_ID'
export SANDHAI_STAGING_BUCKET='OPERATOR_PROVIDED_BUCKET_NAME'
export SANDHAI_STAGING_OPTIONS_DART='/absolute/private/path/firebase_options.dart'
export SANDHAI_STAGING_WEB_CONFIG='/absolute/private/path/staging-web-config.json'
export SANDHAI_STAGING_ACCOUNTS='/absolute/private/path/staging-test-accounts.json'
test "$SANDHAI_STAGING_PROJECT" != 'OPERATOR_PROVIDED_PROJECT_ID'
test "$SANDHAI_STAGING_PROJECT" != 'sandhai-5km-demo'
test "$SANDHAI_STAGING_BUCKET" != 'OPERATOR_PROVIDED_BUCKET_NAME'
test -f "$SANDHAI_STAGING_OPTIONS_DART"
test -f "$SANDHAI_STAGING_WEB_CONFIG"
export SANDHAI_STAGING_WORK="$(mktemp -d /tmp/sandhai-staging-XXXXXX)"
mkdir -p "$SANDHAI_STAGING_WORK/repo" "$SANDHAI_STAGING_WORK/evidence"
tar --exclude=.git --exclude=node_modules --exclude=build --exclude=.dart_tool \
  --exclude=.firebase --exclude=.agents --exclude=.codex --exclude=.aws \
  --exclude='*-debug.log' -cf - . |
  tar -xf - -C "$SANDHAI_STAGING_WORK/repo"
cp -- "$SANDHAI_STAGING_OPTIONS_DART" "$SANDHAI_STAGING_WORK/repo/lib/firebase_options.dart"
cd "$SANDHAI_STAGING_WORK/repo"
```

Review this copy's web and Android project IDs/app IDs/bucket against the
operator's resource record. Keep the original checkout's options, live emulator
process, exports, fixtures and Android installation unchanged. Copy the current
working tree as above: `git archive HEAD` would omit uncommitted Phase 4 changes.

Cloud staging runs use **`APP_MODE=production` with staging options**. Merely
adding `--project` to Firebase CLI commands cannot select the Flutter backend.
An emulator build remains an emulator build. Do not alter the existing
`automaticHostMapping: false` settings or the retained Android USB reverse
mappings; they are unrelated to cloud configuration.

## Read-only metadata and index readiness

All commands in this section are **not executed during the audit**. They target
the explicit project and local config file, never `.firebaserc` implicitly:

```bash
firebase apps:list WEB --project "$SANDHAI_STAGING_PROJECT" \
  --config "$SANDHAI_STAGING_WORK/repo/firebase.json" --non-interactive
firebase apps:list ANDROID --project "$SANDHAI_STAGING_PROJECT" \
  --config "$SANDHAI_STAGING_WORK/repo/firebase.json" --non-interactive
firebase firestore:databases:get '(default)' --project "$SANDHAI_STAGING_PROJECT" \
  --config "$SANDHAI_STAGING_WORK/repo/firebase.json" --non-interactive
firebase firestore:indexes --database '(default)' --pretty \
  --project "$SANDHAI_STAGING_PROJECT" \
  --config "$SANDHAI_STAGING_WORK/repo/firebase.json" --non-interactive
```

Capture redacted metadata, exit codes, UTC time and the command version. Confirm
the registered app identities and Native database, then verify **READY**, not
merely present/CREATING, for these collection-scoped `offers` indexes:

| Fields in committed order | Purpose |
| --- | --- |
| `geohash ASC, status ASC, createdAt DESC` | Preserved earlier index. |
| `vendorId ASC, createdAt DESC` | Private vendor dashboard. |
| `category ASC, geohash ASC` | Preserved category index. |
| `status ASC, geohash ASC` | Current nearby bound query. |

Match the collection scope in the console or the index specification; do not
mistake a collection-group index for the committed collection index. The service
may append `__name__`; compare the declared fields accordingly. Verify all
required indexes without deleting unrelated deployed indexes.

Installed CLI source was inspected under
`/usr/local/lib/node_modules/firebase-tools/lib/`:

- `commands/firestore-indexes-list.js` issues index/field-override reads.
  `firestore/pretty-print.js` includes index state with `--pretty`.
  `firestore/api.js:makeIndexSpec` strips `state`; normal or `--json` index-spec
  output alone cannot prove readiness.
- `commands/firestore-databases-get.js` requests `datastore.databases.get` and
  calls the database GET API. `commands/apps-list.js` lists apps in the selected
  project; no account-wide `projects:list` is needed.
- **Do not use `firebase deploy --dry-run` as a read-only check.** Its own
  `commands/deploy.js` description says it may enable APIs; Firestore
  `deploy/firestore/prepare.js` calls `ensureApiEnabled.ensure`.

Use the selected project's console to confirm the released Firestore/Storage
rules against the reviewed source and record release identity/time. CLI
`database:rules:*` commands concern Realtime Database, not Firestore. A local
rules test does not demonstrate what is released. If required indexes are absent
or building, let the operator's separately authorized deployment process resolve
them, then repeat reads. See
[Firestore index management](https://firebase.google.com/docs/firestore/query-data/indexing).

## Planned client query probe

### Deployment gate (commands not executed)

The following commands mutate the explicitly selected staging project. Run them
only after the operator authorizes that rules/index deployment and confirms the
project is dedicated staging. Review the complete index diff first: CLI index
deployment can propose deletion of indexes absent from the local specification.
Do not accept deletion of unrelated indexes. Do not add `--force`.

```bash
firebase deploy --only firestore:rules --project "$SANDHAI_STAGING_PROJECT" \
  --config "$SANDHAI_STAGING_WORK/repo/firebase.json"
firebase deploy --only storage --project "$SANDHAI_STAGING_PROJECT" \
  --config "$SANDHAI_STAGING_WORK/repo/firebase.json"
firebase deploy --only firestore:indexes --project "$SANDHAI_STAGING_PROJECT" \
  --config "$SANDHAI_STAGING_WORK/repo/firebase.json"
firebase firestore:indexes --database '(default)' --pretty \
  --project "$SANDHAI_STAGING_PROJECT" \
  --config "$SANDHAI_STAGING_WORK/repo/firebase.json" --non-interactive
```

This repository's Storage config addresses the project's default Firebase
bucket. If the operator supplies a different bucket, stop and review explicit
Storage target configuration in the isolated copy before deploying; do not
silently apply rules to the wrong bucket. Deployment success is not index
readiness. Repeat the last read until all required indexes are **READY**, record
the result, and then run ordinary-client queries. Provisioning APIs or billing
is not authorized by this procedure.

### Ordinary-client probe

After the registration fixtures below exist, the operator can run this probe in
the isolated copy with `npm ci` completed. It reads Firestore using the ordinary
Firebase client SDK and the actual test accounts, without an Admin SDK or
Security Rules bypass. Signing in updates normal Auth sign-in metadata; this
section is not a claim of zero cloud mutation.

The private accounts file has the shape
`{"customer":{"email":"...","password":"..."},"vendor":{"email":"...","password":"..."}}`.
The web config file contains the operator's Firebase web config object. Set a
geohash prefix taken from a bound for the intended fixture center. `s000` is a
representative equatorial prefix for query-shape readiness; the full application
must still execute every bound in its 5,000 m cover.

```bash
export SANDHAI_STAGING_PREFIX='s000'
node --input-type=module <<'JS'
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase/app';
import {initializeAuth, inMemoryPersistence, signInWithEmailAndPassword,
  signOut} from 'firebase/auth';
import {getFirestore, collection, doc, query, where, orderBy, startAt, endAt,
  getDocsFromServer, getDocFromServer, terminate} from 'firebase/firestore';

let app, auth, db;
const watchdog = setTimeout(() => {
  console.error('FAIL: probe timeout'); process.exit(1);
}, 45000);
try {
  const cfg = JSON.parse(fs.readFileSync(process.env.SANDHAI_STAGING_WEB_CONFIG, 'utf8'));
  const accounts = JSON.parse(fs.readFileSync(process.env.SANDHAI_STAGING_ACCOUNTS, 'utf8'));
  assert.equal(fs.statSync(process.env.SANDHAI_STAGING_ACCOUNTS).mode & 0o077, 0);
  assert.equal(cfg.projectId, process.env.SANDHAI_STAGING_PROJECT);
  assert.notEqual(cfg.projectId, 'sandhai-5km-demo');
  assert.equal(cfg.storageBucket, process.env.SANDHAI_STAGING_BUCKET);
  for (const name of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST',
    'FIREBASE_STORAGE_EMULATOR_HOST']) assert.ok(!process.env[name]);
  const prefix = process.env.SANDHAI_STAGING_PREFIX;
  assert.match(prefix, /^[0123456789bcdefghjkmnpqrstuvwxyz]{1,6}$/);
  app = initializeApp(cfg);
  auth = initializeAuth(app, {persistence: inMemoryPersistence});
  db = getFirestore(app);
  await signInWithEmailAndPassword(auth, accounts.customer.email, accounts.customer.password);
  const nearby = await getDocsFromServer(query(collection(db, 'offers'),
    where('status', '==', 'active'), orderBy('geohash'),
    startAt(prefix), endAt(prefix + '~')));
  assert.equal(nearby.metadata.fromCache, false);
  console.log('PASS: server nearby query; rows=' + nearby.size);
  await signOut(auth);
  await signInWithEmailAndPassword(auth, accounts.vendor.email, accounts.vendor.password);
  const ownUser = await getDocFromServer(doc(db, 'users', auth.currentUser.uid));
  assert.equal(ownUser.data()?.role, 'vendor');
  assert.equal(ownUser.data()?.approvalStatus, 'approved');
  const ownOffers = await getDocsFromServer(query(collection(db, 'offers'),
    where('vendorId', '==', auth.currentUser.uid), orderBy('createdAt', 'desc')));
  assert.equal(ownOffers.metadata.fromCache, false);
  console.log('PASS: server private-vendor query; rows=' + ownOffers.size);
} catch (error) {
  console.error('FAIL: ' + (error.code || error.name || 'query failure'));
  process.exitCode = 1;
} finally {
  if (auth) await signOut(auth).catch(() => {});
  if (db) await terminate(db);
  if (app) await deleteApp(app);
  clearTimeout(watchdog);
}
JS
```

A server-confirmed empty result establishes only successful execution of this
query shape. It does not establish correct radius coverage, publication,
category, expiry, or nonempty fixture discovery. Record `failed-precondition`
(index), `permission-denied` (rules/IAM), Auth errors and network failures
separately; none is an empty-feed pass. Also verify the full app has no query
error for every bound and returns the seeded expected rows.

## Planned authorized fixture flow and expected results

Use a new run identifier in titles/account names and maintain a manifest of exact
test UIDs, document IDs and image object paths. Limit fixture writes to the
dedicated staging project. The manifest/evidence must omit passwords, Auth
tokens and token-bearing image download URLs. No fixture below has been created
by this audit.

1. **Registration and restored sessions.** In separate browser profiles, create
   one customer and two vendors through the real forms. Verify vendor
   `users/{uid}` and `vendors/{uid}` exist atomically; approval starts `pending`.
   Reload/sign in again and retain the same UID/role/profile. Pending vendors
   cannot publish or upload. Test recovery of a dedicated Auth-only registration
   if the operator has separately prepared that fixture; never break global
   rules to manufacture a failure.
2. **Authorized approval and location.** An authorized administrator updates only
   each manifest vendor's `users/{uid}.approvalStatus` to `approved`. Record
   actor/time and verify the client cannot self-approve. Confirm the store
   location through the real profile UI, explicitly accepting or correcting the
   foreground suggestion. Check finite coordinates, canonical six-character
   geohash and server confirmation timestamp. Rejected/suspended vendors remain
   unable to publish; legacy unconfirmed coordinates remain insufficient.
3. **Real persisted photo publication.** Upload the existing public grocery JPEG
   through the real picker and publish as the approved vendor. Independently
   inspect the server document and Storage metadata: correct UID/path, category,
   prices, confirmed coordinate snapshot, timestamps, MIME, byte count and exact
   photo bytes. Customer receives it live and after reload; second vendor's
   private dashboard cannot expose the first vendor's private drafts.
4. **Radius boundary.** With browser-controlled center `(0, 0)`, use the
   independent coordinates below, same longitude `0`, status `active`, future
   expiry and valid category/price/timestamp/location evidence. Prefer separate
   approved, confirmed stores at the three points and normal client publication
   so the fixture also satisfies publication rules. A separately authorized
   administrator may seed clearly labeled geometry-only records, but such
   writes do not prove client create-rule success. Include marker-bearing new
   records; do not blindly backfill real legacy data.

   | Latitude | Independent spherical distance | Discovery |
   | --- | --- | --- |
   | `0.044876148135344655` | 4,990 m | Included. |
   | `0.044966080295936524` | 5,000 m | Included. |
   | `0.045056012456528396` | 5,010 m | Excluded. |

   Run `python3 tool/nearby_fixture_evidence.py` locally to retain the independent
   vector-distance calculation (R = 6,371,000 m). Test full app bound coverage,
   category/search, deterministic distance/ID ordering and location replacement.
   Browser-controlled coordinates are not hardware GPS evidence. Distance is a
   discovery filter: a direct read of a public active outside-radius offer is
   expected to succeed under the current rules.
5. **Live expiry without writes.** Publish a dedicated short-lived valid offer
   through the client SDK, or have the authorized administrator shorten only a
   manifest offer's `expiryTime` once before observation. Capture its raw server
   `updateTime`, status and expiry after setup. Observe foreground removal with
   no refresh, then repeat with a separate offer expiring while backgrounded and
   resume. Independently read afterward: `updateTime` must be unchanged, status
   may remain `active`, and the feed excludes it. Do not write during either
   observation window. Record UTC/device times: expiry uses customer wall clock,
   not a trusted server clock.
6. **Security rejections through ordinary client identities.** Attempt
   self-approval/role escalation, another UID's private user read, a broad
   private-offers query, pending/suspended publication/upload, another vendor's
   write/upload/delete, mismatched store coordinates, invalid prices/category,
   invalid or excessive publication lifetime, and incorrect image MIME/size.
   Require the expected Firestore/Storage permission error and independently
   confirm no forbidden document/object was created or changed. An expired
   `active` public offer can remain directly readable; discovery must hide it.
   Do not weaken released rules for an error-state test. Exercise transient
   connection failure locally, then restore connectivity and retry.

Build/run the isolated cloud-configured web app after reviewing configuration:

```bash
flutter pub get
flutter run -d chrome --dart-define=APP_MODE=production
flutter build web --dart-define=APP_MODE=production
JAVA_HOME=/absolute/path/to/jdk-21 flutter build apk --debug --dart-define=APP_MODE=production
```

Use an expendable Android test device/profile for cloud staging. Do not install
over the retained developer phone's restored emulator session. Any Android build
must use the same reviewed staging options and `APP_MODE=production`; the USB
emulator host workaround remains untouched in the original source.

Existing `tool/verify_phase*_browser.cjs` and native integration probes target
local emulators and use emulator-only rule/owner endpoints. **Do not repoint
them to cloud or treat their synthetic `Bearer owner` credentials as cloud
administration.** The UI/SDK steps above must use normal staging identities;
administrator actions use the operator's approved tooling.

## Planned cleanup and completion record

After evidence review, the authorized administrator removes only the exact
manifest's synthetic offers, their Storage objects, vendor/user documents and
test Auth accounts. Delete offer references before their referenced objects when
using owner cleanup, because published referenced photos are protected. User
documents cannot be deleted by client rules, so final profile removal requires
the authorized administrator. Never clear a collection, reset an emulator,
delete a project/bucket/index, or delete by a broad title/prefix search. Preserve
existing local emulator fixtures and all Phase 2/3/4 exports.

Retain a redacted completion record with project/database/bucket identity,
configuration/build hashes, rules release IDs, READY index evidence, query exit
codes and counts, fixture IDs, independent distances, publication/expiry
before-and-after evidence, rejection codes, cleanup result and any retained
fixture IDs. Do not call staging verified until metadata, deployed rules,
server-confirmed queries, nonempty expected discovery, expiry and negative
checks all pass. Until then report **blocked** or the precise failed check;
the present audit remains **blocked: no designated staging project/config**.
