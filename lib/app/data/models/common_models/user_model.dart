class UserModel {
  final String id;
  final String role;
  final String name;
  final String email;
  final String? phone;
  final String? address;
  final String? profileImage;
  final bool isActive;
  final bool isEmailVerified;
  final String? googleId;
  final String? facebookId;
  final String? appleId;
  final String? currencyPreference; // 'PKR' | 'USD' | null (not yet chosen)
  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel({
    required this.role,
    required this.id,
    required this.name,
    required this.email,
    this.address,
    this.phone,
    this.profileImage,
    required this.isActive,
    required this.isEmailVerified,
    this.googleId,
    this.facebookId,
    this.appleId,
    this.currencyPreference,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: (json['_id'] ?? json['id']) as String,
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      profileImage: json['profileImage'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      isEmailVerified: json['isEmailVerified'] as bool? ?? false,
      googleId: json['googleId'] as String?,
      facebookId: json['facebookId'] as String?,
      appleId: json['appleId'] as String?,
      currencyPreference: json['currencyPreference'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'email': email,
      'phone': phone,
      'address': address,
      'profileImage': profileImage,
      'isActive': isActive,
      'isEmailVerified': isEmailVerified,
      'googleId': googleId,
      'facebookId': facebookId,
      'appleId': appleId,
      'currencyPreference': currencyPreference,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? role,
    String? email,
    String? phone,
    String? address,
    String? profileImage,
    bool? isActive,
    bool? isEmailVerified,
    String? googleId,
    String? facebookId,
    String? appleId,
    String? currencyPreference,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      profileImage: profileImage ?? this.profileImage,
      isActive: isActive ?? this.isActive,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      googleId: googleId ?? this.googleId,
      facebookId: facebookId ?? this.facebookId,
      appleId: appleId ?? this.appleId,
      currencyPreference: currencyPreference ?? this.currencyPreference,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
