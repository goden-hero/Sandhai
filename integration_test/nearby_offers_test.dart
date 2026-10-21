// Emulator-only native Firestore query integration; fixture writes are trusted
// test setup, never application behavior. No collection/account resets.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sandhai/app/bootstrap.dart';
import 'package:sandhai/app/config.dart';
import 'package:sandhai/core/location/store_location.dart';
import 'package:sandhai/data/nearby_offer_repository.dart';
import 'package:sandhai/data/nearby_query_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native bounded queries: exact radius, live changes, expiry and fresh re-subscription',
    (tester) async {
      final config = AppConfig.fromEnvironment();
      expect(config.mode, AppMode.emulator);
      await tester.pumpWidget(await createApplication(config: config));
      await tester.runAsync(() async {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final prefix = 'native-nearby-$stamp';
        final client = HttpClient()..findProxy = (_) => 'DIRECT';
        Future<void> fixture(String id, Map<String, dynamic> data) async {
          Object encode(Object? value) {
            if (value is String) return {'stringValue': value};
            if (value is num) return {'doubleValue': value};
            if (value is DateTime) {
              return {'timestampValue': value.toUtc().toIso8601String()};
            }
            throw StateError('Unsupported fixture field');
          }

          final req = await client.patchUrl(
            Uri.parse(
              'http://${config.emulatorHost}:8080/v1/projects/${config.emulatorProjectId}/databases/(default)/documents/offers/$prefix-$id',
            ),
          );
          req.headers.set('Authorization', 'Bearer owner');
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({'fields': data.map((k, v) => MapEntry(k, encode(v)))}),
          );
          final r = await req.close();
          expect(r.statusCode, 200, reason: await utf8.decoder.bind(r).join());
        }

        final now = DateTime.now();
        Map<String, dynamic> value(
          double lat, {
          DateTime? expiry,
          String status = 'active',
        }) => {
          'vendorId': prefix,
          'title': prefix,
          'description': 'Native query fixture',
          'category': 'groceries',
          'oldPrice': 100,
          'newPrice': 50,
          'imageUrl': '',
          'latitude': lat,
          'longitude': 0.0,
          'geohash': StoreLocation(lat, 0).geohash,
          'createdAt': now.subtract(const Duration(minutes: 1)),
          'locationConfirmedAt': now.subtract(const Duration(minutes: 2)),
          'expiryTime': expiry ?? now.add(const Duration(hours: 1)),
          'status': status,
        };
        NearbySearch? search;
        StreamSubscription<List<NearbyOffer>>? sub;
        try {
          await fixture('4990', value(.044876148135344655));
          await fixture('5000', value(.044966080295936524));
          await fixture('5010', value(.045056012456528396));
          final repo = NearbyOfferRepository(
            source: FirebaseNearbyQuerySource(),
          );
          List<NearbyOffer>? found;
          Object? error;
          Completer<Object>? networkFailure;
          void attach() {
            search = repo.search(StoreLocation(0, 0));
            sub = search!.stream.listen(
              (v) => found = v,
              onError: (Object e) {
                error = e;
                if (networkFailure?.isCompleted == false) {
                  networkFailure!.complete(e);
                }
              },
            );
          }

          Future<void> until(bool Function() predicate) async {
            for (var n = 0; n < 150 && !predicate() && error == null; n++) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(error, isNull);
            expect(predicate(), isTrue);
          }

          Set<String> ids() =>
              found
                  ?.map((v) => v.offer.id)
                  .where((id) => id.startsWith(prefix))
                  .toSet() ??
              {};
          attach();
          await until(() => ids().length == 2);
          expect(ids(), {'$prefix-4990', '$prefix-5000'});
          await fixture('4990', value(.1));
          await until(() => !ids().contains('$prefix-4990'));
          await fixture('5000', value(.044966080295936524, status: 'draft'));
          await until(() => ids().isEmpty);
          await fixture(
            'short',
            value(.001, expiry: DateTime.now().add(const Duration(seconds: 3))),
          );
          await until(() => ids().contains('$prefix-short'));
          // No write/event after this point: the local expiry timer removes it.
          await until(() => ids().isEmpty);
          final doc = await FirebaseFirestore.instance
              .doc('offers/$prefix-short')
              .get(const GetOptions(source: Source.server));
          expect(doc.data()!['status'], 'active');
          expect(
            (doc.data()!['expiryTime'] as Timestamp).toDate().isBefore(
              DateTime.now(),
            ),
            isTrue,
          );
          await sub!.cancel();
          found = null;
          error = null;
          // Re-subscribe against an already warm SDK cache; server confirmation
          // must still produce a complete snapshot rather than metadata-only empty.
          await fixture('fresh', value(.002));
          attach();
          await until(() => ids().contains('$prefix-fresh'));
          // SDK metadata, rather than a fabricated source exception, must expose
          // loss of server confirmation. Retry after reconnect uses fresh bounds.
          networkFailure = Completer<Object>();
          await FirebaseFirestore.instance.disableNetwork();
          final offline = await networkFailure.future.timeout(
            const Duration(seconds: 15),
          );
          expect(offline.toString(), contains('connection'));
          await sub!.cancel();
          await FirebaseFirestore.instance.enableNetwork();
          found = null;
          error = null;
          networkFailure = null;
          attach();
          await until(() => ids().contains('$prefix-fresh'));
          final delete = await client.deleteUrl(
            Uri.parse(
              'http://${config.emulatorHost}:8080/v1/projects/${config.emulatorProjectId}/databases/(default)/documents/offers/$prefix-fresh',
            ),
          );
          delete.headers.set('Authorization', 'Bearer owner');
          final deleted = await delete.close();
          expect(deleted.statusCode, 200);
          await deleted.drain<void>();
          await until(() => !ids().contains('$prefix-fresh'));
        } finally {
          await FirebaseFirestore.instance.enableNetwork();
          await sub?.cancel();
          await search?.dispose();
          client.close();
        }
      });
    },
  );
}
