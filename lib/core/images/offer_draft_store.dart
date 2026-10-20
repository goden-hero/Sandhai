import '../../app/config.dart';
import '../../data/offer_repository.dart';

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Unsaved fields are local and UID-scoped. Never publish a recovered draft
/// automatically, and never share its contents with another account.
class OfferDraftStore {
  static OfferDraftStore instance = OfferDraftStore();
  late final _preferences = SharedPreferencesAsync();
  String get _scope =>
      '${AppConfig.current.mode.name}-${AppConfig.current.emulatorProjectId}';
  String _key(String uid) => 'offer-draft-v3-$_scope-$uid';
  Future<void> save(String uid, Map<String, dynamic> fields) =>
      _preferences.setString(_key(uid), jsonEncode(fields));
  Future<Map<String, dynamic>?> read(String uid) async {
    final value = await _preferences.getString(_key(uid));
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  Future<void> markPicker(String uid) =>
      _preferences.setString('picker-owner-v3-$_scope', uid);
  Future<String?> pickerOwner() =>
      _preferences.getString('picker-owner-v3-$_scope');
  Future<void> clearPicker() => _preferences.remove('picker-owner-v3-$_scope');
  String _uploadKey(String uid, String id) =>
      'offer-upload-v3-$_scope-$uid-$id';
  Future<void> rememberUpload(String uid, String id, UploadedImage image) =>
      _preferences.setString(
        _uploadKey(uid, id),
        jsonEncode({'path': image.path, 'url': image.url}),
      );
  Future<UploadedImage?> pendingUpload(String uid, String id) async {
    final value = await _preferences.getString(_uploadKey(uid, id));
    if (value == null) return null;
    final data = jsonDecode(value) as Map<String, dynamic>;
    return UploadedImage(data['path'] as String, data['url'] as String);
  }

  Future<void> forgetUpload(String uid, String id) =>
      _preferences.remove(_uploadKey(uid, id));
  Future<void> clear(String uid) => _preferences.remove(_key(uid));
}
