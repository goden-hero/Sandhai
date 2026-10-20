// Called only by APP_MODE=emulator. Demo never imports a Firebase SDK.
// FlutterFire firebase_auth_web 5.15.3 restores Auth inside initializeApp(),
// before Dart can call useAuthEmulator(). Restoring an unsigned emulator token
// against production discards that session. Connect synchronously after creating
// JS Auth, before FlutterFire waits for restoration.
// Keep this SDK version and dependencies aligned with firebase_core_web 2.24.1
// and firebase_auth_web 5.15.3 in pubspec.lock. The browser caches these same
// modules when FlutterFire imports them; no second app or Auth instance is made.
window.sandhaiClearRememberedAuthEmulator = () => {
  window.sessionStorage.removeItem('[DEFAULT]-firebaseEmulatorOrigin');
};
window.sandhaiPrepareEmulatorAuth = async (options, host) => {
  const version = '11.9.1';
  const [core, auth] = await Promise.all([
    import(`https://www.gstatic.com/firebasejs/${version}/firebase-app.js`),
    import(`https://www.gstatic.com/firebasejs/${version}/firebase-auth.js`),
  ]);
  const app = core.initializeApp(options);
  const instance = auth.initializeAuth(app, {
    errorMap: auth.debugErrorMap,
    persistence: [auth.indexedDBLocalPersistence, auth.browserLocalPersistence,
      auth.browserSessionPersistence],
    popupRedirectResolver: auth.browserPopupRedirectResolver,
  });
  auth.connectAuthEmulator(instance, `http://${host}:9099`);
};
