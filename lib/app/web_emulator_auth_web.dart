import 'dart:js_interop';

import 'package:firebase_core/firebase_core.dart';

@JS('sandhaiPrepareEmulatorAuth')
external JSPromise<JSAny?> _prepare(JSObject options, JSString host);

@JS('sandhaiClearRememberedAuthEmulator')
external void clearRememberedWebEmulator();

/// Connect Auth before FlutterFire waits for its first restored web session.
Future<void> prepareWebEmulatorAuth(
  FirebaseOptions options,
  String host,
) async {
  await _prepare(
    {
          'apiKey': options.apiKey,
          'appId': options.appId,
          'messagingSenderId': options.messagingSenderId,
          'projectId': options.projectId,
          'authDomain': options.authDomain,
          'storageBucket': options.storageBucket,
        }.jsify()
        as JSObject,
    host.toJS,
  ).toDart;
}
