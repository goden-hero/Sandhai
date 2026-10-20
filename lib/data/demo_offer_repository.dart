import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../models/offer_model.dart';
import 'offer_repository.dart';

/// Demo offers are isolated from Firebase and scoped to the demo account UID.
class DemoOfferRepository implements OfferRepository {
  final offers = <String, OfferModel>{};
  final _changes = StreamController<void>.broadcast();
  @override
  String newId() => 'demo_offer_${DateTime.now().microsecondsSinceEpoch}';
  List<OfferModel> _for(String uid) =>
      offers.values.where((o) => o.vendorId == uid).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  @override
  Stream<List<OfferModel>> watchVendor(String uid) => Stream.multi((out) {
    final sub = _changes.stream.listen((_) => out.addSync(_for(uid)));
    out.addSync(_for(uid));
    out.onCancel = sub.cancel;
  });

  @override
  Future<OfferModel?> fetch(String id) async => offers[id];
  @override
  Future<UploadedImage> upload(
    String uid,
    String id,
    Uint8List bytes,
    String filename,
  ) async => UploadedImage(
    'offers/$uid/$id/$filename',
    'data:image/${filename.endsWith('.png')
        ? 'png'
        : filename.endsWith('.webp')
        ? 'webp'
        : 'jpeg'};base64,${base64Encode(bytes)}',
  );
  @override
  Future<void> deleteUpload(UploadedImage image) async {}
  @override
  Future<OfferModel> save(OfferModel offer) async {
    final saved = offers.putIfAbsent(offer.id, () => offer);
    _changes.add(null);
    return saved;
  }
}
