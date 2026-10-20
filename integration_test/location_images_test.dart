// Emulator-only native integration. Never runs against production.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sandhai/app/bootstrap.dart';
import 'package:sandhai/app/config.dart';
import 'package:sandhai/core/location/store_location.dart';
import 'package:sandhai/features/auth/services/auth_service.dart';
import 'package:sandhai/features/vendor/services/offer_service.dart';

import '../test/support/phase3_fixtures.dart' show testPng;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Firebase registration, confirmed location, photo metadata, and idempotent publication',
    (tester) async {
      final config = AppConfig.fromEnvironment();
      expect(
        config.mode,
        AppMode.emulator,
        reason: 'This test must only use disposable local emulator fixtures.',
      );
      final app = await createApplication(config: config);
      await tester.pumpWidget(app);
      final auth = AuthService.instance;
      await tester.runAsync(() async {
        await auth.signOut();
        final user = await auth.registerVendor(
          email:
              'native-phase3-${DateTime.now().millisecondsSinceEpoch}@example.com',
          password: 'NativePhase3Pass123',
          storeName: 'Native Phase 3 integration',
          phone: '9876543210',
          category: 'groceries',
        );
        expect(auth.vendorProfile!.latitude, isNull);
        await auth.confirmStoreLocation(StoreLocation(11.1, 77.2));
        // Privileged local emulator fixture setup; never part of the application.
        final client = HttpClient()..findProxy = (_) => 'DIRECT';
        try {
          final uri = Uri.parse(
            'http://${config.emulatorHost}:8080/v1/projects/${config.emulatorProjectId}/databases/(default)/documents/users/${user.uid}?updateMask.fieldPaths=approvalStatus',
          );
          final req = await client.patchUrl(uri);
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({
              'fields': {
                'approvalStatus': {'stringValue': 'approved'},
              },
            }),
          );
          final response = await req.close();
          expect(
            response.statusCode,
            200,
            reason: await utf8.decoder.bind(response).join(),
          );
        } finally {
          client.close();
        }
        for (var n = 0; n < 50 && auth.profile?.isApprovedVendor != true; n++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(auth.profile!.isApprovedVendor, isTrue);
        final service = OfferService.instance;
        final id = service.newOfferId();
        Future<dynamic> save() => service.createOffer(
          offerId: id,
          title: 'Native photo persistence',
          description: 'Device integration fixture',
          oldPrice: 100,
          newPrice: 50,
          category: 'fresh_produce',
          durationHours: 6,
          imageBytes: testPng,
        );
        final saved = await save();
        await save();
        final db = FirebaseFirestore.instance;
        final doc = await db
            .doc('offers/$id')
            .get(const GetOptions(source: Source.server));
        expect(doc.data()!['category'], 'fresh_produce');
        expect(doc.data()!['latitude'], 11.1);
        expect(doc.data()!['geohash'], StoreLocation(11.1, 77.2).geohash);
        final metadata = await FirebaseStorage.instance
            .ref(saved.imagePath as String)
            .getMetadata();
        expect(metadata.contentType, 'image/png');
        expect(metadata.size, testPng.length);
        expect(
          (await db
                  .collection('offers')
                  .where('vendorId', isEqualTo: user.uid)
                  .get(const GetOptions(source: Source.server)))
              .size,
          1,
        );
        await expectLater(
          FirebaseStorage.instance.ref(saved.imagePath as String).delete(),
          throwsA(anything),
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('Native photo persistence'), findsOneWidget);
    },
  );
}
