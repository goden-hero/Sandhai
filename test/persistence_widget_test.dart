import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandhai/app/app.dart';
import 'package:sandhai/app/config.dart';
import 'package:sandhai/app/router.dart';
import 'package:sandhai/features/customer/widgets/offer_card.dart';
import 'package:sandhai/features/auth/services/auth_service.dart';
import 'package:sandhai/features/vendor/services/offer_service.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'Firebase-mode customer screens contain no sample offers or settings',
    (tester) async {
      AppConfig.current = const AppConfig(mode: AppMode.emulator);
      addTearDown(
        () => AppConfig.current = const AppConfig(mode: AppMode.demo),
      );
      final accounts = TestAccounts();
      final auth = AuthService(repository: accounts);
      AuthService.install(auth);
      await auth.registerCustomer(
        email: 'customer@test.com',
        password: 'password',
        displayName: 'Real customer',
      );
      await tester.pumpWidget(const SandhaiApp(isFirebaseConnected: true));
      await tester.pumpAndSettle();
      expect(find.byType(OfferCard), findsNothing);
      expect(find.text('Simulate Empty:'), findsNothing);
      expect(
        find.text('Nearby discovery is not connected yet'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Profile & Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Real customer'), findsOneWidget);
      expect(find.textContaining('Mock 5 KM'), findsNothing);
      expect(find.text('Push Notifications'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'pending/failed profile saves retain input and do not show success',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = TestAccounts();
      final auth = AuthService(repository: repo);
      AuthService.install(auth);
      await auth.registerVendor(
        email: 'vendor@test.com',
        password: 'password',
        storeName: 'Original',
        phone: '9876543210',
        category: 'Groceries',
      );
      await tester.pumpWidget(const SandhaiApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Business profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Retained store name',
      );
      repo.updateGate = Completer<void>();
      repo.failUpdate = true;
      await tester.tap(find.text('Save profile'));
      await tester.pump();
      expect(
        find.text('Saving… waiting for server confirmation'),
        findsOneWidget,
      );
      expect(find.text('Vendor profile saved.'), findsNothing);
      repo.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Server rejected profile'),
        ),
        findsOneWidget,
      );
      expect(find.text('Retained store name'), findsOneWidget);
      expect(find.text('Vendor profile saved.'), findsNothing);
      repo.failUpdate = false;
      repo.updateGate = null;
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(find.text('Vendor profile saved.'), findsOneWidget);
      expect(repo.vendors[auth.identity!.uid]!.name, 'Retained store name');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'offer failure retains values and approval changes disable an open form',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = TestAccounts();
      final auth = AuthService(repository: repo);
      AuthService.install(auth);
      final user = await auth.registerVendor(
        email: 'vendor@test.com',
        password: 'password',
        storeName: 'Store',
        phone: '9876543210',
        category: 'Groceries',
      );
      repo.approval(user.uid, 'approved');
      await tester.pump();
      final offers = TestOffers()..failSave = true;
      OfferService.install(OfferService(auth: auth, repository: offers));
      await tester.pumpWidget(const SandhaiApp());
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.pushNamed(context, AppRoutes.createOffer);
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Retained offer');
      await tester.enterText(fields.at(1), 'Details');
      await tester.enterText(fields.at(2), '100');
      await tester.enterText(fields.at(3), '50');
      final button = find.widgetWithText(
        ElevatedButton,
        'Publish Clearance Offer',
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Write denied'),
        ),
        findsOneWidget,
      );
      expect(find.text('Retained offer'), findsOneWidget);
      expect(find.textContaining('published successfully'), findsNothing);
      repo.approval(user.uid, 'suspended');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ElevatedButton>(find.byType(ElevatedButton).last)
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'logout and account switching dispose the previous dashboard stream',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accounts = TestAccounts();
      final auth = AuthService(repository: accounts);
      AuthService.install(auth);
      final a = await auth.registerVendor(
        email: 'a@test.com',
        password: 'password',
        storeName: 'Store A',
        phone: '9876543210',
        category: 'Groceries',
      );
      accounts.approval(a.uid, 'approved');
      await tester.pump();
      final offers = TestOffers();
      final service = OfferService(auth: auth, repository: offers);
      OfferService.install(service);
      await service.createOffer(
        offerId: 'a',
        title: 'Private A offer',
        description: 'A',
        oldPrice: 100,
        newPrice: 50,
        category: 'Groceries',
        durationHours: 6,
      );
      await tester.pumpWidget(const SandhaiApp());
      await tester.pumpAndSettle();
      expect(find.text('Private A offer'), findsOneWidget);
      expect(offers.activeWatches, 1);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Private A offer'), findsNothing);
      expect(offers.activeWatches, 0);
      await auth.registerVendor(
        email: 'b@test.com',
        password: 'password',
        storeName: 'Store B',
        phone: '9876543210',
        category: 'Groceries',
      );
      await tester.pumpAndSettle();
      expect(find.text('Store B'), findsOneWidget);
      expect(find.text('Private A offer'), findsNothing);
      expect(offers.activeWatches, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(offers.activeWatches, 0);
    },
  );
  testWidgets(
    'registration failure is visible at the bottom of a phone form and retry reuses Auth',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accounts = TestAccounts()..failCompletion = true;
      final auth = AuthService(repository: accounts);
      AuthService.install(auth);
      await tester.pumpWidget(const SandhaiApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('I want to sell excess stock'));
      await tester.pumpAndSettle();
      final values = [
        'Retained phone store',
        '9876543210',
        'Store address',
        'Store details',
        'vendor@test.com',
        'password',
        'password',
      ];
      for (var i = 0; i < values.length; i++) {
        await tester.enterText(find.byType(TextFormField).at(i), values[i]);
      }
      final submit = find.widgetWithText(
        ElevatedButton,
        'Submit Vendor Registration',
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      final feedback = find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('Injected profile failure'),
      );
      expect(feedback, findsOneWidget);
      expect(
        tester.getRect(feedback).overlaps(const Rect.fromLTWH(0, 0, 420, 900)),
        isTrue,
      );
      expect(find.text('Retained phone store'), findsOneWidget);
      expect(accounts.creations, 1);
      expect(accounts.users, isEmpty);
      accounts.failCompletion = false;
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('APPROVAL PENDING'), findsOneWidget);
      expect(auth.profile!.displayName, 'Retained phone store');
      expect(accounts.creations, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
