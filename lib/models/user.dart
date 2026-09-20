import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  final String id;
  final String? email;
  final String? fullName;
  final String? avatarUrl;
  final String? phone;
  final String? role;
  final bool isPharmacist;
  final bool isCourier;
  final bool isAdmin;
  final bool isActive;
  final DateTime? createdAt;

  const AppUser({
    required this.id,
    this.email,
    this.fullName,
    this.avatarUrl,
    this.phone,
    this.role,
    this.isPharmacist = false,
    this.isCourier = false,
    this.isAdmin = false,
    this.isActive = true,
    this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String? ?? 'patient';
    return AppUser(
      id: json['id'] as String? ?? json['uuid'] as String? ?? '',
      email: json['email'] as String?,
      fullName: json['full_name'] as String? ?? json['name'] as String?,
      avatarUrl: json['avatar_url'] as String? ?? json['photo_url'] as String?,
      phone: json['phone'] as String?,
      role: role,
      isPharmacist:
          role == 'pharmacist' || (json['is_pharmacist'] as bool? ?? false),
      isCourier: role == 'courier' || (json['is_courier'] as bool? ?? false),
      isAdmin: role == 'admin' || (json['is_admin'] as bool? ?? false),
      isActive: json['is_active'] != false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  bool get isPatient =>
      !isPharmacist && !isCourier && !isAdmin;

  @override
  List<Object?> get props => [
        id,
        email,
        fullName,
        role,
        isActive,
      ];
}

class SearchHistoryItem extends Equatable {
  final String id;
  final String query;
  final String? medicineId;
  final DateTime searchedAt;

  const SearchHistoryItem({
    required this.id,
    required this.query,
    this.medicineId,
    required this.searchedAt,
  });

  @override
  List<Object?> get props => [id, query, medicineId, searchedAt];
}

class Report extends Equatable {
  final String id;
  final String pharmacyId;
  final String? medicineId;
  final String reason;
  final String description;
  final DateTime createdAt;

  const Report({
    required this.id,
    required this.pharmacyId,
    this.medicineId,
    required this.reason,
    required this.description,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, pharmacyId, medicineId, reason];
}
