import 'dart:async';
import 'dart:typed_data';

import 'package:sandhai/core/errors/app_failure.dart';
import 'package:sandhai/data/account_repository.dart';
import 'package:sandhai/data/demo_account_repository.dart';
import 'package:sandhai/data/demo_offer_repository.dart';
import 'package:sandhai/data/offer_repository.dart';
import 'package:sandhai/models/offer_model.dart';
import 'package:sandhai/models/user_model.dart';
import 'package:sandhai/models/vendor_model.dart';

Stream<T> trackSubscription<T>(Stream<T> source, void Function(int) change) =>
    Stream.multi((out) {
      change(1);
      final sub = source.listen(
        out.addSync,
        onError: out.addErrorSync,
        onDone: out.closeSync,
      );
      out.onCancel = () {
        change(-1);
        return sub.cancel();
      };
    });

class TestAccounts extends DemoAccountRepository {
  int creations = 0, activeUserWatches = 0, activeVendorWatches = 0;
  bool failCompletion = false,
      failRead = false,
      failUpdate = false,
      failWatch = false,
      failLogout = false;
  Completer<void>? updateGate;
  @override
  Future<AccountIdentity> createAccount(String email, String password) async {
    creations++;
    return super.createAccount(email, password);
  }

  @override
  Future<void> completeRegistration(
    AccountIdentity identity,
    RegistrationData data,
  ) async {
    if (failCompletion) throw const AppFailure('Injected profile failure');
    await super.completeRegistration(identity, data);
  }

  @override
  Stream<UserModel?> watchUser(String uid) => trackSubscription(
    failWatch
        ? Stream.error(const AppFailure('Session stream failed'))
        : super.watchUser(uid),
    (delta) => activeUserWatches += delta,
  );

  @override
  Stream<VendorModel?> watchVendor(String uid) => trackSubscription(
    super.watchVendor(uid),
    (delta) => activeVendorWatches += delta,
  );

  @override
  Future<UserModel?> fetchUser(String uid) async {
    if (failRead) throw const AppFailure('Read failed');
    return super.fetchUser(uid);
  }

  @override
  Future<VendorModel> updateVendor(
    String uid, {
    required String name,
    required String phone,
    required String category,
    String? address,
    String? description,
    String? imageUrl,
  }) async {
    await updateGate?.future;
    if (failUpdate) throw const AppFailure('Server rejected profile');
    return super.updateVendor(
      uid,
      name: name,
      phone: phone,
      category: category,
      address: address,
      description: description,
      imageUrl: imageUrl,
    );
  }

  @override
  Future<void> signOut() async {
    if (failLogout) throw const AppFailure('Logout failed');
    await super.signOut();
  }

  void approval(String uid, String status) {
    final old = users[uid]!;
    setUser(
      UserModel(
        uid: uid,
        displayName: old.displayName,
        email: old.email,
        role: old.role,
        approvalStatus: status,
        createdAt: old.createdAt,
      ),
    );
  }
}

class TestOffers extends DemoOfferRepository {
  bool failUpload = false, failSave = false, loseResponse = false;
  int uploads = 0, saves = 0, cleanups = 0, activeWatches = 0;
  Completer<void>? saveGate;
  Future<void> Function()? afterUpload;
  @override
  Stream<List<OfferModel>> watchVendor(String uid) => trackSubscription(
    super.watchVendor(uid),
    (delta) => activeWatches += delta,
  );

  @override
  Future<UploadedImage> upload(
    String uid,
    String id,
    Uint8List bytes,
    String filename,
  ) async {
    uploads++;
    if (failUpload) throw const AppFailure('Upload failed');
    await afterUpload?.call();
    return UploadedImage(
      'offers/$uid/$id/$filename',
      'https://example.test/image.jpg',
    );
  }

  @override
  Future<void> deleteUpload(UploadedImage image) async {
    cleanups++;
  }

  @override
  Future<OfferModel> save(OfferModel offer) async {
    saves++;
    await saveGate?.future;
    if (failSave) throw const AppFailure('Write denied');
    final saved = await super.save(offer);
    if (loseResponse) throw const AppFailure('Lost response');
    return saved;
  }
}

Future<void> settleSession() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
