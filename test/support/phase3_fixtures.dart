import 'package:sandhai/data/offer_repository.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:sandhai/core/images/offer_draft_store.dart';
import 'package:sandhai/core/images/image_selection_service.dart';
import 'package:sandhai/core/images/selected_image.dart';

final Uint8List testPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP438Ag8F+AgYHh/////wEnDgabX8NVlAAAAABJRU5ErkJggg==',
);

class MemoryDrafts extends OfferDraftStore {
  final uploads = <String, UploadedImage>{};
  @override
  Future<void> rememberUpload(
    String uid,
    String id,
    UploadedImage image,
  ) async {
    uploads['$uid/$id'] = image;
  }

  @override
  Future<UploadedImage?> pendingUpload(String uid, String id) async =>
      uploads['$uid/$id'];
  @override
  Future<void> forgetUpload(String uid, String id) async {
    uploads.remove('$uid/$id');
  }

  String? owner;
  @override
  Future<void> markPicker(String uid) async {
    owner = uid;
  }

  @override
  Future<String?> pickerOwner() async => owner;
  @override
  Future<void> clearPicker() async {
    owner = null;
  }

  final values = <String, Map<String, dynamic>>{};
  @override
  Future<void> save(String uid, Map<String, dynamic> fields) async {
    values[uid] = fields;
  }

  @override
  Future<Map<String, dynamic>?> read(String uid) async => values[uid];
  @override
  Future<void> clear(String uid) async {
    values.remove(uid);
  }
}

class TestSelection extends ImageSelectionService {
  SelectedImage? next, recovered;
  Object? failure;
  @override
  Future<SelectedImage?> pick() async {
    if (failure != null) throw failure!;
    return next;
  }

  @override
  Future<SelectedImage?> recover() async => recovered;
}

void installDraftFakes() {
  OfferDraftStore.instance = MemoryDrafts();
  ImageSelectionService.instance = TestSelection();
}
