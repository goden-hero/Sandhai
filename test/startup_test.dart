import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandhai/app/app.dart';
import 'package:sandhai/app/bootstrap.dart';
import 'package:sandhai/app/config.dart';
import 'package:sandhai/features/auth/services/auth_service.dart';
import 'package:sandhai/features/customer/screens/customer_home_screen.dart';
import 'package:sandhai/features/onboarding/screens/welcome_screen.dart';
import 'package:sandhai/main.dart' as entry;

void main() {
  setUp(() {
    AppConfig.current = const AppConfig(mode: AppMode.demo);
    AuthService.instance.setDemoUser(null);
  });

  tearDown(() {
    AppConfig.current = const AppConfig(mode: AppMode.demo);
    AuthService.instance.setDemoUser(null);
  });

  testWidgets(
    'real entry point launches demo and registration without Firebase',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      expect(Firebase.apps, isEmpty);
      await entry.main();
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.textContaining('Demo mode'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text("I'm here to shop"));
      await tester.pumpAndSettle();
      expect(find.text('Customer Registration'), findsOneWidget);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Demo Shopper');
      await tester.enterText(fields.at(1), 'shopper@example.com');
      await tester.enterText(fields.at(2), 'demo-password');
      await tester.enterText(fields.at(3), 'demo-password');
      final register = find.widgetWithText(
        ElevatedButton,
        'Create Customer Account',
      );
      await tester.ensureVisible(register);
      await tester.tap(register);
      await tester.pumpAndSettle();

      expect(find.byType(CustomerHomeScreen), findsOneWidget);
      expect(AuthService.instance.demoCurrentUser?.displayName, 'Demo Shopper');
      expect(Firebase.apps, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('demo skips Firebase even if initialization would fail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var initialized = false;
    final app = await createApplication(
      config: const AppConfig(mode: AppMode.demo),
      initializeFirebase: (_) async {
        initialized = true;
        throw StateError('Firebase must not be used in demo');
      },
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(initialized, isFalse);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(Firebase.apps, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [AppMode.emulator, AppMode.production]) {
    testWidgets(
      '$mode initialization failure is visible and never opens demo',
      (tester) async {
        final app = await createApplication(
          config: AppConfig(mode: mode),
          initializeFirebase: (_) async =>
              throw StateError('Backend unavailable'),
        );
        await tester.pumpWidget(app);
        await tester.pumpAndSettle();

        expect(find.byType(StartupFailureApp), findsOneWidget);
        expect(find.text('Selected mode: ${mode.name}'), findsOneWidget);
        expect(find.textContaining('Backend unavailable'), findsOneWidget);
        expect(find.byType(SandhaiApp), findsNothing);
        expect(find.byType(WelcomeScreen), findsNothing);
        expect(AppConfig.current.mode, mode);
        expect(Firebase.apps, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('production rejects placeholder options before Firebase starts', (
    tester,
  ) async {
    final app = await createApplication(
      config: const AppConfig(mode: AppMode.production),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.byType(StartupFailureApp), findsOneWidget);
    expect(
      find.textContaining('Production Firebase configuration'),
      findsOneWidget,
    );
    expect(Firebase.apps, isEmpty);
  });
}
