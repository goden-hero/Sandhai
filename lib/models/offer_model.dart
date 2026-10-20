import '../core/constants/offer_categories.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class OfferModel {
  final String id;
  final String vendorId;
  final String title;
  final String description;
  final double oldPrice;
  final double newPrice;
  final String imageUrl;
  final String category;
  final String? imagePath, imageContentType;
  final double? imageSize;
  final double? latitude;
  final double? longitude;
  final String geohash;
  final DateTime createdAt;
  final DateTime expiryTime;
  final String status; // 'active' | 'expired' | 'deleted' | 'draft'

  OfferModel({
    required this.id,
    required this.vendorId,
    required this.title,
    required this.description,
    required this.oldPrice,
    required this.newPrice,
    required this.imageUrl,
    this.category = 'other',
    this.imagePath,
    this.imageContentType,
    this.imageSize,
    required this.latitude,
    required this.longitude,
    required this.geohash,
    required this.createdAt,
    required this.expiryTime,
    required this.status,
  });

  factory OfferModel.fromFirestore(DocumentSnapshot doc) =>
      OfferModel.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});
  factory OfferModel.fromMap(String id, Map<String, dynamic> data) {
    return OfferModel(
      id: id,
      vendorId: data['vendorId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      oldPrice: (data['oldPrice'] as num?)?.toDouble() ?? 0.0,
      newPrice: (data['newPrice'] as num?)?.toDouble() ?? 0.0,
      imageUrl: data['imageUrl'] ?? '',
      category: OfferCategories.normalize(data['category']),
      imagePath: data['imagePath'],
      imageContentType: data['imageContentType'],
      imageSize: (data['imageSize'] as num?)?.toDouble(),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      geohash: data['geohash'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiryTime:
          (data['expiryTime'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(hours: 24)),
      status: data['status'] ?? 'draft',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'vendorId': vendorId,
      'title': title,
      'description': description,
      'oldPrice': oldPrice,
      'newPrice': newPrice,
      'imageUrl': imageUrl,
      'category': OfferCategories.normalize(category),
      if (imagePath != null) 'imagePath': imagePath,
      if (imageContentType != null) 'imageContentType': imageContentType,
      if (imageSize != null) 'imageSize': imageSize!.toInt(),
      'latitude': latitude,
      'longitude': longitude,
      'geohash': geohash,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiryTime': Timestamp.fromDate(expiryTime),
      'status': status,
    };
  }
}
