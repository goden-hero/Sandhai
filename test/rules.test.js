const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const test = require('node:test');
const assert = require('node:assert');

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'sandhai-phase3-tests';

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
      port: Number(process.env.FIRESTORE_EMULATOR_HOST?.split(':').pop() || 8180),
    },
    storage: {
      rules: storageRules,
      host: '127.0.0.1',
      port: Number(process.env.FIREBASE_STORAGE_EMULATOR_HOST?.split(':').pop() || 9299),
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
    if (role === 'vendor') await db.collection('vendors').doc(uid).set(vendorData());
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
      geohash: 'tf346t',
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
      imageUrl: '',
      category: 'groceries',
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: 'tf346t',
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
      imageUrl: '',
      category: 'groceries',
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: 'tf346t',
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
      imageUrl: '',
      category: 'groceries',
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: 'tf346t',
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
      imageUrl: '',
      category: 'groceries',
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: 'tf346t',
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
      imageUrl: '',
      category: 'groceries',
      latitude: 13.0827,
      longitude: 80.2707,
      geohash: 'tf346t',
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
      imageUrl: '',
      category: 'groceries',
      latitude: 100.0,
      longitude: 80.2707,
      geohash: 'tf346t',
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
      imageUrl: '',
      category: 'groceries',
      latitude: 13.0827,
      longitude: 200.0,
      geohash: 'tf346t',
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
      imageUrl: '',
      category: 'groceries',
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
      geohash: 'tf346t',
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



// Phase 2: online transactions, completion, account isolation, and upload cleanup.
function userData(uid, role='vendor', status='pending') {
  return {displayName:'Persistent Store',email:`${uid}@example.com`,role,approvalStatus:status,createdAt:new Date()};
}
function vendorData() {
  return {name:'Persistent Store',phone:'9876543210',category:'Groceries',address:'Store address',
    latitude:13.0827,longitude:80.2707,geohash:'tf346t',locationConfirmedAt:new Date(),createdAt:new Date()};
}
function offerData(uid, status='active') {
  const now=new Date();
  return {vendorId:uid,title:'Persistent offer',description:'Clearance stock',oldPrice:100,newPrice:50,imageUrl:'',
    category:'groceries',latitude:13.0827,longitude:80.2707,geohash:'tf346t',createdAt:now,expiryTime:new Date(+now+3600000),status};
}

test('13. Atomic vendor completion creates both profiles and never grants approval', async()=>{
  const db=testEnv.authenticatedContext('atomicVendor').firestore();
  await assertSucceeds(db.runTransaction(async tx=>{
    const u=db.doc('users/atomicVendor'),v=db.doc('vendors/atomicVendor');
    await tx.get(u); await tx.get(v);
    tx.set(u,userData('atomicVendor')); tx.set(v,vendorData());
  }));
  assert.equal((await db.doc('users/atomicVendor').get()).data().approvalStatus,'pending');
  assert.equal((await db.doc('vendors/atomicVendor').get()).data().name,'Persistent Store');
  const bad=testEnv.authenticatedContext('selfApprovedAtomic').firestore();
  const batch=bad.batch(); batch.set(bad.doc('users/selfApprovedAtomic'),userData('selfApprovedAtomic','vendor','approved'));
  batch.set(bad.doc('vendors/selfApprovedAtomic'),vendorData()); await assertFails(batch.commit());
});

test('14. Existing incomplete vendors can finish their store without resetting approval',async()=>{
  await seedUser('partialVendor','vendor','approved');
  const db=testEnv.authenticatedContext('partialVendor').firestore();
  const before=(await db.doc('users/partialVendor').get()).data();
  await assertSucceeds(db.runTransaction(async tx=>{
    const user=await tx.get(db.doc('users/partialVendor'));
    const vendor=await tx.get(db.doc('vendors/partialVendor'));
    assert.equal(user.data().role,'vendor');
    if(!vendor.exists)tx.set(db.doc('vendors/partialVendor'),vendorData());
  }));
  assert.deepEqual((await db.doc('users/partialVendor').get()).data(),before);
  await assertFails(db.doc('users/partialVendor').update({role:'customer'}));
  await assertFails(db.doc('users/partialVendor').update({approvalStatus:'pending'}));
});

test('15. Profile transaction failure rolls back the user display name too',async()=>{
  await seedUser('profileAtomic','vendor','pending','Original');
  await seedVendor('profileAtomic','Original','9876543210','Groceries');
  const db=testEnv.authenticatedContext('profileAtomic').firestore();
  await assertFails(db.runTransaction(async tx=>{
    await tx.get(db.doc('users/profileAtomic')); await tx.get(db.doc('vendors/profileAtomic'));
    tx.update(db.doc('users/profileAtomic'),{displayName:'False success'});
    tx.update(db.doc('vendors/profileAtomic'),{name:'False success',phone:''});
  }));
  assert.equal((await db.doc('users/profileAtomic').get()).data().displayName,'Original');
  assert.equal((await db.doc('vendors/profileAtomic').get()).data().name,'Original');
});

test('16. Vendor-scoped queries retain private offers and block other private dashboards',async()=>{
  await seedUser('privateA','vendor','approved'); await seedUser('privateB','vendor','approved');
  await seedOffer('aDraft','privateA',{status:'draft'}); await seedOffer('bDraft','privateB',{status:'draft'});
  const a=testEnv.authenticatedContext('privateA').firestore();
  const own=await assertSucceeds(a.collection('offers').where('vendorId','==','privateA').orderBy('createdAt','desc').get());
  assert.deepEqual(own.docs.map(d=>d.id),['aDraft']);
  await assertFails(a.collection('offers').where('vendorId','==','privateB').get());
  await assertFails(a.doc('offers/bDraft').get());
});

test('17. Offer transactions use a stable ID and approval remains authoritative',async()=>{
  await seedUser('stableVendor','vendor','approved');
  const db=testEnv.authenticatedContext('stableVendor').firestore();
  async function save(){return db.runTransaction(async tx=>{
    await tx.get(db.doc('users/stableVendor'));
    const ref=db.doc('offers/stableOffer'); const old=await tx.get(ref);
    if(!old.exists) tx.set(ref,offerData('stableVendor'));
  });}
  await assertSucceeds(save()); await assertSucceeds(save());
  assert.equal((await db.collection('offers').where('vendorId','==','stableVendor').get()).size,1);
  await seedUser('stableVendor','vendor','suspended');
  await assertFails(db.collection('offers').add(offerData('stableVendor')));
});

test('18. Approval snapshots update an already authenticated client',async()=>{
  await seedUser('observedVendor','vendor','pending');
  const db=testEnv.authenticatedContext('observedVendor').firestore();
  const statuses=[];
  let stop;
  try {
    await new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>reject(new Error('Approval subscription timed out')),10000);
      stop=db.doc('users/observedVendor').onSnapshot(async doc=>{
        const status=doc.data().approvalStatus; statuses.push(status);
        try {
          if(status==='pending')await seedUser('observedVendor','vendor','approved');
          if(status==='approved')await seedUser('observedVendor','vendor','rejected');
          if(status==='rejected'){clearTimeout(timeout);resolve();}
        }catch(e){clearTimeout(timeout);reject(e);}
      },reject);
    });
    assert.deepEqual(statuses,['pending','approved','rejected']);
  }finally{if(stop)stop();}
});

test('19. Upload errors reject and owners can clean up after revoked approval',async()=>{
  await seedUser('cleanupVendor','vendor','approved'); await seedUser('cleanupOther','vendor','approved');
  const storage=testEnv.authenticatedContext('cleanupVendor').storage();
  const ref=storage.ref('offers/cleanupVendor/offer/image.png');
  await assertSucceeds(ref.put(Buffer.from([137,80,78,71]),{contentType:'image/png'}));
  await seedUser('cleanupVendor','vendor','suspended');
  await assertFails(storage.ref('offers/cleanupVendor/offer/new.png').put(Buffer.from('x'),{contentType:'image/png'}));
  await assertFails(testEnv.authenticatedContext('cleanupOther').storage().ref(ref.fullPath).delete());
  await assertSucceeds(ref.delete());
  await seedUser('cleanupVendor','vendor','approved');
  await assertFails(storage.ref('offers/cleanupVendor/offer/text.txt').put(Buffer.from('not an image'),{contentType:'text/plain'}));
});

test('20. Offer field injection is rejected on creation and update',async()=>{
  await seedUser('offerFields','vendor','approved'); const db=testEnv.authenticatedContext('offerFields').firestore();
  await assertFails(db.doc('offers/injected').set({...offerData('offerFields'),isAdmin:true}));
  await assertSucceeds(db.doc('offers/clean').set(offerData('offerFields')));
  await assertFails(db.doc('offers/clean').update({isAdmin:true}));
});

test('21. Unconfirmed legacy coordinates cannot publish; confirmed store snapshots must match', async()=>{
  await seedUser('locationVendor','vendor','approved');
  const db=testEnv.authenticatedContext('locationVendor').firestore();
  await testEnv.withSecurityRulesDisabled(c=>c.firestore().doc('vendors/locationVendor').set({...vendorData(),locationConfirmedAt:null}));
  await assertFails(db.doc('offers/unconfirmed').set(offerData('locationVendor')));
  await assertSucceeds(db.doc('vendors/locationVendor').update({locationConfirmedAt:new Date()}));
  await assertSucceeds(db.doc('offers/confirmed').set(offerData('locationVendor')));
  for(const fields of [{latitude:0},{longitude:0},{geohash:'tf340w'},{latitude:NaN},{longitude:Infinity}]) {
    await assertFails(db.collection('offers').add({...offerData('locationVendor'),...fields}));
  }
});
test('22. Registration permits absent coordinates; invalid or partial confirmed locations fail',async()=>{
  await seedUser('emptyLocation','vendor','pending');
  const db=testEnv.authenticatedContext('emptyLocation').firestore();
  await testEnv.withSecurityRulesDisabled(c=>c.firestore().doc('vendors/emptyLocation').delete());
  const minimal={name:'No fabricated location',phone:'9876543210',category:'groceries',createdAt:new Date()};
  await assertSucceeds(db.doc('vendors/emptyLocation').set(minimal));
  for(const fields of [{latitude:12},{latitude:91,longitude:20,geohash:'s00000'}, {latitude:NaN,longitude:20,geohash:'s00000'}, {latitude:12,longitude:20,geohash:'!!!!!!'}, {locationConfirmedAt:true}]) {
    await assertFails(db.doc('vendors/emptyLocation').update(fields));
  }
});
test('23. Offer category, numeric types, image metadata, ownership and required keys are enforced',async()=>{
  await seedUser('schemaVendor','vendor','approved');
  const db=testEnv.authenticatedContext('schemaVendor').firestore();
  const base=offerData('schemaVendor');
  for(const fields of [{category:'Bakery & Dairy'},{category:'unknown'},{category:4},{oldPrice:'100'},{oldPrice:Infinity},{newPrice:NaN},{vendorId:'another'},{imageUrl:4},{expiryTime:'tomorrow'},{imagePath:'offers/other/id/image.png'}]) {
    await assertFails(db.collection('offers').add({...base,...fields}));
  }
  for(const key of Object.keys(base)) { const invalid={...base};delete invalid[key];await assertFails(db.collection('offers').add(invalid)); }
  const path=`offers/schemaVendor/photo/${'a'.repeat(64)}.png`;
  const photo={...base,imageUrl:'http://127.0.0.1:9299/image',imagePath:path,imageContentType:'image/png',imageSize:123};
  await assertSucceeds(db.doc('offers/photo').set(photo));
  await assertFails(db.doc('offers/photo').update({imageContentType:'image/jpeg'}));
  await assertFails(db.doc('offers/photo').update({imageSize:5242881}));
  await assertFails(db.doc('offers/photo').update({imageSize:0}));
  await assertFails(db.doc('offers/photo').update({latitude:12}));
  const downgrade={...photo};delete downgrade.imagePath;delete downgrade.imageContentType;delete downgrade.imageSize;
  await assertFails(db.doc('offers/photo').set(downgrade));
});
test('24. Storage MIME/extension/size checks and deletion are separate; published photos are protected',async()=>{
  await seedUser('photoOwner','vendor','approved');await seedUser('photoOther','vendor','approved');
  const storage=testEnv.authenticatedContext('photoOwner').storage();
  for(const [name,mime,bytes] of [['bad.jpg','image/png',Buffer.from('x')],['zero.png','image/png',Buffer.alloc(0)],['big.png','image/png',Buffer.alloc(5242881)]]) {
    await assertFails(storage.ref(`offers/photoOwner/photo/${name}`).put(bytes,{contentType:mime}));
  }
  const imagePath=`offers/photoOwner/photo/${'b'.repeat(64)}.png`;
  const ref=storage.ref(imagePath);await assertSucceeds(ref.put(Buffer.from('png'),{contentType:'image/png'}));
  await testEnv.withSecurityRulesDisabled(c=>c.firestore().doc('offers/photo').set({...offerData('photoOwner'),imagePath}));
  await assertFails(ref.delete());
  await assertFails(ref.put(Buffer.from('different bytes'),{contentType:'image/png'}));
  await assertFails(testEnv.authenticatedContext('photoOther').storage().ref(imagePath).delete());
  await testEnv.withSecurityRulesDisabled(c=>c.firestore().doc('offers/photo').delete());
  await seedUser('photoOwner','vendor','suspended');await assertSucceeds(ref.delete());
});
