import 'package:image/image.dart' as headers;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

import '../errors/app_failure.dart';

class SelectedImage {
  SelectedImage._(this.bytes, this.contentType, this.extension, this.digest);
  static const maxBytes = 5 * 1024 * 1024;
  static const maxPixels = 40000000;
  final Uint8List bytes;
  final String contentType, extension, digest;
  String get filename => '$digest.$extension';
  static Future<SelectedImage> validate(Uint8List source) async {
    if (source.isEmpty || source.length > maxBytes) {
      throw const AppFailure('Choose an image between 1 byte and 5 MiB.');
    }
    // Inspect signatures, then decode actual content. File extensions/MIME hints
    // from a picker are untrusted; canonical output names use the detected type.
    final bytes = Uint8List.fromList(source);
    bool starts(List<int> sig) =>
        bytes.length >= sig.length &&
        List.generate(sig.length, (i) => bytes[i] == sig[i]).every((v) => v);
    final (mime, ext) = starts([137, 80, 78, 71, 13, 10, 26, 10])
        ? ('image/png', 'png')
        : starts([255, 216, 255])
        ? ('image/jpeg', 'jpg')
        : bytes.length >= 12 &&
              String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
              String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP'
        ? ('image/webp', 'webp')
        : throw const AppFailure(
            'Choose a valid JPEG, PNG, or WebP photo. HEIC, GIF, and SVG are not supported.',
          );
    ui.Codec? codec;
    try {
      final headers.Decoder decoder = switch (ext) {
        'png' => headers.PngDecoder(),
        'jpg' => headers.JpegDecoder(),
        _ => headers.WebPDecoder(),
      };
      final info = decoder.startDecode(bytes);
      if (info == null || info.width <= 0 || info.height <= 0) {
        throw const AppFailure(
          'The selected file has an invalid image header. Choose another photo.',
        );
      }
      if (info.width * info.height > maxPixels) {
        throw const AppFailure('Choose an image of at most 40 megapixels.');
      }
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 64,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(
        'The selected file could not be decoded as an image. Choose another photo.',
      );
    } finally {
      codec?.dispose();
    }
    return SelectedImage._(bytes, mime, ext, sha256.convert(bytes).toString());
  }
}
