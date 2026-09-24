import 'package:cloud_firestore/cloud_firestore.dart';

class VendorModel {
  final String uid;
  final String name;
  final String phone;
  final String category;
  final String? address;
  final String? description;
  final String? imageUrl;
  final double latitude;
  final double longitude;
  final String geohash;
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
    required this.latitude,
    required this.longitude,
    required this.geohash,
    required this.createdAt,
    this.updatedAt,
  });

  factory VendorModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return VendorModel(
      uid: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      category: data['category'] ?? '',
      address: data['address'],
      description: data['description'],
      imageUrl: data['imageUrl'],
      latitude: (data['latitude'] as num?)?.toDouble() ?? 13.0827,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 80.2707,
      geohash: data['geohash'] ?? 'tf340w',
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
      if (description != null && description!.isNotEmpty) 'description': description,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'geohash': geohash,
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
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

