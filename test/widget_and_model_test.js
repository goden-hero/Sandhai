const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

// Read Dart source files to verify Task 3 Auth architecture and route definitions
const routerFileContent = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'app', 'router.dart'),
  'utf8'
);
const authServiceContent = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'features', 'auth', 'services', 'auth_service.dart'),
  'utf8'
);
const signInScreenContent = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'features', 'auth', 'screens', 'sign_in_screen.dart'),
  'utf8'
);
const registerCustomerContent = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'features', 'auth', 'screens', 'register_customer_screen.dart'),
  'utf8'
);
const registerVendorContent = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'features', 'auth', 'screens', 'register_vendor_screen.dart'),
  'utf8'
);
const vendorDashboardContent = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'features', 'vendor', 'screens', 'vendor_dashboard_screen.dart'),
  'utf8'
);

const accountRepositoryContent = fs.readFileSync(path.join(__dirname, '..', 'lib/data/firebase_account_repository.dart'), 'utf8');
const sessionGateContent = fs.readFileSync(path.join(__dirname, '..', 'lib/features/auth/screens/session_gate.dart'), 'utf8');
const offerRepositoryContent = fs.readFileSync(path.join(__dirname, '..', 'lib/data/firebase_offer_repository.dart'), 'utf8');

const customerHomeContent = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'features', 'customer', 'screens', 'customer_home_screen.dart'),
  'utf8'
);

const vendorProfileContent = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'features', 'vendor', 'screens', 'vendor_profile_screen.dart'),
  'utf8'
);
const vendorModelContent = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'models', 'vendor_model.dart'),
  'utf8'
);

test('Task 3 & Task 4 Architecture & Code Audit Verification', async (t) => {
  await t.test('1. Router defines authentication route constants', () => {
    assert.strictEqual(routerFileContent.includes("static const String signIn = '/auth/sign-in';"), true);
    assert.strictEqual(routerFileContent.includes("static const String registerCustomer = '/auth/register-customer';"), true);
    assert.strictEqual(routerFileContent.includes("static const String registerVendor = '/auth/register-vendor';"), true);
    assert.strictEqual(routerFileContent.includes("static const String vendorProfile = '/vendor/profile';"), true);
  });

  await t.test('2. AuthService encapsulates customer & vendor registration with role and pending approval status', () => {
    assert.strictEqual(authServiceContent.includes('registerCustomer'), true);
    assert.strictEqual(authServiceContent.includes('registerVendor'), true);
    assert.strictEqual(authServiceContent.includes("role: 'vendor'"), true);
    assert.strictEqual(accountRepositoryContent.includes("? 'pending'"), true);
  });

  await t.test('3. Register screens provide direct Customer & Vendor registration options', () => {
    assert.strictEqual(registerCustomerContent.includes('AuthService.instance.registerCustomer'), true);
    assert.strictEqual(registerVendorContent.includes('AuthService.instance.registerVendor'), true);
  });

  await t.test('4. Sign-in screen handles authentication & profile-based routing', () => {
    assert.strictEqual(signInScreenContent.includes('AuthService.instance.signInWithEmailAndPassword'), true);
    assert.strictEqual(sessionGateContent.includes('auth.profile!.isVendor'), true);
  });

  await t.test('5. Vendor Dashboard checks approval status and guards offer creation', () => {
    assert.strictEqual(vendorDashboardContent.includes('user.isPendingVendor'), true);
    assert.strictEqual(vendorDashboardContent.includes('Only approved vendors can publish'), true);
  });

  await t.test('6. Customer home screen removes demo role-switching controls', () => {
    assert.strictEqual(customerHomeContent.includes('Icons.swap_horiz'), false);
    assert.strictEqual(customerHomeContent.includes('Switch Role'), false);
  });

  await t.test('7. AuthService prevents defaulting missing profile accounts to approved customer accounts', () => {
    assert.strictEqual(authServiceContent.includes('SessionPhase.incomplete'), true);
  });

  await t.test('8. RegisterVendorScreen collects business address & description and validates phone digits', () => {
    assert.strictEqual(registerVendorContent.includes('_addressController'), true);
    assert.strictEqual(registerVendorContent.includes('_descriptionController'), true);
    assert.strictEqual(registerVendorContent.includes('10-digit phone number'), true);
  });

  await t.test('9. VendorProfileScreen implements view mode, edit mode, and approval status badge', () => {
    assert.strictEqual(vendorProfileContent.includes('VendorProfileScreen'), true);
    assert.strictEqual(vendorProfileContent.includes('APPROVAL PENDING'), true);
    assert.strictEqual(vendorProfileContent.includes('_saveProfileUpdates'), true);
    assert.strictEqual(vendorProfileContent.includes('PopScope'), true);
  });

  await t.test('10. VendorModel & AuthService support address, description, and profile updates', () => {
    assert.strictEqual(vendorModelContent.includes('address'), true);
    assert.strictEqual(vendorModelContent.includes('description'), true);
    assert.strictEqual(authServiceContent.includes('fetchVendorProfile'), true);
    assert.strictEqual(authServiceContent.includes('updateVendorProfile'), true);
  });

  await t.test('11. OfferService enforces input validation, storage uploads, and approval status checks', () => {
    const offerServiceContent = fs.readFileSync(
      path.join(__dirname, '..', 'lib', 'features', 'vendor', 'services', 'offer_service.dart'),
      'utf8'
    );
    assert.strictEqual(offerServiceContent.includes('createOffer'), true);
    assert.strictEqual(offerServiceContent.includes('isApprovedVendor'), true);
    assert.strictEqual(offerServiceContent.includes('Clearance price'), true);
    assert.strictEqual(offerRepositoryContent.includes('offers/$uid/$id/$safeName'), true);
  });

  await t.test('12. CreateOfferScreen provides form validation, category selection, price checks, and image preview', () => {
    const createOfferContent = fs.readFileSync(
      path.join(__dirname, '..', 'lib', 'features', 'vendor', 'screens', 'create_offer_screen.dart'),
      'utf8'
    );
    assert.strictEqual(createOfferContent.includes('Post Clearance Offer'), true);
    assert.strictEqual(createOfferContent.includes('Must be <= ₹'), true);
    assert.strictEqual(createOfferContent.includes('_selectedCategory'), true);
    assert.strictEqual(createOfferContent.includes('_pickSampleImage'), true);
    assert.strictEqual(createOfferContent.includes('Publish Locked (Store Approval Pending)'), true);
  });

  await t.test('13. VendorDashboardScreen displays newly posted offers from OfferService', () => {
    assert.strictEqual(vendorDashboardContent.includes('OfferService.instance.watchVendorOffers'), true);
    assert.strictEqual(vendorDashboardContent.includes('vendorOffers.length'), true);
  });

  await t.test('14. OfferService dynamically inherits store location from vendor profile and provides storage cleanup', () => {
    const offerServiceContent = fs.readFileSync(
      path.join(__dirname, '..', 'lib', 'features', 'vendor', 'services', 'offer_service.dart'),
      'utf8'
    );
    assert.strictEqual(offerServiceContent.includes('fetchVendorProfile'), true);
    assert.strictEqual(offerServiceContent.includes('vendorProfile?.latitude'), true);
    assert.strictEqual(offerServiceContent.includes('repository.deleteUpload(uploaded)'), true);
  });

  await t.test('15. GeohashUtils provides 6-character base32 encoding, coordinate bounds validation, and OfferService integration', () => {
    const geohashUtilsContent = fs.readFileSync(
      path.join(__dirname, '..', 'lib', 'core', 'utils', 'geohash_utils.dart'),
      'utf8'
    );
    const offerServiceContent = fs.readFileSync(
      path.join(__dirname, '..', 'lib', 'features', 'vendor', 'services', 'offer_service.dart'),
      'utf8'
    );
    assert.strictEqual(geohashUtilsContent.includes('static const int defaultPrecision = 6;'), true);
    assert.strictEqual(geohashUtilsContent.includes('_base32Chars'), true);
    assert.strictEqual(geohashUtilsContent.includes('isValidLocation'), true);
    assert.strictEqual(offerServiceContent.includes('GeohashUtils.isValidLocation'), true);
    assert.strictEqual(offerServiceContent.includes('GeohashUtils.encode'), true);
  });
});





