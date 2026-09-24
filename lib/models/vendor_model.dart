import 'package:cloud_firestore/cloud_firestore.dart';

class VendorModel {
  final String uid;
  final String name;
  final String phone;
  final String category;
  final double latitude;
  final double longitude;
  final String geohash;
  final DateTime createdAt;

  VendorModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.geohash,
    required this.createdAt,
  });

  factory VendorModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VendorModel(
      uid: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      category: data['category'] ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
      geohash: data['geohash'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'category': category,
      'latitude': latitude,
      'longitude': longitude,
      'geohash': geohash,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
