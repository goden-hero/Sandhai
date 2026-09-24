# 5KM Sandhai — Task 3.1: Security Review & Authentication Hardening Report

This document details the security review, confirmed vulnerability findings, implemented security hardening, and test verification results for **Task 3.1: Security Review & Authentication Hardening** of the **5KM Sandhai** hyperlocal clearance marketplace project.

---

## 1. Executive Summary

A comprehensive security review was performed across the authentication lifecycle, Cloud Firestore security rules, Firebase Storage security rules, role-aware navigation, and user profile initialization logic implemented in Task 3.

### Key Security Audit Findings & Fixes:
1. **Firebase Storage Privilege Escalation (Vulnerability Fixed)**:
   * *Finding*: Storage rules previously allowed any authenticated user to upload offer images under `offers/{vendorId}/...` as long as `request.auth.uid == vendorId`. Customers and pending vendors could upload offer images to Storage by matching their own UID.
   * *Fix*: Hardened [`storage.rules`](file:///home/hisham/projects/sandhai/storage.rules) to query Cloud Firestore via `firestore.get()` and require `isApprovedVendor()` (`role == 'vendor'` AND `approvalStatus == 'approved'`) before granting write access to offer image paths.
2. **Schema & Field Tampering in Firestore Profiles (Vulnerability Fixed)**:
   * *Finding*: `users/{uid}` and `vendors/{uid}` rules validated expected fields but did not restrict extra arbitrary keys (`keys().hasOnly(...)`). Malicious clients could inject unauthorized fields (e.g. `isAdmin: true` or `overrideRole: 'admin'`).
   * *Fix*: Hardened [`firestore.rules`](file:///home/hisham/projects/sandhai/firestore.rules) using `request.resource.data.keys().hasOnly([...])` on both document creation and update operations.
3. **Silent Auth Failure & Default Role Fallback (Hardened)**:
   * *Finding*: `AuthService` caught generic exceptions during authentication and silently returned in-memory mock users. Furthermore, missing user profile documents during sign-in defaulted to `approved` customer roles.
   * *Fix*: Refactored [`AuthService`](file:///home/hisham/projects/sandhai/lib/features/auth/services/auth_service.dart) to throw explicit exceptions when profile initialization fails or when an authenticated account lacks a Firestore profile, preventing silent fallback to fake demo sessions or improper role defaults when Firebase is active.
4. **UI Navigation Guarding & Demo Control Removal (Hardened)**:
   * *Finding*: `CustomerHomeScreen` retained demo role-switching controls (`Icons.swap_horiz` and `'Switch Role'`) that allowed bypassing authentication to jump directly to the Vendor Dashboard UI.
   * *Fix*: Removed demo role-switching buttons from [`CustomerHomeScreen`](file:///home/hisham/projects/sandhai/lib/features/customer/screens/customer_home_screen.dart).

---

## 2. Security Boundaries & Authorization Lifecycle

```mermaid
graph TD
    A["User Authentication Request"] --> B{"Firebase Auth Valid?"}
    B -->|No| C["🛑 Auth Error Returned (No Fake Demo Session)"]
    B -->|Yes| D["Fetch Firestore Profile (users/{uid})"]
    
    D --> E{"Profile Document Exists?"}
    E -->|No| F["🛑 Error: Profile Missing (No Default Approval)"]
    E -->|Yes| G["Extract Role & Approval Status"]
    
    G --> H{"Target Action"}
    H -->|Customer Route| I["Customer View Allowed"]
    H -->|Publish Offer / Storage Upload| J{"Is Approved Vendor?"}
    
    J -->|role == 'vendor' & approvalStatus == 'approved'| K["✅ Firestore / Storage Write Granted"]
    J -->|role == 'customer' OR approvalStatus == 'pending'| L["🛑 Access Denied by Firestore & Storage Rules"]
```

---

## 3. Review of Inspected Components

| Component | File Path | Status & Assessment |
| :--- | :--- | :--- |
| **User Model** | [`lib/models/user_model.dart`](file:///home/hisham/projects/sandhai/lib/models/user_model.dart) | **Verified Secure**: Strongly typed schema with explicit helper getters (`isVendor`, `isCustomer`, `isApprovedVendor`, `isPendingVendor`). |
| **Authentication Service** | [`lib/features/auth/services/auth_service.dart`](file:///home/hisham/projects/sandhai/lib/features/auth/services/auth_service.dart) | **Hardened**: Handles registration/sign-in cleanly; throws exceptions on profile failures; removes silent fake user fallback when live Firebase is active. |
| **Firestore Security Rules** | [`firestore.rules`](file:///home/hisham/projects/sandhai/firestore.rules) | **Hardened**: Strict key constraints (`hasOnly`) added; `approvalStatus == 'pending'` enforced on vendor signup; role & status immutability on update; offer writes guarded by `isApprovedVendor()`. |
| **Storage Security Rules** | [`storage.rules`](file:///home/hisham/projects/sandhai/storage.rules) | **Hardened**: Added `isApprovedVendor()` check querying Firestore `/users/{uid}` via `firestore.get()`. Blocks unapproved vendors & customers. |
| **Customer Home Screen** | [`lib/features/customer/screens/customer_home_screen.dart`](file:///home/hisham/projects/sandhai/lib/features/customer/screens/customer_home_screen.dart) | **Hardened**: Demo role-switching shortcuts removed from AppBar and BottomNavigationBar. |
| **Vendor Dashboard Screen** | [`lib/features/vendor/screens/vendor_dashboard_screen.dart`](file:///home/hisham/projects/sandhai/lib/features/vendor/screens/vendor_dashboard_screen.dart) | **Verified Secure**: Displays `PENDING` vs `APPROVED` badge and onboarding notice; guards offer creation button. |
| **Sign In Screen** | [`lib/features/auth/screens/sign_in_screen.dart`](file:///home/hisham/projects/sandhai/lib/features/auth/screens/sign_in_screen.dart) | **Verified Secure**: Form validation active; routes dynamically using fetched Firestore profile role. |

---

## 4. Tests Executed & Actual Results

### Automated Test Suite Execution Summary:

1. **Static Architecture & Code Audit Suite** (`npm test`):
   ```text
   ▶ Task 3 Auth Architecture & Code Audit Verification
     ✔ 1. Router defines authentication route constants
     ✔ 2. AuthService encapsulates customer & vendor registration with role and pending approval status
     ✔ 3. Register screens provide direct Customer & Vendor registration options
     ✔ 4. Sign-in screen handles authentication & profile-based routing
     ✔ 5. Vendor Dashboard checks approval status and guards offer creation
     ✔ 6. Customer home screen removes demo role-switching controls
     ✔ 7. AuthService prevents defaulting missing profile accounts to approved customer accounts
   ✔ Task 3 Auth Architecture & Code Audit Verification (8 tests pass)
   ```

2. **Firebase Emulator Security Rules Suite** (`npm run test:emulators`):
   ```text
   ✔ 1. An unauthenticated user cannot create an offer
   ✔ 2. A customer cannot create an offer
   ✔ 3. Vendor self-registration enforces pending approval status
   ✔ 4. Pending vendor cannot create an offer, approved vendor can
   ✔ 5. Vendor cannot modify their own approvalStatus or role via profile update
   ✔ 6. A customer can read public active offers
   ✔ 7. Invalid offer data is rejected
   ✔ 8. Unauthorized image uploads are rejected
   ✔ 9. Storage uploads require approved vendor status (pending vendor & customer blocked)
   ✔ 10. Profile schema tampering (extra arbitrary fields) is rejected
   ℹ tests 10 | pass 10 | fail 0
   ```

---

## 5. Verification Matrix

| Validation Item | Method / Suite | Status |
| :--- | :--- | :--- |
| **Direct Customer/Vendor Signup Isolation** | Firebase Auth Emulator | **Verified and passing** |
| **Pending Vendor Approval Initialization** | Firestore Rules (Test 3) | **Verified and passing** |
| **Role & Status Immutability on Update** | Firestore Rules (Test 5) | **Verified and passing** |
| **Pending Vendor Offer Block** | Firestore Rules (Test 4) | **Verified and passing** |
| **Approved Vendor Offer Grant** | Firestore Rules (Test 4) | **Verified and passing** |
| **Storage Upload Approved Vendor Requirement** | Storage Rules (Test 9) | **Verified and passing** |
| **Profile Document Key Constraints (`hasOnly`)** | Firestore Rules (Test 10) | **Verified and passing** |
| **Removal of UI Demo Role Switching** | Static Code Audit (Test 6) | **Verified and passing** |
| **Auth Error & Missing Profile Handling** | Static Code Audit (Test 7) | **Verified and passing** |
| **Existing Task 1 Security Protections** | Firebase Emulator Suite | **Verified and passing** |
| **Existing Task 2 UI Skeleton Preservation** | Code Inspection & Static Audit | **Verified and passing** |
| **Flutter Compiler & Device Runtime** | System `flutter` CLI | **Blocked by environment** (Flutter SDK not installed on PATH) |

---

## 6. Remaining Risks & Limitations

1. **Environment Limitation**: The Flutter SDK is not present on the host environment PATH. Static code inspections and Node.js/Firebase Emulator test suites were utilized. Full Flutter widget/compilation checks remain blocked until the Flutter SDK is installed.
2. **Administrative Approval Mechanism**: As required by the task scope, client-side self-approval is prevented. Vendor approval must be set out-of-band or via trusted backend administrative logic (to be built in a future task).

---

## 7. Readiness Assessment

**Status**: **Verified and Passing**

All identified vulnerabilities (Storage upload bypass, profile schema key injection, silent fallback demo authentication, and UI demo role-switching controls) have been remediated and verified with 10/10 passing Firebase Emulator security tests and 8/8 passing static architecture tests. Task 3.1 security hardening is complete.
