class CallLifecycle {
  const CallLifecycle._();

  static String status(Map<String, dynamic>? call) =>
      call?['status']?.toString().toLowerCase() ?? 'initiated';

  static bool wasAccepted(Map<String, dynamic>? call) =>
      call?['exotelCallSid']?.toString().trim().isNotEmpty == true;

  static bool isTerminal(Map<String, dynamic>? call) {
    final callStatus = status(call);
    return callStatus == 'completed' || callStatus == 'failed';
  }

  static int duration(Map<String, dynamic>? call) {
    final value = call?['duration'];
    return value is num ? value.toInt() : 0;
  }
}