const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const test = require('node:test');
const assert = require('node:assert');

const PROJECT_ID = 'sandhai-5km-demo';

let testEnv;

test.before(async () => {
  const firestoreRules = fs.readFileSync(
    path.join(__dirname, '..', 'firestore.rules'),
    'utf8'
  );
  const storageRules = fs.readFileSync(
    path.join(__dirname, '..', 'storage.rules'),
    'utf8'
  );

  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: firestoreRules,
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: storageRules,
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

test.after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

test.beforeEach(async () => {
  if (testEnv) {
    await testEnv.clearFirestore();
  }
});

// Helper to seed user document using admin context
async function seedUser(uid, role, approvalStatus = 'approved', displayName = 'Test User') {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('users').doc(uid).set({
      displayName,
      email: `${uid}@example.com`,
      role,
      approvalStatus,
      createdAt: new Date(),
    });
  });
}

// Helper to seed offer document using admin context
async function seedOffer(offerId, vendorId, extra = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const now = new Date();
    const expiry = new Date(now.getTime() + 24 * 60 * 60 * 1000);
    await db.collection('offers').doc(offerId).set({
      vendorId,
      title: 'Fresh Tomatoes',
      description: 'Organic fresh tomatoes 1kg clearance',
      oldPrice: 100.0,
      newPrice: 50.0,
      imageUrl: 'https://storage.example.com/tomatoes.jpg',
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: 'tf340w',
      createdAt: now,
      expiryTime: expiry,
      status: 'active',
      ...extra,
    });
  });
}

// --- TEST SUITE FOR TASK 1 & TASK 3 SECURITY RULES ---

test('1. An unauthenticated user cannot create an offer', async () => {
  const unauthDb = testEnv.unauthenticatedContext().firestore();
  const now = new Date();
  const expiry = new Date(now.getTime() + 3600000);

  await assertFails(
    unauthDb.collection('offers').add({
      vendorId: 'vendor123',
      title: 'Unauth Offer',
      description: 'Test description',
      oldPrice: 100.0,
      newPrice: 50.0,
      imageUrl: 'https://example.com/img.jpg',
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: 'tf340w',
      createdAt: now,
      expiryTime: expiry,
      status: 'active',
    })
  );
});

test('2. A customer cannot create an offer', async () => {
  await seedUser('cust123', 'customer', 'approved', 'Customer User');
  const custDb = testEnv.authenticatedContext('cust123').firestore();
  const now = new Date();
  const expiry = new Date(now.getTime() + 3600000);

  await assertFails(
    custDb.collection('offers').add({
      vendorId: 'cust123',
      title: 'Customer Offer',
      description: 'Should fail',
      oldPrice: 100.0,
      newPrice: 50.0,
      imageUrl: 'https://example.com/img.jpg',
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: 'tf340w',
      createdAt: now,
      expiryTime: expiry,
      status: 'active',
    })
  );
});

test('3. Vendor self-registration enforces pending approval status', async () => {
  const vendorDb = testEnv.authenticatedContext('newVendor1').firestore();

  // 3a. Registering with approvalStatus == 'pending' succeeds
  await assertSucceeds(
    vendorDb.collection('users').doc('newVendor1').set({
      displayName: 'New Fresh Store',
      email: 'store@example.com',
      role: 'vendor',
      approvalStatus: 'pending',
      createdAt: new Date(),
    })
  );

  // 3b. Registering with approvalStatus == 'approved' fails (no self-approval)
  const vendorDb2 = testEnv.authenticatedContext('sneakyVendor').firestore();
  await assertFails(
    vendorDb2.collection('users').doc('sneakyVendor').set({
      displayName: 'Sneaky Store',
      email: 'sneaky@example.com',
      role: 'vendor',
      approvalStatus: 'approved', // Invalid! Must start as pending
      createdAt: new Date(),
    })
  );
});

test('4. Pending vendor cannot create an offer, approved vendor can', async () => {
  await seedUser('pendingVendor', 'vendor', 'pending', 'Pending Store');
  await seedUser('approvedVendor', 'vendor', 'approved', 'Approved Store');

  const pendingDb = testEnv.authenticatedContext('pendingVendor').firestore();
  const approvedDb = testEnv.authenticatedContext('approvedVendor').firestore();
  const now = new Date();
  const expiry = new Date(now.getTime() + 3600000);

  // 4a. Pending vendor creating offer fails
  await assertFails(
    pendingDb.collection('offers').add({
      vendorId: 'pendingVendor',
      title: 'Blocked Offer',
      description: 'Pending vendor trying to publish',
      oldPrice: 100.0,
      newPrice: 50.0,
      imageUrl: 'https://example.com/img.jpg',
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: 'tf340w',
      createdAt: now,
      expiryTime: expiry,
      status: 'active',
    })
  );

  // 4b. Approved vendor creating offer succeeds
  await assertSucceeds(
    approvedDb.collection('offers').add({
      vendorId: 'approvedVendor',
      title: 'Approved Offer',
      description: 'Approved vendor publishing',
      oldPrice: 100.0,
      newPrice: 50.0,
      imageUrl: 'https://example.com/img.jpg',
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: 'tf340w',
      createdAt: now,
      expiryTime: expiry,
      status: 'active',
    })
  );
});

test('5. Vendor cannot modify their own approvalStatus or role via profile update', async () => {
  await seedUser('vendorPending', 'vendor', 'pending', 'Pending Store');
  const vendorDb = testEnv.authenticatedContext('vendorPending').firestore();

  // 5a. Trying to self-approve via update fails
  await assertFails(
    vendorDb.collection('users').doc('vendorPending').update({
      approvalStatus: 'approved',
    })
  );

  // 5b. Trying to change role to admin or customer fails
  await assertFails(
    vendorDb.collection('users').doc('vendorPending').update({
      role: 'customer',
    })
  );
});

test('6. A customer can read public active offers', async () => {
  await seedOffer('activeOffer1', 'approvedVendor', { status: 'active' });
  const custDb = testEnv.authenticatedContext('cust123').firestore();

  await assertSucceeds(
    custDb.collection('offers').doc('activeOffer1').get()
  );
});

test('7. Invalid offer data is rejected', async () => {
  await seedUser('approvedVendor', 'vendor', 'approved', 'Approved Store');
  const vendorDb = testEnv.authenticatedContext('approvedVendor').firestore();
  const now = new Date();
  const expiry = new Date(now.getTime() + 3600000);

  // 7a. Overpriced offer (newPrice > oldPrice)
  await assertFails(
    vendorDb.collection('offers').add({
      vendorId: 'approvedVendor',
      title: 'Overpriced Offer',
      description: 'Invalid price',
      oldPrice: 50.0,
      newPrice: 100.0,
      imageUrl: 'https://example.com/img.jpg',
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: 'tf340w',
      createdAt: now,
      expiryTime: expiry,
      status: 'active',
    })
  );

  // 7b. Out-of-bounds latitude (> 90.0)
  await assertFails(
    vendorDb.collection('offers').add({
      vendorId: 'approvedVendor',
      title: 'Invalid Lat Offer',
      description: 'Latitude 100.0',
      oldPrice: 100.0,
      newPrice: 50.0,
      imageUrl: 'https://example.com/img.jpg',
      latitude: 100.0,
      longitude: 80.2707,
      geohash: 'tf340w',
      createdAt: now,
      expiryTime: expiry,
      status: 'active',
    })
  );

  // 7c. Out-of-bounds longitude (> 180.0)
  await assertFails(
    vendorDb.collection('offers').add({
      vendorId: 'approvedVendor',
      title: 'Invalid Lng Offer',
      description: 'Longitude 200.0',
      oldPrice: 100.0,
      newPrice: 50.0,
      imageUrl: 'https://example.com/img.jpg',
      latitude: 13.0827,
      longitude: 200.0,
      geohash: 'tf340w',
      createdAt: now,
      expiryTime: expiry,
      status: 'active',
    })
  );

  // 7d. Invalid geohash format (empty string)
  await assertFails(
    vendorDb.collection('offers').add({
      vendorId: 'approvedVendor',
      title: 'Invalid Geohash Offer',
      description: 'Empty geohash',
      oldPrice: 100.0,
      newPrice: 50.0,
      imageUrl: 'https://example.com/img.jpg',
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: '',
      createdAt: now,
      expiryTime: expiry,
      status: 'active',
    })
  );
});

test('8. Unauthorized image uploads are rejected', async () => {
  const unauthStorage = testEnv.unauthenticatedContext().storage();
  const vendorAStorage = testEnv.authenticatedContext('vendorA').storage();
  const buffer = Buffer.from('fake image data');

  // Unauthenticated upload
  await assertFails(
    unauthStorage
      .ref('offers/vendorA/image.jpg')
      .put(buffer, { contentType: 'image/jpeg' })
  );

  // Vendor A uploading to Vendor B path
  await assertFails(
    vendorAStorage
      .ref('offers/vendorB/image.jpg')
      .put(buffer, { contentType: 'image/jpeg' })
  );
});

test('9. Storage uploads require approved vendor status (pending vendor & customer blocked)', async () => {
  await seedUser('approvedStorageVendor', 'vendor', 'approved', 'Approved Store');
  await seedUser('pendingStorageVendor', 'vendor', 'pending', 'Pending Store');
  await seedUser('customerUser', 'customer', 'approved', 'Customer');

  const approvedStorage = testEnv.authenticatedContext('approvedStorageVendor').storage();
  const pendingStorage = testEnv.authenticatedContext('pendingStorageVendor').storage();
  const customerStorage = testEnv.authenticatedContext('customerUser').storage();
  const buffer = Buffer.from('fake image content');

  // Approved vendor uploading to their path succeeds
  await assertSucceeds(
    approvedStorage
      .ref('offers/approvedStorageVendor/item.png')
      .put(buffer, { contentType: 'image/png' })
  );

  // Pending vendor uploading to their path fails
  await assertFails(
    pendingStorage
      .ref('offers/pendingStorageVendor/item.png')
      .put(buffer, { contentType: 'image/png' })
  );

  // Customer uploading to their path fails
  await assertFails(
    customerStorage
      .ref('offers/customerUser/item.png')
      .put(buffer, { contentType: 'image/png' })
  );
});

test('10. Profile schema tampering (extra arbitrary fields) is rejected', async () => {
  const userDb = testEnv.authenticatedContext('hackerUser').firestore();

  // Creation with extra unauthorized field 'isAdmin' fails
  await assertFails(
    userDb.collection('users').doc('hackerUser').set({
      displayName: 'Hacker User',
      email: 'hacker@example.com',
      role: 'customer',
      approvalStatus: 'approved',
      createdAt: new Date(),
      isAdmin: true, // Extra forbidden field
    })
  );
});

// Helper to seed vendor document using admin context
async function seedVendor(uid, name, phone, category, createdAt = new Date()) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('vendors').doc(uid).set({
      name,
      phone,
      category,
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: 'tf340w',
      createdAt,
    });
  });
}

test('11. Vendor can update permitted profile fields on their own document', async () => {
  const seededTime = new Date();
  await seedUser('vendorUpdateOwner', 'vendor', 'pending', 'Store Owner');
  await seedVendor('vendorUpdateOwner', 'Original Store', '9876543210', 'Groceries', seededTime);

  const vendorDb = testEnv.authenticatedContext('vendorUpdateOwner').firestore();

  // Vendor updating their own store fields succeeds
  await assertSucceeds(
    vendorDb.collection('vendors').doc('vendorUpdateOwner').update({
      name: 'Updated Store Name',
      phone: '9876543210',
      category: 'Produce',
      address: '42 Usman Road, T. Nagar, Chennai',
      description: 'Updated clearance store description',
    })
  );
});

test('12. Vendor cannot update another vendor profile document', async () => {
  await seedUser('vendorA', 'vendor', 'approved', 'Store A');
  await seedUser('vendorB', 'vendor', 'approved', 'Store B');
  await seedVendor('vendorB', 'Store B', '9876543210', 'Groceries');

  const vendorADb = testEnv.authenticatedContext('vendorA').firestore();

  // Vendor A attempting to update Vendor B profile fails
  await assertFails(
    vendorADb.collection('vendors').doc('vendorB').update({
      name: 'Hacked Store B Name',
    })
  );
});


