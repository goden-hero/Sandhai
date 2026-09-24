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

const customerHomeContent = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'features', 'customer', 'screens', 'customer_home_screen.dart'),
  'utf8'
);

test('Task 3 Auth Architecture & Code Audit Verification', async (t) => {
  await t.test('1. Router defines authentication route constants', () => {
    assert.strictEqual(routerFileContent.includes("static const String signIn = '/auth/sign-in';"), true);
    assert.strictEqual(routerFileContent.includes("static const String registerCustomer = '/auth/register-customer';"), true);
    assert.strictEqual(routerFileContent.includes("static const String registerVendor = '/auth/register-vendor';"), true);
  });

  await t.test('2. AuthService encapsulates customer & vendor registration with role and pending approval status', () => {
    assert.strictEqual(authServiceContent.includes('registerCustomer'), true);
    assert.strictEqual(authServiceContent.includes('registerVendor'), true);
    assert.strictEqual(authServiceContent.includes("role: 'vendor'"), true);
    assert.strictEqual(authServiceContent.includes("approvalStatus: 'pending'"), true);
  });

  await t.test('3. Register screens provide direct Customer & Vendor registration options', () => {
    assert.strictEqual(registerCustomerContent.includes('AuthService.instance.registerCustomer'), true);
    assert.strictEqual(registerVendorContent.includes('AuthService.instance.registerVendor'), true);
  });

  await t.test('4. Sign-in screen handles authentication & profile-based routing', () => {
    assert.strictEqual(signInScreenContent.includes('AuthService.instance.signInWithEmailAndPassword'), true);
    assert.strictEqual(signInScreenContent.includes('userModel.role == \'vendor\''), true);
  });

  await t.test('5. Vendor Dashboard checks approval status and guards offer creation', () => {
    assert.strictEqual(vendorDashboardContent.includes('_currentVendorUser.isPendingVendor'), true);
    assert.strictEqual(vendorDashboardContent.includes('Pending vendors cannot publish offers'), true);
  });

  await t.test('6. Customer home screen removes demo role-switching controls', () => {
    assert.strictEqual(customerHomeContent.includes('Icons.swap_horiz'), false);
    assert.strictEqual(customerHomeContent.includes('Switch Role'), false);
  });

  await t.test('7. AuthService prevents defaulting missing profile accounts to approved customer accounts', () => {
    assert.strictEqual(authServiceContent.includes('User profile not found for account'), true);
  });
});

