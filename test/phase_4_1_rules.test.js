const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

// Run serially with rules.test.js in the disposable test emulators. The retained
// developer project has live fixtures and must never be cleared by this suite.
const projectId = process.env.GCLOUD_PROJECT || 'sandhai-phase3-tests';
let env;

test.before(async () => {
  assert.match(projectId, /^sandhai-(?:phase3|phase4-1)-tests$/);
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(?:127\.0\.0\.1|localhost):8180$/);
  assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST || '', /^(?:127\.0\.0\.1|localhost):9299$/);
  assert.match(process.env.TMPDIR || '', /^\/tmp\/sandhai-/);
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1', port: 8180,
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
    storage: {
      host: '127.0.0.1', port: 9299,
      rules: fs.readFileSync(path.join(__dirname, '..', 'storage.rules'), 'utf8'),
    },
  });
});

test.beforeEach(async () => { if (env) await env.clearFirestore(); });
test.after(async () => { if (env) await env.cleanup(); });

const confirmedAt = new Date('2026-01-01T00:00:00Z');
function user(uid, role = 'vendor', approvalStatus = 'approved') {
  return {
    displayName: 'Security regression store', email: `${uid}@example.com`,
    role, approvalStatus, createdAt: confirmedAt,
  };
}
function store() {
  return {
    name: 'Security regression store', phone: '9876543210', category: 'groceries',
    latitude: 13.0827, longitude: 80.2707, geohash: 'tf346t',
    locationConfirmedAt: confirmedAt, createdAt: confirmedAt,
  };
}
function offer(uid, extra = {}) {
  const now = new Date();
  return {
    vendorId: uid, title: 'Clearance offer', description: 'Security regression',
    category: 'groceries', oldPrice: 100, newPrice: 50, imageUrl: '',
    latitude: 13.0827, longitude: 80.2707, geohash: 'tf346t',
    locationConfirmedAt: confirmedAt, createdAt: now,
    expiryTime: new Date(+now + 60 * 60 * 1000), status: 'active', ...extra,
  };
}
async function seed(uid, role = 'vendor', approvalStatus = 'approved') {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await db.doc(`users/${uid}`).set(user(uid, role, approvalStatus));
    if (role === 'vendor') await db.doc(`vendors/${uid}`).set(store());
  });
}
async function approval(uid, status) {
  await env.withSecurityRulesDisabled(context =>
    context.firestore().doc(`users/${uid}`).update({approvalStatus: status}));
}
function db(uid) { return env.authenticatedContext(uid).firestore(); }
function storage(uid) { return env.authenticatedContext(uid).storage(); }
function photo(uid, id, extra = {}) {
  return offer(uid, {
    imageUrl: 'https://example.com/photo.png',
    imagePath: `offers/${uid}/${id}/${'a'.repeat(64)}.png`,
    imageContentType: 'image/png', imageSize: 3, ...extra,
  });
}

test('Phase 4.1: profile ownership and approval cannot be forged in atomic registration', async () => {
  const owner = db('registration-owner');
  const create = owner.batch();
  create.set(owner.doc('users/registration-owner'), user('registration-owner', 'vendor', 'pending'));
  create.set(owner.doc('vendors/registration-owner'), store());
  await assertSucceeds(create.commit());
  await assertFails(owner.doc('users/registration-owner').update({approvalStatus: 'approved'}));
  await assertFails(owner.doc('users/registration-owner').update({role: 'customer'}));
  await assertFails(owner.doc('users/registration-owner').delete());
  await assertFails(owner.doc('users/different-owner').set(user('different-owner', 'vendor', 'pending')));

  const forged = db('forged-registration');
  const batch = forged.batch();
  batch.set(forged.doc('users/forged-registration'), user('forged-registration'));
  batch.set(forged.doc('vendors/forged-registration'), store());
  await assertFails(batch.commit());
});

test('Phase 4.1: private profiles and every private offer status stay scoped to the UID', async () => {
  await seed('private-owner');
  await seed('private-other');
  const owner = db('private-owner');
  const other = db('private-other');
  const publicDb = env.unauthenticatedContext().firestore();
  for (const status of ['draft', 'expired', 'deleted']) {
    await env.withSecurityRulesDisabled(context =>
      context.firestore().doc(`offers/private-${status}`).set(offer('private-owner', {status})));
    await assertSucceeds(owner.doc(`offers/private-${status}`).get());
    await assertFails(other.doc(`offers/private-${status}`).get());
    await assertFails(publicDb.doc(`offers/private-${status}`).get());
  }
  await assertSucceeds(owner.collection('offers').where('vendorId', '==', 'private-owner').get());
  await assertFails(other.collection('offers').where('vendorId', '==', 'private-owner').get());
  await assertFails(other.doc('users/private-owner').get());
  await assertFails(publicDb.doc('users/private-owner').get());
  await assertSucceeds(owner.doc('users/private-owner').get());
});

test('Phase 4.1: same-session revocation blocks offer creation and modification but allows owner deletion', async () => {
  await seed('revoked-owner');
  const owner = db('revoked-owner');
  await assertSucceeds(owner.doc('offers/before-revocation').set(offer('revoked-owner')));
  await approval('revoked-owner', 'suspended');
  await assertFails(owner.doc('offers/after-revocation').set(offer('revoked-owner')));
  await assertFails(owner.doc('offers/before-revocation').update({title: 'Unauthorized change'}));
  await assertSucceeds(owner.doc('offers/before-revocation').get());
  await assertSucceeds(owner.doc('offers/before-revocation').delete());
});

test('Phase 4.1: revoked vendors can reconcile an absent offer and clean its orphan without reading another private offer', async () => {
  await seed('reconcile-owner');
  await seed('reconcile-other');
  await seed('reconcile-customer', 'customer');
  const owner = db('reconcile-owner');
  await assertSucceeds(db('reconcile-other').doc('offers/reconcile-private').set(
    offer('reconcile-other', {status: 'draft'})));

  const imagePath = `offers/reconcile-owner/reconcile-absent/${'b'.repeat(64)}.png`;
  const ref = storage('reconcile-owner').ref(imagePath);
  await assertSucceeds(ref.put(Buffer.from('png'), {contentType: 'image/png'}));
  await approval('reconcile-owner', 'suspended');
  const missing = await assertSucceeds(owner.doc('offers/reconcile-absent').get());
  assert.equal(missing.exists, false);
  await assertFails(owner.doc('offers/reconcile-absent').set(photo('reconcile-owner', 'reconcile-absent', {
    imagePath,
  })));
  await assertSucceeds(ref.delete());

  await assertFails(owner.doc('offers/reconcile-private').get());
  await assertFails(owner.collection('offers').where('vendorId', '==', 'reconcile-other').get());
  await assertFails(db('reconcile-customer').doc('offers/reconcile-absent').get());
  await assertFails(env.unauthenticatedContext().firestore().doc('offers/reconcile-absent').get());
});

test('Phase 4.1: offer numeric, type, ownership and location snapshot boundaries reject malformed writes', async () => {
  await seed('boundary-owner');
  const owner = db('boundary-owner');
  const invalid = [
    {oldPrice: 0}, {oldPrice: -1}, {oldPrice: Infinity}, {oldPrice: NaN},
    {oldPrice: 1000000000000}, {oldPrice: '100'},
    {newPrice: 0}, {newPrice: -1}, {newPrice: 101}, {newPrice: NaN}, {newPrice: Infinity},
    {latitude: NaN}, {latitude: 91}, {longitude: Infinity}, {longitude: -181},
    {latitude: 0}, {longitude: 0}, {geohash: 'tf340w'}, {geohash: 'TF346T'},
    {geohash: 'tf346'}, {geohash: 'tf346tt'}, {locationConfirmedAt: new Date(0)},
    {vendorId: 'someone-else'}, {category: 4}, {category: 'unknown'},
    {expiryTime: 'tomorrow'}, {createdAt: 'today'}, {isAdmin: true},
  ];
  for (const [index, fields] of invalid.entries()) {
    await assertFails(owner.doc(`offers/boundary-${index}`).set(offer('boundary-owner', fields)));
  }
  await assertSucceeds(owner.doc('offers/valid-boundary').set(offer('boundary-owner', {newPrice: 100})));
  for (const fields of [{vendorId: 'someone-else'}, {latitude: 0}, {longitude: 0}, {geohash: 's00000'}]) {
    await assertFails(owner.doc('offers/valid-boundary').update(fields));
  }
});

test('Phase 4.1: profile updates retain required keys and validate email and update timestamps', async () => {
  await seed('profile-schema-owner');
  const ref = db('profile-schema-owner').doc('users/profile-schema-owner');
  const original = (await ref.get()).data();
  await assertSucceeds(ref.update({displayName: 'Valid update', email: 'valid@example.com', updatedAt: new Date()}));
  for (const fields of [{email: 5}, {email: {untrusted: true}}, {updatedAt: 'today'}, {updatedAt: {seconds: 0}}]) {
    await assertFails(ref.update(fields));
  }
  const missingEmail = {...original};
  delete missingEmail.email;
  await assertFails(ref.set(missingEmail));
});

test('Phase 4.1: registration validates an optional updatedAt timestamp', async () => {
  const owner = db('profile-create-schema');
  await assertFails(owner.doc('users/profile-create-schema').set({
    ...user('profile-create-schema', 'vendor', 'pending'), updatedAt: {untrusted: true},
  }));
});

test('Phase 4.1: new publications cannot bypass the 24-hour duration bound', async () => {
  await seed('duration-owner');
  const owner = db('duration-owner');
  const now = new Date();
  await assertFails(owner.doc('offers/multi-day').set(offer('duration-owner', {
    createdAt: now, expiryTime: new Date(+now + 25 * 60 * 60 * 1000),
  })));
  await assertSucceeds(owner.doc('offers/one-day').set(offer('duration-owner', {
    createdAt: now, expiryTime: new Date(+now + 24 * 60 * 60 * 1000),
  })));
});

test('Phase 4.1: new active offers cannot have expired or distant future publication times', async () => {
  await seed('timestamp-owner');
  const owner = db('timestamp-owner');
  const now = new Date();
  await assertFails(owner.doc('offers/already-expired').set(offer('timestamp-owner', {
    createdAt: new Date(+now - 2 * 60 * 60 * 1000), expiryTime: new Date(+now - 60 * 60 * 1000),
  })));
  await assertFails(owner.doc('offers/future-publication').set(offer('timestamp-owner', {
    createdAt: new Date(+now + 48 * 60 * 60 * 1000), expiryTime: new Date(+now + 49 * 60 * 60 * 1000),
  })));
});

test('Phase 4.1: editing cannot extend an offer beyond its original 24-hour publication window', async () => {
  await seed('edit-duration-owner');
  const owner = db('edit-duration-owner');
  const original = offer('edit-duration-owner');
  const ref = owner.doc('offers/edit-duration');
  await assertSucceeds(ref.set(original));
  await assertFails(ref.update({expiryTime: new Date(+original.createdAt + 25 * 60 * 60 * 1000)}));
  await assertSucceeds(ref.update({title: 'Valid title edit'}));

  const now = new Date();
  await env.withSecurityRulesDisabled(context => context.firestore().doc('offers/old-expired').set(
    offer('edit-duration-owner', {
      createdAt: new Date(+now - 48 * 60 * 60 * 1000),
      expiryTime: new Date(+now - 24 * 60 * 60 * 1000), status: 'expired',
    })));
  await assertFails(owner.doc('offers/old-expired').update({
    status: 'active', expiryTime: new Date(+now + 60 * 60 * 1000),
  }));
});

test('Phase 4.1: offer IDs containing regex syntax cannot reference a different offer upload', async () => {
  await seed('image-scope-owner');
  const owner = db('image-scope-owner');
  await assertFails(owner.doc('offers/.*').set(photo('image-scope-owner', 'different-offer')));
  await assertSucceeds(owner.doc('offers/.*').set(photo('image-scope-owner', '.*')));
  await assertSucceeds(owner.doc('offers/ordinary-offer').set(photo('image-scope-owner', 'ordinary-offer')));
  await assertFails(owner.doc('offers/ordinary-offer').update({
    imagePath: `offers/image-scope-owner/other-offer/${'a'.repeat(64)}.png`,
  }));
});

test('Phase 4.1: published image bytes stay immutable and cleanup stays safe after approval revocation', async () => {
  await seed('cleanup-invariant-owner');
  await seed('cleanup-invariant-other');
  const owner = db('cleanup-invariant-owner');
  const imagePath = `offers/cleanup-invariant-owner/protected/${'a'.repeat(64)}.png`;
  const ref = storage('cleanup-invariant-owner').ref(imagePath);
  await assertSucceeds(ref.put(Buffer.from('png'), {contentType: 'image/png'}));
  await assertSucceeds(owner.doc('offers/protected').set(photo('cleanup-invariant-owner', 'protected')));
  await assertSucceeds(ref.put(Buffer.from('png'), {contentType: 'image/png'}));
  await assertFails(ref.put(Buffer.from('new'), {contentType: 'image/png'}));
  await assertFails(ref.delete());
  await approval('cleanup-invariant-owner', 'rejected');
  await assertFails(ref.put(Buffer.from('png'), {contentType: 'image/png'}));
  await assertFails(ref.delete());
  await assertFails(storage('cleanup-invariant-other').ref(imagePath).delete());
  await assertFails(env.unauthenticatedContext().storage().ref(imagePath).delete());
  await assertFails(storage('cleanup-invariant-owner').ref(
    'offers/cleanup-invariant-owner/new-offer/new.png').put(Buffer.from('png'), {contentType: 'image/png'}));
  await assertSucceeds(owner.doc('offers/protected').delete());
  await assertSucceeds(ref.delete());
});
