# Executive Summary  
The proposed 5KM Sandhai prototype uses a Flutter front-end (Android/iOS) and Firebase back-end (Auth, Firestore, Cloud Functions, FCM, Storage) to implement a hyperlocal clearance marketplace. Vendors post urgent offers (with location) and all nearby customers (within 5–10 km) receive push notifications. We analyze the feasibility of the geospatial query (radius search), notification fan-out, and system scaling under Firebase’s free-tier constraints. Key findings: Firestore geohash-based queries require multiple range-queries and client-side filtering, which incurs some extra reads/latency. H3 hex indexing offers more uniform coverage than geohash but would need a custom implementation (no built-in Firestore support). FCM can deliver unlimited messages at no cost but send operations must be batched (500 tokens max per call). Cloud Functions cold starts (~300–500 ms) can add latency for infrequent events. Estimated demo monthly costs (Firestore + Functions + Storage) are on the order of a few hundred rupees, scaling to ~₹1000/month for 100k users (mostly Firestore read/write charges). Security rules must enforce role-based access (vendors vs consumers). We provide a minimal 3-tier architecture diagram, a prioritized 2-week task plan with estimates, cost tables, performance risks with mitigations, example Cloud Function pseudocode, a Firestore schema table with sample rules, and a testing strategy. All suggestions adhere to the “Firebase-friendly” stack (Flutter, OpenStreetMap, Razorpay, etc.) and target rapid MVP delivery.

## System Goals and Constraints  
- **Goals:** Real-time geo-fenced alerts within 5 km; sub-2 s end-to-end latency from offer post to user notification; support ~1K users/100 vendors in demo, scaling to ~100K users/10K vendors. Dual marketplace: (a) perishable clearance offers, (b) services directory.  
- **Constraints:** Use free-tier-friendly Firebase services (Firestore, Auth, Cloud Functions, FCM, Storage). Flutter front-end (single codebase). Maps via OpenStreetMap (flutter_map plugin). Razorpay for payment (no credit card data stored). All data in `asia-south1` region (Mumbai) for low latency.  
- **Data flow:** Vendor uses Flutter app to register (Auth) and post offers (with geo). Offers saved in Firestore. A Cloud Function (onCreate) computes geohash and queries for nearby users, then sends FCM push. User app shows a live feed/map of offers and allows call/WhatsApp contact. Razorpay payment is verified via a Cloud Function (HTTP webhook).  

## Architecture Diagram & Components  
```mermaid
graph LR
    subgraph Client
      A[Flutter App<br/>(Vendor/Customer)] 
    end
    A --> Auth[Firebase Auth]
    A --> FS[(Cloud Firestore)]
    A --> FS2[(Cloud Firestore)] %% separate for clarity (vendors/users collections)
    A --> S[Firebase Storage]
    A --> OSM[OpenStreetMap Tiles]
    Auth --> FS
    subgraph Backend
      FS --> CF1[Cloud Function<br/>(Offer GeoQuery+FCM)]
      Razorpay[Payment Gateway<br/>(Razorpay)] --> CF2[Cloud Function<br/>(Payment Webhook)]
      CF2 --> FS
      CF1 --> FCM[FCM Push Service]
    end
```
**Components (3-tier):**  
- **Presentation (Flutter App):** Single app with vendor/customer roles, using Firebase Auth. Integrates OpenStreetMap (free), geolocation, and FCM client SDK for notifications.  
- **Business Logic (Cloud Functions):**  
  - *OfferTriggerFn:* Triggered on Firestore `offers` create; computes geohash, radius-query, and fans out FCM messages.  
  - *PaymentWebhookFn:* HTTP-trigger to verify Razorpay payment (validate HMAC signature) and activate the vendor’s plan.  
  - (Optional *AdminFns* for vendor approval, analytics.)  
- **Data Layer:**  
  - *Firestore:* Collections for `vendors`, `offers`, `users` (see Schema below). Uses indexes on location/geohash. Mumbai region (`asia-south1`).  
  - *Firebase Storage:* Stores compressed images for offers. Default `*.appspot.com` bucket (5 GB free).  
  - *FCM:* Free unlimited push messaging.  

## Geo-query Patterns & Comparison  
We use geohash-based querying in Firestore, per Firebase’s recommended pattern. For a given center and radius:  
1. **Geohash query bounds:** Compute GeoHash ranges via GeoFireUtils (or custom). Typically up to 9 ranges, often ~4 at 5 km radius.  
2. **Firestore range queries:** For each bound, run `orderBy("geohash").startAt(minHash).endAt(maxHash)`. Combine results.  
3. **Filter false positives:** Firestore returns a superset of locations (geohash “bounding box”). Client code (Cloud Function) computes exact Haversine distance and discards points > radius. This incurs extra reads and latency. At high latitudes geohash distortions could increase false-positives (not a major issue in India’s mid-latitudes).  

**Geohash:** 
- Pros: Simple prefix queries; well-supported by libraries (GeoFireUtils).  
- Cons: False positives (need filtering); up to 9 range-queries per radius query. Non-uniform cell sizes near edges.  

**Uber H3:** 
- Uses hexagonal tiling for more uniform cell shapes. Less directional bias than geohash squares. H3 is hierarchical but “provides exact logical containment but only approximate geometric containment” (child hexagons may cross parent boundaries).  
- Pros: More uniform coverage, fewer neighbors to check.  
- Cons: No built-in Firestore support. Would require adding an H3 index field (at some resolution) on each document, and at query time computing a set of covering hexagon keys. Additional compute (H3 library) in Cloud Function. Likely fewer false positives at cost of more complex code.  

**Quadkey (Bing Maps):** 
- Quadtree tile key (string of 0–3 digits) representing map tiles (used by Bing Maps). Essentially square-grid indexing like geohash.  
- Pros: Hierarchical, easy to compute, might integrate similarly to geohash (prefix range queries).  
- Cons: Same fundamental issue of square cells: false positives and edge artifacts. Not natively supported in Firebase (would also store as a field and query).  

In summary, **geohash** is simplest with existing Firebase tooling (and official guidance). **H3** could yield more accuracy but at higher implementation cost. **Quadkey** is similar to geohash but not significantly better for this use-case. Given demo priorities, we recommend geohash. 

## Firebase Cloud Functions & FCM 
**Cold starts & concurrency:** Cloud Functions (1st Gen) cold-starts for Node.js are typically a few hundred milliseconds (often <500 ms) per idle instance. With light code and small bundle, warm latency is minimal (~10–50 ms). For low-throughput (demo) this is acceptable; at scale, consider Firebase Functions 2nd Gen or Cloud Run with managed concurrency to reduce cold-start impacts. Functions auto-scale on trigger. 

**FCM fan-out:** We use the Admin SDK’s multicast API. It allows up to **500 target tokens** per send, so large audiences must be chunked. FCM sends are fast (typically under 2–3 sec end-to-end) but delivery can be delayed by device/network conditions (Doze mode on Android, etc.). FCM itself is free and unlimited. We should implement retries/backoff for failures. 

**FCM capacity:** There is no hard published limit on total sends (it’s built for large scale). Key considerations:  
- Batching: Use `sendMulticast` in batches of ≤500 tokens.  
- Error handling: Handle rate-limit or transient errors by exponential backoff.  
- Token management: If we use a `users` collection to store each device’s FCM token, regularly prune invalid tokens.  

**Notification latency at scale:** In practice, FCM can deliver thousands of messages/sec, but if 10k vendors all post at once, the fan-out load could exceed a single Function’s capacity. Mitigations: limit pushes per instance, or shard by region. FCM itself uses persistent connections; under load, messages queue but will eventually deliver. Typical mobile push latency is <2 s when device is active. (Worst-case: if offline, messages are held up to TTL, then dropped.) 

## Firestore Costs, Limits, and Indexing  
**Free quotas:** On Spark (free) plan, Firestore allows 50K reads/day and 20K writes/day at no charge. Storage free up to 1 GiB, and network egress 10 GiB/month. For initial demo (1K users, 100 vendors, light usage), this covers most operations. Beyond free tier (Blaze plan), charges are: ~$0.03 per 100K reads, $0.09 per 100K writes (₹80≈$1, so ₹24/100K reads, ₹72/100K writes).  

**Storage:** Firebase Storage (for images) gives 5 GB free. Compressed offer images (few hundred KB each) likely stay under this for small-scale. After free, ~$0.026/GB (negligible for moderate usage). 

**Cost Estimates:**  
| Resource             | Demo (≈1k/100)      | Cost (₹) | Target (100k/10k)             | Cost (₹) |
|----------------------|---------------------|----------|-------------------------------|----------|
| **Firestore Reads**  | ~50K/day free tier  | ~₹0      | ≈30M/month (after 1.5M free)  | ~₹700    |
| **Firestore Writes** | ~5K/day free tier   | ~₹0      | ≈2M/month (after 600K free)   | ~₹100    |
| **Cloud Functions**  | ~100 invocations    | ~₹0      | ~1.5M/month (2M free tier)    | ~₹0      |
| **Firebase Storage** | ~200 MB images      | ~₹0      | ~3 GB (within 5GB free)       | ~₹0      |
| **Cloud Messaging**  | —                   | ~₹0      | —                             | ~₹0      |
| **Map Tiles (OSM)**  | —                   | ~₹0      | —                             | ~₹0      |
| **Total (approx)**   |  —                  | **₹0**   |  —                            | **≈₹800/month** |

*(Costs beyond free tier are rough; we assume ₹80=$1.)* Sources: Firestore pricing, Cloud Functions pricing, Storage pricing. In practice, expect <₹1000/month for 100k users (most cost from Firestore reads).  

## Implementation Checklist & Timeline  
**Key Tasks (ordered):**  

| Task                                        | Priority | Est. Effort |  
|---------------------------------------------|:--------:|:-----------:|  
| 1. Firebase project setup & security rules  | High     | 1d          |  
| 2. Flutter project & UI skeleton            | High     | 1d          |  
| 3. Auth integration (Vendor/Customer roles) | High     | 1d          |  
| 4. Vendor registration/profile screen       | High     | 1d          |  
| 5. Offer posting UI (incl. image upload)    | High     | 2d          |  
| 6. Store geolocation & geohash on offers    | High     | 0.5d        |  
| 7. Cloud Function: onCreate Offer → GeoQuery & FCM | High | 2d        |  
| 8. Consumer feed UI (map & list)            | Medium   | 2d          |  
| 9. FCM integration (Token handling, display)| High     | 1d          |  
| 10. Razorpay integration (UI + webhook)     | Medium   | 2d          |  
| 11. Vendor dashboard (views/calls metrics)  | Low      | 1d          |  
| 12. Testing, bug fixes, polish              | High     | 2d          |  

- *Note:* High-priority tasks must be done first. We assume 2 weeks (10 working days). Total ~14–15 person-days; may require 2 developers or adjusting scope.  

**2-Week Sprint Plan:**  

- **Week 1 (Days 1–5):**  
  - Firebase setup (Auth, Firestore rules/indices) & Flutter scaffolding.  
  - Implement Auth flows (vendor vs customer).  
  - Vendor signup/profile (with location auto-detect via device GPS).  
  - Basic UI for posting offers (form fields: title, prices, image, radius slider).  
  - Configure image compression (e.g. use `image` package in Flutter).  

- **Week 2 (Days 6–10):**  
  - Implement Firestore writes on offer submission (store `lat, lng, geohash`).  
  - Write Cloud Function (`offers.onCreate`) to query nearby users and send FCM.  This involves geohash range queries and filtering (see pseudocode below).  
  - Integrate FCM on client: request permission, get token, subscribe user document in Firestore.  
  - Build user feed view: query `offers` around user's current location, show on map/list.  
  - Add Razorpay payment screen for plan purchase; deploy Cloud Function webhook to verify payment signature and update vendor plan.  
  - Thorough testing of end-to-end flows.  
  - Polish UI, error handling, and validate security rules.  

Tasks in **bold** should be completed by the end of each week. Daily standups and code review to track progress.  

## Performance Risks & Mitigations  
- **Geospatial query load:** Geohash queries issue multiple index scans. In worst-case (high density of users/offers), the CF may run many Firestore queries. *Mitigation:* Limit query count by using only necessary bounds (GeoFireUtils often yields ~4 bounds for a 5 km circle). Use Firestore’s `limit()` if possible. Pre-compute geohash on write to avoid heavy computation in Function. Cache frequent queries if needed. If Firestore becomes bottleneck, consider migrating geospatial lookups to a specialized store (e.g. Cloud SQL with PostGIS, or a managed geo-index like Algolia or Google Maps Geospatial services) as a future improvement.  

- **Cloud Function latency:** Cold starts add ~0.3–0.5 s on first invocation; heavy CF code (large libraries) can increase this. *Mitigation:* Use Node.js 18+ with minimal dependencies; keep function code small. For demo, occasional cold start is acceptable. For scale, consider Functions (2nd Gen) or Cloud Run with provisioned concurrency.  

- **Push delivery delays:** While FCM is generally fast, mobile OS battery modes can delay delivery. *Mitigation:* Set appropriate message priority (high priority for immediate alerts). Allow app to fetch offers on resume as a backup to missed notifications. 

- **Write contention:** If many vendors post simultaneously, Firestore could hit per-collection limits. *Mitigation:* Unlikely at demo scale (100 posts/day). At scale, shard data if necessary, or throttle posting.  

- **Free-tier limits:** Exceeding free quotas (50K reads/day, 20K writes/day) will incur cost. *Mitigation:* Monitor usage; if hits near limit, either optimize queries or upgrade billing. (For demo targets, we calculated usage under thresholds.)  

- **Alternative stacks:** If Firebase proves limiting, one could use Cloud Run or App Engine with a relational DB (e.g. Cloud SQL Postgres + PostGIS) for geo queries, or use ElasticSearch for location search. However, these add complexity and cost; Firebase is sufficient for MVP.

## Sample Cloud Function Pseudocode  

```js
// Trigger: new offer document created
exports.offerCreated = functions.firestore
  .document('offers/{offerId}')
  .onCreate(async (snap, context) => {
  const offer = snap.data();
  const { lat, lng, radius } = offer; // e.g., radius in km
  // Compute geohash query bounds (GeoFireUtils example)
  const center = { latitude: lat, longitude: lng };
  const meters = radius * 1000;
  const bounds = GeoFireUtils.getGeoHashQueryBounds(center, meters);
  let tokens = [];

  // Query 'users' collection (each user doc has lat,lng,geohash, fcmToken)
  for (const b of bounds) {
    const q = db.collection('users')
                .orderBy('geohash')
                .startAt(b.lowerBound)
                .endAt(b.upperBound);
    const snapUsers = await q.get();
    for (const userDoc of snapUsers.docs) {
      const u = userDoc.data();
      // Calculate exact distance
      const dist = GeoFireUtils.distanceBetween(
        { latitude: u.lat, longitude: u.lng },
        center
      );
      if (dist <= meters) {
        tokens.push(u.fcmToken);
      }
    }
  }
  // Deduplicate tokens
  tokens = Array.from(new Set(tokens));
  // Send notifications in batches of 500
  const batchSize = 500;
  for (let i = 0; i < tokens.length; i += batchSize) {
    const chunk = tokens.slice(i, i + batchSize);
    try {
      await admin.messaging().sendMulticast({
        tokens: chunk,
        notification: {
          title: `Offer: ${offer.title}`,
          body: `Deal ${offer.oldPrice} → ${offer.newPrice}. Hurry, expires soon!`,
        },
        data: { offerId: snap.id }
      });
    } catch (err) {
      console.error('FCM send error:', err);
      // Optionally implement retry with exponential backoff
    }
  }
});
```

```js
// Payment webhook for Razorpay (HTTP function)
// Validates HMAC SHA256 signature
exports.razorpayWebhook = functions.https.onRequest(async (req, res) => {
  const webhookSecret = functions.config().razorpay.secret;
  const signature = req.headers['x-razorpay-signature'];
  const body = req.rawBody.toString(); // raw request body
  // Verify signature (using Razorpay SDK or manual HMAC)
  if (!Razorpay.utils.verifyWebhookSignature(body, signature, webhookSecret)) {
    console.warn('Invalid Razorpay signature');
    return res.status(400).send('Invalid signature');
  }
  const payload = JSON.parse(body);
  if (payload.event === 'payment.captured') {
    const vendorId = payload.payload.payment.entity.notes.vendor_id;
    // Update vendor plan in Firestore, set active/timestamp
    await db.collection('vendors').doc(vendorId).update({ planActive: true, planExpiry: /*...*/ });
  }
  res.status(200).send('OK');
});
```

## Firestore Schema & Security Rules  

**Collections and Fields:**  

| Collection  | Fields (Type)                                                    | Description                         |
|-------------|------------------------------------------------------------------|-------------------------------------|
| **vendors** | `vendorId` (docID)<br>`name` (string)<br>`phone` (string)<br>`whatsapp` (string)<br>`category` (string)<br>`lat`, `lng` (double)<br>`geohash` (string)<br>`plan` (string)<br>`approved` (bool) | Vendor profiles, store details    |
| **offers**  | `offerId` (docID)<br>`vendorId` (ref)<br>`title` (string)<br>`oldPrice`, `newPrice` (number)<br>`imageUrl` (string)<br>`headline` (string)<br>`expiryTime` (timestamp)<br>`radius` (number, km)<br>`createdAt` (timestamp)<br>`lat`, `lng`, `geohash` | Clearance offers by vendors       |
| **users**   | `userId` (docID)<br>`fcmToken` (string)<br>`lat`, `lng` (double)<br>`geohash` (string) | Consumer data (for push targeting) |

**Indexes:**  
- Single-field indexes on `geohash` are needed (default indexes suffice).  
- Composite indexes (if needed) for queries like `(category + geohash)` or `(category + location)`. Firestore will prompt for required indexes if you add filters/ordering.

**Security Rules (highlights):**  

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    // Vendor profiles
    match /vendors/{vendorId} {
      allow read: if true; // Public directory view (optional)
      allow write: if request.auth != null 
                   && request.auth.uid == vendorId 
                   && request.auth.token.role == 'vendor';
    }
    // Offers
    match /offers/{offerId} {
      allow read: if true;  // Everyone sees offers
      allow create: if request.auth != null 
                    && request.auth.token.role == 'vendor';
      allow update, delete: if request.auth != null 
                            && request.auth.uid == resource.data.vendorId;
    }
    // Users (FCM tokens)
    match /users/{userId} {
      allow write: if request.auth.uid == userId;
      allow read: if false; // or restrict to self if needed
    }
  }
}
```

These rules ensure only authenticated vendors can create/modify their own offers, and only themselves write their profile. Consumers’ FCM tokens are written only by themselves. Razorpay webhook and admin tasks use server privileges (no client access).  

## Testing Plan (Latency, Correctness, Load)  
- **Unit/Integration:** Use the Firebase Emulator Suite to test Functions and Firestore logic locally. Write unit tests (e.g. Jest) for critical functions (geohash queries, distance filtering, webhook verification). Validate security rules using Firebase Rules Unit Testing.  
- **Latency Measurement:** Instrument Cloud Functions to log processing time (or use [Cloud Logging Monitoring](https://cloud.google.com/logging)). Measure time from offer post to FCM call. On client, measure FCM receipt time. For worst-case, simulate devices in different networks.  
- **Correctness:** 
  - Verify geofence logic: Create test offers and user locations to ensure radius filtering is correct. 
  - Edge cases: near 5 km boundary, near poles/equator (should not matter for India). 
  - Data validation: test that Firestore security rules block unauthorized writes.  
- **Load Testing:** Simulate high load with tools like [Locust](https://locust.io/) or [JMeter](https://jmeter.apache.org/) by firing many offer-creation events (via REST API or Firebase load testing). This tests Firestore query throughput and CF scaling. For FCM, one can use Firebase’s [Performance Monitoring](https://firebase.google.com/docs/perf-mon) or custom logging to check notification delays when sending to thousands of simulated tokens.  
- **Monitoring:** Use Firebase Console and [Stackdriver Monitoring](https://cloud.google.com/monitoring) to track Firestore read/write rates, Function invocations, error rates.  

In summary, careful testing of the geo-query and FCM flows under both normal and heavy loads, combined with Firebase’s emulators and monitoring, will ensure the system meets the 2 s notification goal and handles scale.  

**Sources:** We based this design on Firebase’s official guides and pricing docs, Razorpay’s webhook validation docs, and H3/Quadkey references. These inform our approach to geospatial indexing, notification batching, and cost estimation.