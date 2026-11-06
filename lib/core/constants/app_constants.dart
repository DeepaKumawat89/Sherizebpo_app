/// Application-wide constant values.
///
/// All magic strings, API endpoints, and numeric constants live here
/// so they can be changed in one place.
class AppConstants {
  AppConstants._();

  // ─── App Info ───────────────────────────────────────────────
  static const String appName = 'Sherize';
  static const String tagline = 'Empowering Women Everyday';
    static const String appVersion = '2.1.5';

  // ─── Developer Credit ───────────────────────────────────────
  static const String developerCredit = 'Designed and Developed by';
  static const String developerCompany =
      'Novantix Innovation Technologies Pvt Ltd';
  static const String developerWebsite = 'novantixtech.com';
  static const String developerWebsiteUrl = 'https://novantixtech.com';

  // ─── Developer Mode ─────────────────────────────────────
  static const String developerRole = 'developer';
  // Only this email may hold the developer role (attribution anchor).
  // Change this to your own address before handover.
  static const String developerEmail = 'nspi1919@gmail.com';
  // Remote, developer-controlled branding/credit config location.
  static const String appConfigCollection = 'app_config';
  static const String brandingConfigDoc = 'branding';

  // Employee ID login: hired workers sign in with an Employee ID issued by the
  // super admin, mapped to an internal Firebase Auth email `<id>@<domain>`.
  // Must match EMPLOYEE_LOGIN_DOMAIN in functions/auth/hireWorker.js.
  static const String employeeLoginDomain = 'sherize.app';

  // Play Store listing.
  static const String androidPackageId = 'in.sherize.app';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$androidPackageId';

  // ─── Support & Contact ──────────────────────────────────────
  static const String supportEmail = 'info@sherize.in';
  static const String supportPhone = '+917672073746';
  // Digits only, international format (no '+' or spaces) for wa.me links.
  static const String whatsappNumber = '917672073746';
  static const String supportHours = 'Mon–Sat, 10 AM – 7 PM IST';
  static const String websiteUrl = 'https://sherize.in';

  // ─── API ────────────────────────────────────────────────────
  static const String baseUrl = bool.fromEnvironment('USE_FIREBASE_EMULATORS')
      ? 'http://127.0.0.1:5001/demo-sherize-workflow/us-central1/api'
      : 'https://us-central1-sherize-bpo.cloudfunctions.net/api';
  static const Duration apiTimeout = Duration(seconds: 30);

  // ─── Local Storage Keys ─────────────────────────────────────
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';
  static const String onboardingKey = 'onboarding_complete';
  static const String themeKey = 'app_theme';
  static const String languageKey = 'app_language';

  // ─── Formatting ─────────────────────────────────────────────
  static const String currencySymbol = '₹';
  static const String countryCode = '+91';

  // ─── Pagination ─────────────────────────────────────────────
  static const int defaultPageSize = 20;

  // ─── Validation ─────────────────────────────────────────────
  static const int otpLength = 6;
  static const int phoneLength = 10;
  static const int minPasswordLength = 8;
}
