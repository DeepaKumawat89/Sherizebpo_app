/// Central definition of what a "100% complete" worker profile means.
///
/// Used to gate payouts (a worker may only request a withdrawal once the
/// profile is fully complete) and to surface which fields are still missing.
/// The same required-field set is mirrored server-side in
/// `functions/withdrawals/requestWithdrawal.js` — keep them in sync.
class ProfileCompletion {
  const ProfileCompletion._();

  static bool _has(dynamic value) =>
      value != null && value.toString().trim().isNotEmpty;

  static bool _hasPaymentDetails(Map<String, dynamic> user) {
    final bank = (user['bankDetails'] as Map<String, dynamic>?) ?? const {};
    final mode = (bank['paymentMode'] ?? 'upi').toString();
    if (mode == 'upi') {
      return _has(bank['upiId']);
    }
    return _has(bank['accountNumber']) && _has(bank['ifscCode']);
  }

  /// The ordered list of required fields and whether each is satisfied.
  static List<_ProfileField> _fields(Map<String, dynamic> user) => [
        _ProfileField(
            'Full name', _has(user['fullName']) || _has(user['name'])),
        _ProfileField('Email', _has(user['email'])),
        _ProfileField(
            'Phone', _has(user['phone']) || _has(user['phoneNumber'])),
        _ProfileField('Gender', _has(user['gender'])),
        _ProfileField('Date of birth', _has(user['dateOfBirth'])),
        _ProfileField('City', _has(user['city'])),
        _ProfileField('Bank / UPI details', _hasPaymentDetails(user)),
      ];

  /// Completion ratio in the range 0.0–1.0.
  static double percent(Map<String, dynamic> user) {
    final fields = _fields(user);
    if (fields.isEmpty) return 0;
    final done = fields.where((f) => f.done).length;
    return done / fields.length;
  }

  /// True when every required field is present.
  static bool isComplete(Map<String, dynamic> user) => percent(user) >= 1.0;

  /// Human-readable labels of the fields still missing.
  static List<String> missing(Map<String, dynamic> user) =>
      _fields(user).where((f) => !f.done).map((f) => f.label).toList();
}

class _ProfileField {
  final String label;
  final bool done;
  const _ProfileField(this.label, this.done);
}
