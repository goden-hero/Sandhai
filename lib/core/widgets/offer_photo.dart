import 'package:flutter/material.dart';

/// Demo repositories retain real photos as data URIs without Firebase or disk.
/// Native HttpClient cannot fetch data URIs; render their bytes directly.
class OfferPhoto extends StatelessWidget {
  const OfferPhoto({
    super.key,
    required this.url,
    this.width = 64,
    this.height = 64,
  });
  final String url;
  final double width, height;
  @override
  Widget build(BuildContext context) {
    Widget broken(BuildContext context, Object error, StackTrace? stack) =>
        const Icon(Icons.broken_image_outlined);
    if (url.startsWith('data:image/')) {
      try {
        return Image.memory(
          UriData.parse(url).contentAsBytes(),
          width: width,
          height: height,
          fit: BoxFit.cover,
          semanticLabel: 'Saved offer photo',
          errorBuilder: broken,
        );
      } on FormatException {
        return const Icon(Icons.broken_image_outlined);
      }
    }
    return Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      semanticLabel: 'Saved offer photo',
      errorBuilder: broken,
    );
  }
}
