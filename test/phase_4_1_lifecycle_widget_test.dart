import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandhai/app/config.dart';
import 'package:sandhai/app/router.dart';
import 'package:sandhai/core/errors/app_failure.dart';
import 'package:sandhai/core/location/store_location.dart';
import 'package:sandhai/data/nearby_offer_repository.dart';
import 'package:sandhai/data/nearby_query_source.dart';
import 'package:sandhai/features/auth/services/auth_service.dart';
import 'package:sandhai/features/customer/nearby_feed_controller.dart';
import 'package:sandhai/features/customer/screens/customer_home_screen.dart';

import 'phase_4_1_lifecycle_test.dart'
    show
        LifecycleClock,
        LifecycleLocation,
        LifecycleSource,
        lifecycleAuth,
        lifecycleEpoch,
        lifecycleOffer;

class _TrackedController extends NearbyFeedController {
  _TrackedController({
    required super.auth,
    required super.repository,
    required super.location,
  });
  int listeners = 0, rechecks = 0;
  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }

  @override
  void recheckExpiry() {
    rechecks++;
    super.recheckExpiry();
  }
}

class _ProfileObserver extends NavigatorObserver {
  int pushes = 0, pops = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == AppRoutes.profile) pushes++;
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == AppRoutes.profile) pops++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  late AuthService auth;
  late LifecycleSource source;
  late LifecycleClock clock;
  late _TrackedController controller;
  late _ProfileObserver profileObserver;
  setUp(() async {
    AppConfig.current = const AppConfig(mode: AppMode.emulator);
    auth = await lifecycleAuth();
    source = LifecycleSource();
    clock = LifecycleClock();
    controller = _TrackedController(
      auth: auth,
      repository: NearbyOfferRepository(source: source, clock: clock),
      location: LifecycleLocation(),
    );
    profileObserver = _ProfileObserver();
  });
  tearDown(() {
    controller.dispose();
    auth.dispose();
    AppConfig.current = const AppConfig(mode: AppMode.demo);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerHomeScreen(nearbyController: controller),
        navigatorObservers: [profileObserver],
        routes: {
          AppRoutes.profile: (context) => Scaffold(
            appBar: AppBar(title: const Text('Profile destination')),
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Return to nearby feed'),
              ),
            ),
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> beginSearch(WidgetTester tester) async {
    await tester.tap(find.text('Use my location'));
    await tester.pump();
    await tester.pump();
    expect(
      source.active,
      greaterThan(0),
      reason:
          'phase=${controller.phase}, error=${controller.error}, '
          'location requests=${(controller.location as LifecycleLocation).requests.length}',
    );
  }

  testWidgets(
    'profile waits for cancellation, hidden feed has no timers, and return opens one search',
    (tester) async {
      await open(tester);
      await beginSearch(tester);
      source.seed([
        lifecycleOffer(
          'Expires while on profile',
          lifetime: const Duration(seconds: 3),
        ),
      ]);
      await tester.pumpAndSettle();
      final boundCount = source.probes.length;
      final oldProbe = source.probes.first;
      final gate = Completer<void>();
      for (final probe in source.probes) {
        probe.cancellationGate = gate;
      }
      expect(clock.activeTimers, 1);
      await tester.tap(find.byTooltip('Profile & Settings'));
      await tester.pump();
      expect(find.text('Profile destination'), findsNothing);
      expect(
        source.probes.every((probe) => probe.cancellationRequested),
        isTrue,
      );
      expect(clock.activeTimers, 0);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Profile destination'), findsOneWidget);
      expect(source.active, 0);
      expect(source.probes.length, boundCount);
      expect(clock.activeTimers, 0);
      oldProbe.staleData!(
        NearbyChanges([lifecycleOffer('Hidden late result')], const []),
      );
      oldProbe.deliverLateError(const AppFailure('Hidden late failure'));
      clock.value = lifecycleEpoch.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 4));
      expect(source.active, 0);
      expect(clock.activeTimers, 0);
      await tester.tap(find.text('Return to nearby feed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(source.probes.length, boundCount * 2);
      expect(source.active, boundCount);
      expect(find.text('Loading nearby offers…'), findsOneWidget);
      source.seed([
        lifecycleOffer(
          'Expires while on profile',
          lifetime: const Duration(seconds: 3),
        ),
        lifecycleOffer('Fresh after return'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Expires while on profile'), findsNothing);
      expect(find.text('Hidden late result'), findsNothing);
      expect(find.text('Fresh after return'), findsOneWidget);
      expect(controller.listeners, 1);
      expect(source.maxActive, boundCount);
      // A second navigation catches accumulated subscriptions on repeated returns.
      await tester.tap(find.byTooltip('Profile & Settings'));
      await tester.pumpAndSettle();
      expect(source.active, 0);
      expect(clock.activeTimers, 0);
      await tester.tap(find.text('Return to nearby feed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(source.probes.length, boundCount * 3);
      source.seed([]);
      await tester.pumpAndSettle();
      expect(source.active, boundCount);
      expect(controller.listeners, 1);
      await controller.pause();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.listeners, 0);
    },
  );

  testWidgets(
    'cache-only disconnect has a visible retry state and reconnect requires fresh confirmation',
    (tester) async {
      await open(tester);
      await beginSearch(tester);
      for (final probe in source.probes) {
        probe.add(const NearbyChanges([], [], confirmed: false));
      }
      await tester.pump();
      expect(find.text('Loading nearby offers…'), findsOneWidget);
      expect(find.text('No clearance offers found'), findsNothing);
      source.seed([lifecycleOffer('Before network interruption')]);
      await tester.pumpAndSettle();
      expect(find.text('Before network interruption'), findsOneWidget);
      source.probes.first.add(const NearbyChanges([], [], confirmed: false));
      clock.value = lifecycleEpoch.add(const Duration(milliseconds: 4999));
      await tester.pump(const Duration(milliseconds: 4999));
      expect(find.text('Before network interruption'), findsOneWidget);
      expect(find.text('Could not load nearby offers'), findsNothing);
      clock.value = lifecycleEpoch.add(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Could not load nearby offers'), findsOneWidget);
      expect(find.text('Retry nearby offers'), findsOneWidget);
      expect(find.text('No clearance offers found'), findsNothing);
      expect(find.text('Before network interruption'), findsNothing);
      expect(source.active, 0);
      expect(clock.activeTimers, 0);
      final previous = source.probes.length;
      await tester.tap(find.text('Retry nearby offers'));
      await tester.pump();
      await tester.pump();
      expect(source.probes.length, greaterThan(previous));
      expect(find.text('Loading nearby offers…'), findsOneWidget);
      source.seed([]);
      await tester.pumpAndSettle();
      expect(find.text('No clearance offers found'), findsOneWidget);
      expect(find.text('Could not load nearby offers'), findsNothing);
      await controller.pause();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'profile during pending location returns to an actionable location prompt',
    (tester) async {
      final location = controller.location as LifecycleLocation;
      location.automatic = false;
      await open(tester);
      await tester.tap(find.text('Use my location'));
      await tester.pump();
      expect(find.text('Finding your location…'), findsOneWidget);
      expect(location.requests, hasLength(1));
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Profile destination'), findsOneWidget);
      location.requests.single.complete(StoreLocation(1, 1));
      await tester.pump();
      expect(source.watchCalls, 0);
      await tester.tap(find.text('Return to nearby feed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Finding your location…'), findsNothing);
      expect(find.text('Find offers near you'), findsOneWidget);
      expect(find.text('Use my location'), findsOneWidget);
      expect(controller.center, isNull);
      expect(source.active, 0);
      location.automatic = true;
      await beginSearch(tester);
      source.seed([]);
      await tester.pumpAndSettle();
      expect(find.text('No clearance offers found'), findsOneWidget);
      await controller.pause();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'transient cache transition removes expired rows without a false connection error',
    (tester) async {
      await open(tester);
      await beginSearch(tester);
      source.seed([
        lifecycleOffer(
          'Expires during reconfirmation',
          lifetime: const Duration(seconds: 2),
        ),
        lifecycleOffer('Available after reconfirmation'),
      ]);
      await tester.pumpAndSettle();
      source.probes.first.add(const NearbyChanges([], [], confirmed: false));
      clock.value = lifecycleEpoch.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Expires during reconfirmation'), findsNothing);
      expect(find.text('Available after reconfirmation'), findsOneWidget);
      expect(find.text('Could not load nearby offers'), findsNothing);
      source.probes.first.add(const NearbyChanges([], []));
      clock.value = lifecycleEpoch.add(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Available after reconfirmation'), findsOneWidget);
      expect(find.text('Could not load nearby offers'), findsNothing);
      expect(controller.phase, NearbyPhase.ready);
      expect(clock.activeTimers, 1);
      await controller.pause();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'double profile tap while teardown waits pushes one route and resumes once',
    (tester) async {
      await open(tester);
      await beginSearch(tester);
      source.seed([lifecycleOffer('Before repeated tap')]);
      await tester.pumpAndSettle();
      final boundCount = source.probes.length;
      final gate = Completer<void>();
      for (final probe in source.probes) {
        probe.cancellationGate = gate;
      }
      await tester.tap(find.byTooltip('Profile & Settings'));
      await tester.tap(find.byTooltip('Profile & Settings'));
      await tester.pump();
      expect(profileObserver.pushes, 0);
      expect(clock.activeTimers, 0);
      gate.complete();
      await tester.pumpAndSettle();
      expect(profileObserver.pushes, 1);
      expect(source.active, 0);
      await tester.tap(find.text('Return to nearby feed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(profileObserver.pops, 1);
      expect(source.probes.length, boundCount * 2);
      source.seed([]);
      await tester.pumpAndSettle();
      expect(find.text('Profile destination'), findsNothing);
      expect(find.text('No clearance offers found'), findsOneWidget);
      expect(source.active, boundCount);
      expect(source.maxActive, boundCount);
      await controller.pause();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unmount detaches injected listener and resume observer before a fresh mount',
    (tester) async {
      await open(tester);
      expect(controller.listeners, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.listeners, 0);
      final rechecks = controller.rechecks;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.rechecks, rechecks);
      await open(tester);
      expect(controller.listeners, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.rechecks, rechecks + 1);
      expect(source.active, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.listeners, 0);
    },
  );
}
