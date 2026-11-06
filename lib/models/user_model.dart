/// User model representing the authenticated worker.
class UserModel {
  final String id;
  final String? fullName;
  final String? phone;
  final String? email;
  final String? profileImage;
  final String? gender;
  final String? dateOfBirth;
  final String? city;
  final String? state;
  final String? country;
  final String? address;
  final String? pincode;
  final String? language;
  final String? education;
  final String? experience;
  final String? preferredWorkTime;
  final String? deviceType;
  final String? internetType;
  final String? headsetAvailable;
  final String kycStatus; // pending | verified | rejected
  final double rating;
  final int totalTasksCompleted;
  final double walletBalance;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? fcmToken;
  final DateTime? lastTokenUpdated;

  const UserModel({
    required this.id,
    this.fullName,
    this.phone,
    this.email,
    this.profileImage,
    this.gender,
    this.dateOfBirth,
    this.city,
    this.state,
    this.country,
    this.address,
    this.pincode,
    this.language,
    this.education,
    this.experience,
    this.preferredWorkTime,
    this.deviceType,
    this.internetType,
    this.headsetAvailable,
    this.kycStatus = 'pending',
    this.rating = 0,
    this.totalTasksCompleted = 0,
    this.walletBalance = 0,
    this.createdAt,
    this.updatedAt,
    this.fcmToken,
    this.lastTokenUpdated,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? json['uid'] as String? ?? '',
      fullName: json['fullName'] as String? ?? json['name'] as String?,
      phone: json['phone'] as String? ?? json['phoneNumber'] as String?,
      email: json['email'] as String?,
      profileImage: json['profileImage'] as String? ??
          json['profileImageUrl'] as String? ??
          json['avatar_url'] as String?,
      gender: json['gender'] as String?,
      dateOfBirth: json['dateOfBirth'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      country: json['country'] as String?,
      address: json['address'] as String?,
      pincode: json['pincode'] as String?,
      language: json['language'] as String?,
      education: json['education'] as String?,
      experience: json['experience'] as String?,
      preferredWorkTime: json['preferredWorkTime'] as String?,
      deviceType: json['deviceType'] as String?,
      internetType: json['internetType'] as String?,
      headsetAvailable: json['headsetAvailable'] as String?,
      kycStatus: json['kycStatus'] as String? ??
          json['kyc_status'] as String? ??
          'pending',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      totalTasksCompleted: json['totalTasksCompleted'] as int? ??
          json['tasks_completed'] as int? ??
          json['completedTasks'] as int? ??
          0,
      walletBalance: (json['walletBalance'] as num?)?.toDouble() ??
          (json['total_earnings'] as num?)?.toDouble() ??
          (json['earnings'] as num?)?.toDouble() ??
          0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : (json['createdAt'] != null
              ? (json['createdAt'] is String
                  ? DateTime.parse(json['createdAt'] as String)
                  : (json['createdAt'] as dynamic).toDate())
              : null),
      updatedAt: json['updatedAt'] != null
          ? (json['updatedAt'] is String
              ? DateTime.parse(json['updatedAt'] as String)
              : (json['updatedAt'] as dynamic).toDate())
          : null,
      fcmToken: json['fcmToken'] as String?,
      lastTokenUpdated: json['lastTokenUpdated'] != null
          ? (json['lastTokenUpdated'] is String
              ? DateTime.parse(json['lastTokenUpdated'] as String)
              : (json['lastTokenUpdated'] as dynamic).toDate())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fullName': fullName,
        'phone': phone,
        'email': email,
        'profileImage': profileImage,
        'gender': gender,
        'dateOfBirth': dateOfBirth,
        'city': city,
        'state': state,
        'country': country,
        'address': address,
        'pincode': pincode,
        'language': language,
        'education': education,
        'experience': experience,
        'preferredWorkTime': preferredWorkTime,
        'deviceType': deviceType,
        'internetType': internetType,
        'headsetAvailable': headsetAvailable,
        'kycStatus': kycStatus,
        'rating': rating,
        'totalTasksCompleted': totalTasksCompleted,
        'walletBalance': walletBalance,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'fcmToken': fcmToken,
        'lastTokenUpdated': lastTokenUpdated?.toIso8601String(),
      };

  UserModel copyWith({
    String? fullName,
    String? phone,
    String? email,
    String? profileImage,
    String? gender,
    String? dateOfBirth,
    String? city,
    String? state,
    String? country,
    String? address,
    String? pincode,
    String? language,
    String? education,
    String? experience,
    String? preferredWorkTime,
    String? deviceType,
    String? internetType,
    String? headsetAvailable,
    String? kycStatus,
    double? rating,
    int? totalTasksCompleted,
    double? walletBalance,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? fcmToken,
    DateTime? lastTokenUpdated,
  }) {
    return UserModel(
      id: id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      profileImage: profileImage ?? this.profileImage,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      address: address ?? this.address,
      pincode: pincode ?? this.pincode,
      language: language ?? this.language,
      education: education ?? this.education,
      experience: experience ?? this.experience,
      preferredWorkTime: preferredWorkTime ?? this.preferredWorkTime,
      deviceType: deviceType ?? this.deviceType,
      internetType: internetType ?? this.internetType,
      headsetAvailable: headsetAvailable ?? this.headsetAvailable,
      kycStatus: kycStatus ?? this.kycStatus,
      rating: rating ?? this.rating,
      totalTasksCompleted: totalTasksCompleted ?? this.totalTasksCompleted,
      walletBalance: walletBalance ?? this.walletBalance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      fcmToken: fcmToken ?? this.fcmToken,
      lastTokenUpdated: lastTokenUpdated ?? this.lastTokenUpdated,
    );
  }
}
