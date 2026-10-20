import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../errors/app_failure.dart';
import 'selected_image.dart';

class ImageSelectionService {
  ImageSelectionService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  static ImageSelectionService instance = ImageSelectionService();
  final ImagePicker _picker;
  Future<SelectedImage?> pick() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    return file == null ? null : _read(file);
  }

  Future<SelectedImage> _read(XFile file) async {
    if (await file.length() > SelectedImage.maxBytes) {
      throw const AppFailure('Choose an image no larger than 5 MiB.');
    }
    return SelectedImage.validate(await file.readAsBytes());
  }

  /// Android may kill our activity while the system picker is open. Retrieve
  /// its result on app entry; do not silently consume it in a disposed form.
  Future<SelectedImage?> recover() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    final files = response.files;
    return files == null || files.isEmpty ? null : _read(files.first);
  }
}
