import 'dart:convert';

import 'package:sandhai/core/widgets/offer_photo.dart';
import 'package:sandhai/core/images/offer_draft_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandhai/app/app.dart';
import 'package:sandhai/core/images/image_selection_service.dart';
import 'package:sandhai/core/images/selected_image.dart';
import 'package:sandhai/core/location/store_location.dart';
import 'package:sandhai/core/location/store_location_editor.dart';
import 'package:sandhai/features/auth/services/auth_service.dart';
import 'package:sandhai/features/vendor/screens/create_offer_screen.dart';
import 'package:sandhai/features/vendor/services/offer_service.dart';

import 'support/fakes.dart';
import 'support/phase3_fixtures.dart';

void main() {
  testWidgets('demo data-URI photos render bytes without HTTP or Firebase', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OfferPhoto(url: 'data:image/png;base64,${base64Encode(testPng)}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    expect(tester.takeException(), isNull);
  });
  late TestAccounts accounts;
  late AuthService auth;
  setUp(() async {
    installDraftFakes();
    accounts = TestAccounts();
    auth = AuthService(repository: accounts);
    AuthService.install(auth);
    await auth.registerVendor(
      email: 'widget-phase3@test.com',
      password: 'password',
      storeName: 'Store',
      phone: '9876543210',
      category: 'groceries',
    );
    accounts.approval(auth.identity!.uid, 'approved');
    await settleSession();
    OfferService.install(OfferService(auth: auth, repository: TestOffers()));
  });
  tearDownAll(() => auth.dispose());
  testWidgets(
    'manual location validates, requires explicit consent, and confirms a persisted profile',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: StoreLocationEditor()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'NaN');
      await tester.enterText(find.byType(TextFormField).at(1), '77.2');
      await tester.tap(find.text('Save confirmed location'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a number'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), '11.1');
      await tester.tap(find.text('Save confirmed location'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Confirm that'),
        ),
        findsOneWidget,
      );
      expect(
        accounts.vendors[auth.identity!.uid]!.hasConfirmedLocation,
        isFalse,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save confirmed location'));
      await tester.pumpAndSettle();
      expect(
        accounts.vendors[auth.identity!.uid]!.hasConfirmedLocation,
        isTrue,
      );
      expect(accounts.vendors[auth.identity!.uid]!.latitude, 11.1);
    },
  );
  testWidgets(
    'real preview survives cancellation; picker errors are visible beside retained fields',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await auth.confirmStoreLocation(StoreLocation(11.1, 77.2));
      final image = await tester.runAsync(
        () => SelectedImage.validate(testPng),
      );
      final selection = ImageSelectionService.instance as TestSelection;
      selection.next = image;
      await tester.pumpWidget(const MaterialApp(home: CreateOfferScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Retained title',
      );
      await tester.ensureVisible(find.text('Choose photo'));
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      selection.next = null;
      await tester.ensureVisible(find.text('Choose photo'));
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      selection.failure = StateError('Photos permission unavailable');
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Photos permission'),
        ),
        findsOneWidget,
      );
      expect(find.byType(Image), findsOneWidget);
      final title = tester.widget<TextFormField>(
        find.byType(TextFormField).first,
      );
      expect(title.controller!.text, 'Retained title');
    },
  );
  testWidgets(
    'dashboard offers the recovered Android photo with its vendor-scoped draft',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final uid = auth.identity!.uid;
      await OfferDraftStore.instance.save(uid, {
        'id': 'recovered-id',
        'title': 'Recovered title',
        'category': 'services',
      });
      await OfferDraftStore.instance.markPicker(uid);
      (ImageSelectionService.instance as TestSelection).recovered = await tester
          .runAsync(() => SelectedImage.validate(testPng));
      await tester.pumpWidget(const SandhaiApp());
      await tester.pumpAndSettle();
      expect(find.text('Your offers'), findsOneWidget);
      expect(find.textContaining('Recover selected photo'), findsOneWidget);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Your offers'), findsNothing);
      await auth.registerVendor(
        email: 'different-vendor@test.com',
        password: 'password',
        storeName: 'Other vendor',
        phone: '9876543210',
        category: 'groceries',
      );
      await tester.pumpAndSettle();
      expect(find.text('Your offers'), findsOneWidget);
      expect(find.textContaining('Recover selected photo'), findsNothing);
      expect(find.text('Resume unsaved offer'), findsNothing);
    },
  );
}
