import '../core/location/store_location.dart';
import '../core/utils/geohash_utils.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class VendorModel {
  final String uid;
  final String name;
  final String phone;
  final String category;
  final String? address;
  final String? description;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final String geohash;
  final DateTime? locationConfirmedAt;
  bool get hasConfirmedLocation =>
      locationConfirmedAt != null &&
      GeohashUtils.isValidLocation(latitude, longitude) &&
      geohash == GeohashUtils.encode(latitude!, longitude!);
  StoreLocation? get location =>
      hasConfirmedLocation ? StoreLocation(latitude!, longitude!) : null;
  final DateTime createdAt;
  final DateTime? updatedAt;

  VendorModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.category,
    this.address,
    this.description,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.geohash = '',
    this.locationConfirmedAt,
    required this.createdAt,
    this.updatedAt,
  });

  factory VendorModel.fromFirestore(DocumentSnapshot doc) =>
      VendorModel.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});
  factory VendorModel.fromMap(String id, Map<String, dynamic> data) {
    return VendorModel(
      uid: id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      category: data['category'] ?? '',
      address: data['address'],
      description: data['description'],
      imageUrl: data['imageUrl'],
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      geohash: data['geohash'] ?? '',
      locationConfirmedAt: (data['locationConfirmedAt'] as Timestamp?)
          ?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'category': category,
      if (address != null && address!.isNotEmpty) 'address': address,
      if (description != null && description!.isNotEmpty)
        'description': description,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (geohash.isNotEmpty) 'geohash': geohash,
      if (locationConfirmedAt != null)
        'locationConfirmedAt': Timestamp.fromDate(locationConfirmedAt!),
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  VendorModel copyWith({
    String? name,
    String? phone,
    String? category,
    String? address,
    String? description,
    String? imageUrl,
    double? latitude,
    double? longitude,
    String? geohash,
    DateTime? updatedAt,
    DateTime? locationConfirmedAt,
  }) {
    return VendorModel(
      uid: uid,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      category: category ?? this.category,
      address: address ?? this.address,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      geohash: geohash ?? this.geohash,
      createdAt: createdAt,
      locationConfirmedAt: locationConfirmedAt ?? this.locationConfirmedAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
