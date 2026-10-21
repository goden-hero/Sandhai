import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandhai/app/config.dart';
import 'package:sandhai/models/offer_model.dart';
import 'package:sandhai/core/errors/app_failure.dart';
import 'package:sandhai/core/widgets/offer_photo.dart';
import 'package:sandhai/data/nearby_offer_repository.dart';
import 'package:sandhai/features/auth/services/auth_service.dart';
import 'package:sandhai/features/customer/nearby_feed_controller.dart';
import 'package:sandhai/features/customer/screens/customer_home_screen.dart';
import 'package:sandhai/features/customer/widgets/offer_card.dart';

import 'nearby_offers_test.dart' show epoch, offer, FixedClock;
import 'support/fakes.dart';
import 'support/nearby_fakes.dart';

void main() {
  late AuthService auth;
  late TestNearbySource source;
  late TestCustomerLocation location;
  late NearbyFeedController controller;
  late FixedClock clock;
  setUp(() async {
    AppConfig.current = const AppConfig(mode: AppMode.emulator);
    auth = AuthService(repository: TestAccounts());
    AuthService.install(auth);
    await auth.registerCustomer(
      email: 'widget-customer@test.com',
      password: 'password',
      displayName: 'Customer',
    );
    await settleSession();
    source = TestNearbySource();
    location = TestCustomerLocation();
    clock = FixedClock(epoch);
    controller = NearbyFeedController(
      auth: auth,
      repository: NearbyOfferRepository(source: source, clock: clock),
      location: location,
    );
  });
  tearDown(() {
    controller.dispose();
    AppConfig.current = const AppConfig(mode: AppMode.demo);
  });
  tearDownAll(() => auth.dispose());
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CustomerHomeScreen(nearbyController: controller)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'permission, loading, query error, retry and empty remain distinct',
    (tester) async {
      await open(tester);
      expect(find.text('Find offers near you'), findsOneWidget);
      location.failure = const AppFailure('Location permission was denied.');
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(find.text('Location unavailable'), findsOneWidget);
      expect(find.text('No clearance offers found'), findsNothing);
      location.failure = null;
      await tester.tap(find.text('Use my location'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Loading nearby offers…'), findsOneWidget);
      source.probes.first.stream.addError(
        const AppFailure('permission-denied'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load nearby offers'), findsOneWidget);
      expect(find.text('No clearance offers found'), findsNothing);
      await tester.tap(find.text('Retry nearby offers'));
      // This fake cancels synchronously, so Dart returns its root-zone completed
      // future. Its completion callback needs the real event loop; pumping only
      // fake microtasks cannot acknowledge teardown and open replacement bounds.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(source.active, greaterThan(0));
      source.seed([]);
      await tester.pumpAndSettle();
      expect(find.text('No clearance offers found'), findsOneWidget);
      expect(find.byType(OfferCard), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'stored categories, calculated distance, live updates, timer and resume expiry',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester);
      await tester.tap(find.text('Use my location'));
      await tester.pump();
      await tester.pump();
      source.seed([
        offer(
          'Near',
          lat: .001,
          expiry: epoch.add(const Duration(seconds: 5)),
          extra: {'category': 'fresh_produce'},
        ),
        offer('Other', lat: .002),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(OfferCard), findsNWidgets(2));
      expect(find.text('0.11 km'), findsOneWidget);
      expect(find.textContaining('(Mock)'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Fresh Produce'));
      await tester.pumpAndSettle();
      expect(find.byType(OfferCard), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      // No Firestore event is sent between these assertions.
      clock.value = epoch.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Near'), findsNothing);
      expect(find.text('No clearance offers found'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(find.text('Other'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.value = epoch.add(const Duration(hours: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Other'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('a real offer image is rendered by the customer card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfferCard(
            offer: OfferModel.fromMap(
              'Photo',
              offer(
                'Photo',
                extra: {'imageUrl': 'https://example.test/photo.jpg'},
              ).data,
            ),
            distanceMetres: 1234,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OfferPhoto), findsOneWidget);
    expect(find.text('1.23 km'), findsOneWidget);
  });
}
