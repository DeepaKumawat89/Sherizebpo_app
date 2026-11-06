/// Immutable snapshot of a user's verification state,
/// sourced from Firestore users/{uid}.
class VerificationStatus {
  final bool phoneVerified;
  final bool emailVerified;
  final bool isNewUser;

  const VerificationStatus({
    required this.phoneVerified,
    required this.emailVerified,
    required this.isNewUser,
  });

  /// Both verifications complete — user may access the dashboard.
  bool get isFullyVerified => phoneVerified && emailVerified;

  /// Sentinel for when Firestore document does not exist yet.
  factory VerificationStatus.newUser() => const VerificationStatus(
        phoneVerified: false,
        emailVerified: false,
        isNewUser: true,
      );

  factory VerificationStatus.fromMap(Map<String, dynamic> data) =>
      VerificationStatus(
        phoneVerified: data['phoneVerified'] == true,
        emailVerified: data['emailVerified'] == true,
        isNewUser: false,
      );

  @override
  String toString() =>
      'VerificationStatus(phone=$phoneVerified, email=$emailVerified, new=$isNewUser)';
}
