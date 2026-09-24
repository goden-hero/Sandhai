import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String displayName;
  final String email;
  final String role; // 'customer' | 'vendor'
  final String approvalStatus; // 'pending' | 'approved' | 'suspended' | 'n/a'
  final DateTime createdAt;
  final DateTime? updatedAt;

  UserModel({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.approvalStatus,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isVendor => role == 'vendor';
  bool get isCustomer => role == 'customer';
  bool get isApprovedVendor => isVendor && approvalStatus == 'approved';
  bool get isPendingVendor => isVendor && approvalStatus == 'pending';
  bool get isRejectedVendor => isVendor && (approvalStatus == 'rejected' || approvalStatus == 'suspended');

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserModel(
      uid: doc.id,
      displayName: data['displayName'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? 'customer',
      approvalStatus: data['approvalStatus'] ?? (data['role'] == 'vendor' ? 'pending' : 'approved'),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'email': email,
      'role': role,
      'approvalStatus': approvalStatus,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }
}
