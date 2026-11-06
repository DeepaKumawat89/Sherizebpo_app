import 'dart:math';

class StringUtils {
  /// Masks a phone number by replacing all but the last 4 digits with asterisks.
  /// Example: +919876543210 -> +91 ******3210
  static String maskPhoneNumber(String phone) {
    if (phone.isEmpty) return phone;
    
    // Remove any formatting spaces
    String cleaned = phone.trim();
    
    // If it's too short to mask properly, just return it
    if (cleaned.length < 5) return cleaned;

    // Best approach: keep first 3 characters (e.g. +91) and last 4 characters. Replace everything in between with *.
    if (cleaned.length > 7) {
      String start = '';
      String end = cleaned.substring(cleaned.length - 4);
      String middle = '';
      
      if (cleaned.startsWith('+')) {
        // assuming +XX or +X
        // let's try to keep country code. usually up to 3 chars after +
        // just keep up to 3 chars
        int keepStart = cleaned.length >= 12 ? 3 : 0; 
        if (cleaned.contains(' ')) {
           keepStart = cleaned.indexOf(' ') + 1;
        } else if (cleaned.length > 10) {
           // +919000000000
           keepStart = cleaned.length - 10;
        }
        start = cleaned.substring(0, keepStart);
        middle = '*' * (cleaned.length - start.length - end.length);
        if(!start.endsWith(' ')) {
          start += ' ';
        }
      } else {
        middle = '*' * (cleaned.length - 4);
      }
      
      return '$start$middle$end';
    }

    return cleaned;
  }

  /// Generates a worker ID with the format SHR-XXXX.
  static String generateWorkerId() {
    final random = Random();
    return 'SHR-${1000 + random.nextInt(9000)}';
  }

  /// Generates a friendly task code with the format TSK-XXXX shown in the UI
  /// instead of the raw Firestore document ID. Mirrors the campaign CMP-XXXX
  /// and payment PAY-XXXX codes. Callers dedup against existing tasks (see
  /// TaskService._generateUniqueTaskCode); pass a wider [width] to grow the
  /// space when the 4-digit range gets crowded.
  static String generateTaskCode({int width = 4}) {
    final random = Random();
    final min = pow(10, width - 1).toInt();
    return 'TSK-${min + random.nextInt(min * 9)}';
  }
}
