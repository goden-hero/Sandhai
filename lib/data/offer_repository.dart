import 'dart:typed_data';

import '../models/offer_model.dart';

class UploadedImage {
  const UploadedImage(this.path, this.url);
  final String path, url;
}

abstract class OfferRepository {
  String newId();
  Stream<List<OfferModel>> watchVendor(String uid);
  Future<OfferModel?> fetch(String id);
  Future<UploadedImage> upload(
    String uid,
    String id,
    Uint8List bytes,
    String filename,
  );
  Future<void> deleteUpload(UploadedImage image);
  Future<OfferModel> save(OfferModel offer);
}
