import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/services.dart';
import 'services/auth_service.dart';


import 'screens/auth/login_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/admin_login_screen.dart';
import 'screens/auth/admin_role_select_screen.dart';
import 'screens/auth/email_screen.dart';
import 'screens/auth/email_verify_screen.dart';
import 'screens/auth/success_screen.dart';
import 'screens/auth/verify_gate_screen.dart';
import 'screens/auth/employee_login_screen.dart';
import 'screens/jobs/public_jobs_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/dashboard/admin_dashboard_screen.dart';
import 'screens/tasks/task_execution_screen.dart';
import 'screens/tasks/call_screen.dart';
import 'screens/tasks/task_history_screen.dart';
import 'screens/earnings/earnings_screen.dart';
import 'screens/earnings/earnings_history_screen.dart';
import 'screens/profile/kyc_screen.dart';
import 'screens/profile/edit_profile_screen.dart';
import 'screens/profile/bank_details_screen.dart';
import 'screens/notifications/notification_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/help_screen.dart';
import 'screens/inbox/inbox_screen.dart';
import 'screens/settings/privacy_policy_screen.dart';
import 'screens/settings/terms_of_service_screen.dart';
import 'screens/admin/admin_review_screen.dart';
import 'screens/admin/submission_detail_screen.dart';
import 'screens/admin/admin_create_task_screen.dart';
import 'screens/admin/admin_kyc_screen.dart';
import 'screens/admin/admin_withdrawals_screen.dart';
import 'screens/admin/admin_users_screen.dart';
import 'screens/admin/admin_tasks_screen.dart';
import 'screens/admin/admin_notifications_screen.dart';
import 'screens/admin/admin_support_screen.dart';
import 'screens/admin/admin_support_chats_screen.dart';
import 'screens/admin/admin_mail_screen.dart';
import 'screens/admin/admin_settings_screen.dart';
import 'screens/admin/admin_error_logs_screen.dart';
import 'screens/dev/dev_login_screen.dart';
import 'screens/dev/dev_dashboard_screen.dart';

/// Centralised named-route definitions.
class AppRoutes {
  AppRoutes._();

  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  // ─── Route Names ────────────────────────────────────────────
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String signup = '/signup';
  static const String email = '/email';
  static const String emailVerify = '/email-verify';
  static const String success = '/success';
  static const String verifyGate = '/verify-gate';
  static const String employeeLogin = '/employee-login';
  static const String publicJobs = '/jobs-public';
  static const String dashboard = '/dashboard';
  static const String taskList = '/tasks';
  static const String taskHistory = '/tasks/history';
  static const String taskExecution = '/tasks/execute';
  static const String call = '/tasks/call';
  static const String earnings = '/earnings';
  static const String earningsHistory = '/earnings/history';
  static const String profile = '/profile';
  static const String editProfile = '/profile/edit';
  static const String kyc = '/profile/kyc';
  static const String bankDetails = '/profile/bank-details';
  static const String notifications = '/notifications';
  static const String settings = '/settings';
  static const String help = '/settings/help';
  static const String privacyPolicy = '/settings/privacy-policy';
  static const String termsOfService = '/settings/terms-of-service';
  static const String inbox = '/inbox';
  static const String adminLogin = '/admin/login';
  static const String adminRoleSelect = '/admin/roles';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminReview = '/admin/review';
  static const String submissionDetail = '/admin/submission';
  static const String adminCreateTask = '/admin/create-task';
  static const String adminKyc = '/admin/kyc';
  static const String adminWithdrawals = '/admin/withdrawals';
  static const String adminUsers = '/admin/users';
  static const String adminTasks = '/admin/tasks';
  static const String adminNotifications = '/admin/notifications';
  static const String adminSupport = '/admin/support';
  static const String adminSupportChats = '/admin/support-chats';
  static const String adminMail = '/admin/mail';
  static const String adminSettings = '/admin/settings';
  static const String adminErrorLogs = '/admin/error-logs';

  static const String admin = '/admin';

  // ─── Developer Mode (hidden — never linked from any UI) ─────
  static const String devLogin = '/dev/access';
  static const String devDashboard = '/dev/console';

  // ─── Initial Route ──────────────────────────────────────────
  static const String initial = onboarding;

  // ─── Route Map ──────────────────────────────────────────────
  static Map<String, WidgetBuilder> get routes => {
        onboarding: (_) => const OnboardingScreen(),
        login: (_) => const LoginScreen(),
        otp: (_) => const OtpScreen(),
        signup: (_) => const SignupScreen(),
        email: (_) => const EmailScreen(),
        emailVerify: (_) => const EmailVerifyScreen(),
        success: (_) => const SuccessScreen(),
        verifyGate: (_) => const VerifyGateScreen(),
        employeeLogin: (_) => const EmployeeLoginScreen(),
        publicJobs: (_) => const PublicJobsScreen(),
        dashboard: (_) => const DashboardScreen(),
        taskList: (_) => const DashboardScreen(initialTab: 1),
        taskHistory: (_) => const TaskHistoryScreen(),
        call: (_) => const CallScreen(),
        earnings: (_) => const EarningsScreen(),
        earningsHistory: (_) => const EarningsHistoryScreen(),
        profile: (_) => const DashboardScreen(initialTab: 2),
        editProfile: (_) => const EditProfileScreen(),
        kyc: (_) => const KycScreen(),
        bankDetails: (_) => const BankDetailsScreen(),
        notifications: (_) => const NotificationScreen(),
        settings: (_) => const SettingsScreen(),
        help: (_) => const HelpScreen(),
        privacyPolicy: (_) => const PrivacyPolicyScreen(),
        termsOfService: (_) => const TermsOfServiceScreen(),
        inbox: (_) => const InboxScreen(),
        adminLogin: (_) => const AdminLoginScreen(),
        adminRoleSelect: (_) => const AdminRoleSelectScreen(),
        adminDashboard: (context) => AdminDashboardScreen(
          activeRole: ModalRoute.of(context)?.settings.arguments as String?),
        admin: (_) => const AdminDashboardScreen(),
        adminReview: (_) => const AdminReviewScreen(),
        adminCreateTask: (_) => const AdminCreateTaskScreen(),
        adminKyc: (_) => const AdminKycScreen(),
        adminWithdrawals: (_) => const AdminWithdrawalsScreen(),
        adminUsers: (_) => const AdminUsersScreen(),
        adminTasks: (_) => const AdminTasksScreen(),
        adminNotifications: (_) => const AdminNotificationsScreen(),
        adminSupport: (_) => const AdminSupportScreen(),
        adminSupportChats: (_) => const AdminSupportChatsScreen(),
        adminMail: (_) => const AdminMailScreen(),
        adminSettings: (_) => const AdminSettingsScreen(),
        adminErrorLogs: (_) => const AdminErrorLogsScreen(),
        devLogin: (_) => const DevLoginScreen(),
        devDashboard: (_) => const DevDashboardScreen(),
      };

  // ─── Route Generator (for args / guards) ────────────────────
  static Route<dynamic> onGenerateRoute(RouteSettings routeSettings) {
    if (routeSettings.name == taskExecution) {
      final args = routeSettings.arguments as Map<String, dynamic>? ?? {};
      return MaterialPageRoute(
        settings: routeSettings,
        builder: (context) => TaskExecutionScreen(
          taskId: args['taskId'],
          assignmentId: args['assignmentId'],
          payout: args['payout'],
          script: args['script'],
          clientName: args['clientName'],
          tatDeadline: args['tatDeadline'],
          totalLeads: (args['totalLeads'] as int?) ?? 0,
        ),
      );
    }

    if (routeSettings.name == submissionDetail) {
      final args = routeSettings.arguments as Map<String, dynamic>? ?? {};
      return MaterialPageRoute(
        settings: routeSettings,
        builder: (context) => SubmissionDetailScreen(
          submissionId: args['submissionId'] ?? '',
        ),
      );
    }

    if (routeSettings.name == call) {
      final args = routeSettings.arguments as Map<String, dynamic>? ?? {};
      return MaterialPageRoute(
        settings: routeSettings,
        builder: (context) => CallScreen(
          taskId: args['taskId'],
          assignmentId: args['assignmentId'],
          leadId: args['leadId'],
          leadName: args['leadName'],
          customerPhone: args['customerPhone'],
          clientName: args['clientName'],
        ),
      );
    }

    return MaterialPageRoute(
      settings: routeSettings,
      builder: (context) {
        final builder = routes[routeSettings.name];
        if (builder != null) return builder(context);
        return _NotFoundScreen(attemptedRoute: routeSettings.name);
      },
    );
  }
}

/// Fallback screen shown when a route is not registered.
class _NotFoundScreen extends StatelessWidget {
  final String? attemptedRoute;
  
  const _NotFoundScreen({this.attemptedRoute});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                final auth = context.read<AuthService>();
                
                String targetRoute = AppRoutes.login;
                if (auth.isAuthenticated) {
                  // If they were trying to access an admin route, send to admin dashboard
                  if (attemptedRoute != null && attemptedRoute!.startsWith('/admin')) {
                    targetRoute = AppRoutes.adminDashboard;
                  } else {
                     targetRoute = AppRoutes.dashboard;
                  }
                }
                
                Navigator.of(context).pushNamedAndRemoveUntil(targetRoute, (_) => false);
              },
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
