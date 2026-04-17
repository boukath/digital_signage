// File: lib/features/super_admin/domain/tenant_model.dart

class Tenant {
  final String id;
  final String companyName;
  final String contactEmail;
  final String phoneNumber;
  final String address;
  final bool isActive;

  // --- STRICT TIME-BASED LICENSE ---
  final DateTime licenseStartDate;
  final DateTime licenseEndDate;

  Tenant({
    required this.id,
    required this.companyName,
    required this.contactEmail,
    required this.phoneNumber,
    required this.address,
    required this.licenseStartDate,
    required this.licenseEndDate,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'companyName': companyName,
      'contactEmail': contactEmail,
      'phoneNumber': phoneNumber,
      'address': address,
      'isActive': isActive,
      'licenseStartDate': licenseStartDate.toIso8601String(),
      'licenseEndDate': licenseEndDate.toIso8601String(),
    };
  }

  factory Tenant.fromMap(Map<String, dynamic> map, String documentId) {
    return Tenant(
      id: documentId,
      companyName: map['companyName'] ?? 'Unknown Company',
      contactEmail: map['contactEmail'] ?? 'No Email',
      phoneNumber: map['phoneNumber'] ?? 'N/A',
      address: map['address'] ?? 'N/A',
      isActive: map['isActive'] ?? true,
      // If dates don't exist yet, we default to today and 1 year from now to prevent crashes
      licenseStartDate: map['licenseStartDate'] != null
          ? DateTime.parse(map['licenseStartDate'])
          : DateTime.now(),
      licenseEndDate: map['licenseEndDate'] != null
          ? DateTime.parse(map['licenseEndDate'])
          : DateTime.now().add(const Duration(days: 365)),
    );
  }
}