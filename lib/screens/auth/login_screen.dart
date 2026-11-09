// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:lucide_icons/lucide_icons.dart';
// import 'package:provider/provider.dart';
// import '../../core/constants/constants.dart';
// import '../../services/auth_service.dart';
// import '../../routes.dart';
// import 'otp_screen.dart';
// import '../../widgets/developer_credit.dart';

// class LoginScreen extends StatefulWidget {
//   const LoginScreen({super.key, this.useEmployeeId = false});

//   final bool useEmployeeId;

//   @override
//   State<LoginScreen> createState() => _LoginScreenState();
// }

// class _LoginScreenState extends State<LoginScreen> {
//   static const Color _headerIndigo = Color(0xFF6366F1);
//   static const Color _referenceDeepIndigo = Color(0xFF3C2FE3);
//   static const Color _referenceIndigo = Color(0xFF4638E5);
//   static const Color _referenceBlueViolet = Color(0xFF5144E7);
//   static const Color _referenceViolet = Color(0xFF675BE9);
//   static const Color _referenceSoftViolet = Color(0xFF8176EA);
//   static const Color _referenceLavenderViolet = Color(0xFF9B91F0);


//   final _formKey = GlobalKey<FormState>();
//   final _emailCtrl = TextEditingController();
//   final _employeeIdCtrl = TextEditingController();
//   final _passwordCtrl = TextEditingController();
//   final _phoneCtrl = TextEditingController();
//   late bool _useEmployeeId;
//   bool _mobileLogin = false;
//   bool _obscurePassword = true;
//   bool _loading = false;
//   String? _error;

//   @override
//   void initState() {
//     super.initState();
//     _useEmployeeId = widget.useEmployeeId;
//   }

//   @override
//   void dispose() {
//     _emailCtrl.dispose();
//     _employeeIdCtrl.dispose();
//     _passwordCtrl.dispose();
//     _phoneCtrl.dispose();
//     super.dispose();
//   }

//   void _changeMethod({required bool mobile, bool employee = false}) {
//     if (_loading) return;
//     FocusScope.of(context).unfocus();
//     _formKey.currentState?.reset();
//     _passwordCtrl.clear();
//     setState(() {
//       _mobileLogin = mobile;
//       _useEmployeeId = employee;
//       _obscurePassword = true;
//       _error = null;
//     });
//   }

//   Future<void> _login() async {
//     if (_loading || !_formKey.currentState!.validate()) return;
//     FocusScope.of(context).unfocus();
//     setState(() {
//       _loading = true;
//       _error = null;
//     });
//     try {
//       final auth = context.read<AuthService>();
//       final error = _useEmployeeId
//           ? await auth.loginWithEmployeeId(
//               _employeeIdCtrl.text.trim(), _passwordCtrl.text)
//           : await auth.loginWithEmailPassword(
//               _emailCtrl.text.trim(), _passwordCtrl.text);
//       if (!mounted) return;
//       if (error == null) {
//         TextInput.finishAutofillContext();
//         Navigator.of(context)
//             .pushNamedAndRemoveUntil(AppRoutes.dashboard, (_) => false);
//       } else {
//         setState(() => _error = error);
//       }
//     } catch (_) {
//       if (mounted) {
//         setState(() => _error = 'Login failed. Please try again.');
//       }
//     } finally {
//       if (mounted) setState(() => _loading = false);
//     }
//   }

//   Future<void> _sendOtp() async {
//     if (_loading || !_formKey.currentState!.validate()) {
//       return;
//     }
//     final phone = '+91${_phoneCtrl.text.trim()}';
//     FocusScope.of(context).unfocus();
//     setState(() {
//       _error = null;
//       _loading = true;
//     });
//     try {
//       await context.read<AuthService>().sendOtp(
//         phone,
//         onVerified: () {
//           if (!mounted || !_mobileLogin) return;
//           Navigator.pushNamedAndRemoveUntil(
//               context, AppRoutes.verifyGate, (_) => false);
//         },
//         onCodeSent: (verificationId) {
//           if (!mounted ||
//               !_mobileLogin ||
//               ModalRoute.of(context)?.isCurrent != true) {
//             return;
//           }
//           setState(() => _loading = false);
//           showModalBottomSheet<void>(
//             context: context,
//             isScrollControlled: true,
//             backgroundColor: Colors.transparent,
//             shape: const RoundedRectangleBorder(
//               borderRadius: BorderRadius.vertical(
//                 top: Radius.circular(AppSizes.radiusXxl),
//               ),
//             ),
//             clipBehavior: Clip.antiAlias,
//             builder: (_) => FractionallySizedBox(
//               heightFactor: 0.9,
//               child: OtpScreen(
//                 phone: phone,
//                 verificationId: verificationId,
//                 embedded: true,
//               ),
//             ),
//           );
//         },
//         onError: (error) {
//           if (!mounted || !_mobileLogin) return;
//           setState(() {
//             _loading = false;
//             _error = error;
//           });
//         },
//       );
//     } catch (_) {
//       if (!mounted) return;
//       setState(() {
//         _loading = false;
//         _error = 'Failed to send OTP. Please try again.';
//       });
//     } finally {
//       if (mounted) setState(() => _loading = false);
//     }
//   }

//   InputDecoration _decoration(String label, IconData icon) => InputDecoration(
//         labelText: label,
//         labelStyle: const TextStyle(
//           color: AppColors.textLabel,
//           fontSize: 14,
//           fontWeight: FontWeight.w600,
//         ),
//         floatingLabelStyle: const TextStyle(
//           color: _referenceDeepIndigo,
//           fontSize: 13,
//           fontWeight: FontWeight.w700,
//         ),
//         prefixIcon: Icon(icon, size: 19, color: _referenceDeepIndigo),
//         filled: true,
//         fillColor: AppColors.surfaceElevated,
//         contentPadding:
//             const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
//         errorMaxLines: 3,
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           borderSide: const BorderSide(color: AppColors.border),
//         ),
//         enabledBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           borderSide: const BorderSide(color: AppColors.border),
//         ),
//         disabledBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           borderSide: const BorderSide(color: AppColors.borderLight),
//         ),
//         focusedBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           borderSide: const BorderSide(color: _referenceDeepIndigo, width: 1.5),
//         ),
//         errorBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           borderSide: const BorderSide(color: AppColors.error),
//         ),
//         focusedErrorBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           borderSide: const BorderSide(color: AppColors.error, width: 1.5),
//         ),
//       );

//   Widget _buildForm() {
//     return AutofillGroup(
//       child: Form(
//         key: _formKey,
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             if (_mobileLogin)
//               TextFormField(
//                 key: const ValueKey('login-phone'),
//                 controller: _phoneCtrl,
//                 enabled: !_loading,
//                 keyboardType: TextInputType.phone,
//                 textInputAction: TextInputAction.done,
//                 autofillHints: const [AutofillHints.telephoneNumberNational],
//                 inputFormatters: [FilteringTextInputFormatter.digitsOnly],
//                 maxLength: 10,
//                 decoration: _decoration('Mobile number', LucideIcons.phone)
//                     .copyWith(prefixText: '+91 ', counterText: ''),
//                 validator: (value) =>
//                     RegExp(r'^\d{10}$').hasMatch(value?.trim() ?? '')
//                         ? null
//                         : 'Enter a valid 10-digit mobile number',
//                 onFieldSubmitted: (_) => _sendOtp(),
//               )
//             else ...[
//               TextFormField(
//                 key:
//                     ValueKey(_useEmployeeId ? 'login-employee' : 'login-email'),
//                 controller: _useEmployeeId ? _employeeIdCtrl : _emailCtrl,
//                 enabled: !_loading,
//                 keyboardType: _useEmployeeId
//                     ? TextInputType.text
//                     : TextInputType.emailAddress,
//                 textCapitalization: _useEmployeeId
//                     ? TextCapitalization.characters
//                     : TextCapitalization.none,
//                 textInputAction: TextInputAction.next,
//                 autofillHints: [
//                   _useEmployeeId ? AutofillHints.username : AutofillHints.email
//                 ],
//                 autocorrect: false,
//                 enableSuggestions: false,
//                 decoration: _decoration(
//                   _useEmployeeId ? 'Employee ID' : 'Email address',
//                   _useEmployeeId ? LucideIcons.user : LucideIcons.mail,
//                 ),
//                 validator: (value) {
//                   final input = value?.trim() ?? '';
//                   if (_useEmployeeId) {
//                     return RegExp(r'^SHR-?(?:\d{4}|\d{6})$',
//                                 caseSensitive: false)
//                             .hasMatch(input)
//                         ? null
//                         : 'Enter a valid Employee ID (e.g. SHR-4450)';
//                   }
//                   return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(input)
//                       ? null
//                       : 'Enter a valid email address';
//                 },
//               ),
//               const SizedBox(height: 16),
//               TextFormField(
//                 key: const ValueKey('login-password'),
//                 controller: _passwordCtrl,
//                 enabled: !_loading,
//                 obscureText: _obscurePassword,
//                 autocorrect: false,
//                 enableSuggestions: false,
//                 textInputAction: TextInputAction.done,
//                 autofillHints: const [AutofillHints.password],
//                 decoration: _decoration('Password', LucideIcons.lock).copyWith(
//                   suffixIcon: IconButton(
//                     tooltip:
//                         _obscurePassword ? 'Show password' : 'Hide password',
//                     onPressed: _loading
//                         ? null
//                         : () => setState(
//                             () => _obscurePassword = !_obscurePassword),
//                     icon: Icon(
//                         _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
//                         size: 20),
//                   ),
//                 ),
//                 validator: (value) => value == null || value.isEmpty
//                     ? 'Enter your password'
//                     : null,
//                 onFieldSubmitted: (_) => _login(),
//               ),
//             ],
//             if (_error != null) ...[
//               const SizedBox(height: 16),
//               Semantics(
//                 liveRegion: true,
//                 child: Text(_error!,
//                     style: const TextStyle(color: AppColors.errorDark)),
//               ),
//             ],
//             const SizedBox(height: 24),
//             FractionallySizedBox(
//               widthFactor: 0.50,
//               child: Container(
//                 height: AppSizes.buttonHeightLg,
//                 padding: const EdgeInsets.fromLTRB(24, 6, 6, 6),
//                 decoration: BoxDecoration(
//                   color: _loading
//                       ? Colors.indigo.shade500.withValues(alpha: 0.60)
//                       : Colors.indigo.shade500,
//                   borderRadius: BorderRadius.circular(100), // full pill
//                   boxShadow: _loading
//                       ? null
//                       : [
//                           BoxShadow(
//                             color:
//                                 const Color(0xFF0F1A4A).withValues(alpha: 0.22),
//                             blurRadius: 16,
//                             offset: const Offset(0, 6),
//                           ),
//                         ],
//                 ),
//                 child: GestureDetector(
//                   behavior: HitTestBehavior.opaque,
//                   onTap: _loading
//                       ? null
//                       : _mobileLogin
//                           ? _sendOtp
//                           : _login,
//                   child: Row(
//                     children: [
//                       Expanded(
//                         child: Center(
//                           child: _loading
//                               ? const SizedBox(
//                                   width: 22,
//                                   height: 22,
//                                   child: CircularProgressIndicator(
//                                     strokeWidth: 2,
//                                     color: Colors.white,
//                                     semanticsLabel: 'Signing in',
//                                   ),
//                                 )
//                               : Text(
//                                   _mobileLogin ? 'Send OTP' : 'Sign in',
//                                   style: const TextStyle(
//                                     color: Colors.white,
//                                     fontSize: 16,
//                                     fontWeight: FontWeight.w800,
//                                   ),
//                                 ),
//                         ),
//                       ),
//                       AspectRatio(
//                         aspectRatio: 1,
//                         child: Container(
//                           decoration: BoxDecoration(
//                             shape: BoxShape.circle,
//                             color:  Colors.white // soft purple circle
//                                 .withValues(
//                               alpha: _loading
//                                   ? 0.60
//                                   : 1.0,
//                             ),
//                           ),
//                           child: const Icon(
//                             Icons.arrow_forward_rounded,
//                             color: Colors.indigo,
//                             size: 26,
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return PopScope(
//       canPop: Navigator.of(context).canPop(),
//       onPopInvokedWithResult: (didPop, result) async {
//         if (didPop) return;
//         final shouldExit = await showDialog<bool>(
//           context: context,
//           builder: (context) => AlertDialog(
//             title: const Text('Exit App?'),
//             content: const Text('Do you want to exit Sherize?'),
//             actions: [
//               TextButton(
//                 onPressed: () => Navigator.of(context).pop(false),
//                 child: const Text('Cancel'),
//               ),
//               TextButton(
//                 onPressed: () => Navigator.of(context).pop(true),
//                 child: const Text('Exit'),
//               ),
//             ],
//           ),
//         );
//         if (shouldExit == true) SystemNavigator.pop();
//       },
//       child: Scaffold(
//         resizeToAvoidBottomInset: true,
//         backgroundColor: _headerIndigo,
//         body: SafeArea(
//           bottom: false,
//           child: LayoutBuilder(
//             builder: (context, constraints) {
//               final isCompact = constraints.maxWidth < 360;
//               final headerHeight = isCompact ? 240.0 : 280.0;
//               final logoSize = _mobileLogin
//                   ? (isCompact ? 224.0 : 260.0)
//                   : (isCompact ? 196.0 : 228.0);

//               return Column(
//                 children: [
//                   Container(
//                     width: double.infinity,
//                     height: headerHeight,
//                     decoration: const BoxDecoration(color: _headerIndigo),
//                     child: Column(
//                       mainAxisAlignment: MainAxisAlignment.start,
//                       children: [
//                         SizedBox(height: isCompact ? 6 : 8),
//                         Image.asset(
//                           'assets/images/sherize_logo.png',
//                           width: logoSize,
//                           height: logoSize,
//                           fit: BoxFit.contain,
//                           semanticLabel: 'Sherize',
//                         ),
//                         if (!_mobileLogin)
//                           Transform.translate(
//                             offset: const Offset(0, -50),
//                             child: Text(
//                               'Welcome back',
//                               textAlign: TextAlign.center,
//                               style: Theme.of(context)
//                                   .textTheme
//                                   .headlineSmall
//                                   ?.copyWith(
//                                     fontWeight: FontWeight.w800,
//                                     color: Colors.white,
//                                     fontSize: isCompact ? 24 : 27,
//                                     letterSpacing: -0.5,
//                                   ),
//                             ),
//                           ),
//                       ],
//                     ),
//                   ),
//                   Expanded(
//                     child: Container(
//                       width: double.infinity,
//                       decoration: const BoxDecoration(
//                         color: AppColors.surface,
//                         borderRadius: BorderRadius.vertical(
//                           top: Radius.circular(AppSizes.radiusXxl),
//                         ),
//                       ),
//                       child: Center(
//                         child: ConstrainedBox(
//                           constraints: const BoxConstraints(maxWidth: 440),
//                           child: SingleChildScrollView(
//                             keyboardDismissBehavior:
//                                 ScrollViewKeyboardDismissBehavior.onDrag,
//                             padding: EdgeInsets.fromLTRB(
//                               isCompact
//                                   ? AppSizes.base
//                                   : AppSizes.screenPaddingH,
//                               isCompact ? AppSizes.sm : AppSizes.md,
//                               isCompact
//                                   ? AppSizes.base
//                                   : AppSizes.screenPaddingH,
//                               AppSizes.xxl +
//                                   MediaQuery.viewInsetsOf(context).bottom,
//                             ),
//                             child: Column(
//                               crossAxisAlignment: CrossAxisAlignment.stretch,
//                               children: [
//                                 if (_mobileLogin) ...[
//                                   const Text(
//                                     'Mobile Login',
//                                     style: TextStyle(
//                                       color: AppColors.textDark,
//                                       fontSize: 24,
//                                       fontWeight: FontWeight.w800,
//                                     ),
//                                   ),
//                                   const SizedBox(height: 24),
//                                 ],
//                                 if (!_mobileLogin) ...[
//                                   SegmentedButton<bool>(
//                                     segments: const [
//                                       ButtonSegment(
//                                           value: false, label: Text('Email')),
//                                       ButtonSegment(
//                                           value: true,
//                                           label: Text('Employee ID')),
//                                     ],
//                                     selected: {_useEmployeeId},
//                                     showSelectedIcon: false,
//                                     direction:
//                                         MediaQuery.sizeOf(context).width <
//                                                     360 ||
//                                                 MediaQuery.textScalerOf(context)
//                                                         .scale(14) >
//                                                     20
//                                             ? Axis.vertical
//                                             : Axis.horizontal,
//                                     onSelectionChanged: _loading
//                                         ? null
//                                         : (selection) => _changeMethod(
//                                             mobile: false,
//                                             employee: selection.single),
//                                     style: SegmentedButton.styleFrom(
//                                       minimumSize: const Size(0, 48),
//                                       textStyle: const TextStyle(
//                                         fontSize: 14,
//                                         fontWeight: FontWeight.w600,
//                                         letterSpacing: 0,
//                                       ),
//                                       selectedBackgroundColor:
//                                           _referenceLavenderViolet.withValues(
//                                               alpha: 0.18),
//                                       selectedForegroundColor:
//                                           _referenceDeepIndigo,
//                                       foregroundColor: AppColors.textBody,
//                                       side: const BorderSide(
//                                           color: AppColors.border),
//                                     ),
//                                   ),
//                                   const SizedBox(height: 24),
//                                 ],
//                                 _buildForm(),
//                                 if (_mobileLogin) const SizedBox(height: 24),
//                                 const SizedBox(height: 12),
//                                 OutlinedButton.icon(
//                                   onPressed: _loading
//                                       ? null
//                                       : () =>
//                                           _changeMethod(mobile: !_mobileLogin),
//                                   icon: Icon(
//                                     _mobileLogin
//                                         ? LucideIcons.mail
//                                         : LucideIcons.smartphone,
//                                     size: 18,
//                                   ),
//                                   label: Text(
//                                     _mobileLogin
//                                         ? 'Login with email'
//                                         : 'Login with mobile number',
//                                     textAlign: TextAlign.center,
//                                   ),
//                                   style: OutlinedButton.styleFrom(
//                                     minimumSize:
//                                         const Size(double.infinity, 52),
//                                     padding: const EdgeInsets.symmetric(
//                                         horizontal: 16, vertical: 12),
//                                     foregroundColor: AppColors.textBody,
//                                     backgroundColor: AppColors.surface,
//                                     side: const BorderSide(
//                                         color: AppColors.border),
//                                     shape: RoundedRectangleBorder(
//                                       borderRadius: BorderRadius.circular(
//                                           AppSizes.radiusMd),
//                                     ),
//                                   ),
//                                 ),
//                                 const SizedBox(height: 16),
//                                 Wrap(
//                                   alignment: WrapAlignment.center,
//                                   spacing: 16,
//                                   children: [
//                                     TextButton.icon(
//                                       onPressed: _loading
//                                           ? null
//                                           : () => Navigator.of(context)
//                                               .pushReplacementNamed(
//                                                   AppRoutes.publicJobs),
//                                       icon: const Icon(LucideIcons.briefcase,
//                                           size: 16),
//                                       label: const Text('Job Portal'),
//                                       style: TextButton.styleFrom(
//                                           minimumSize: const Size(0, 48),
//                                           foregroundColor: AppColors.textMuted),
//                                     ),
//                                     TextButton.icon(
//                                       onPressed: _loading
//                                           ? null
//                                           : () => Navigator.pushNamed(
//                                               context, AppRoutes.adminLogin),
//                                       icon: const Icon(LucideIcons.shieldCheck,
//                                           size: 16),
//                                       label: const Text('Admin Login'),
//                                       style: TextButton.styleFrom(
//                                           minimumSize: const Size(0, 48),
//                                           foregroundColor: AppColors.textMuted),
//                                     ),
//                                   ],
//                                 ),
//                                 const SizedBox(height: 16),
//                                 const DeveloperCredit(),
//                               ],
//                             ),
//                           ),
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               );
//             },
//           ),
//         ),
//       ),
//     );
//   }
// }



import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/constants.dart';
import '../../services/auth_service.dart';
import '../../routes.dart';
import 'otp_screen.dart';
import '../../widgets/developer_credit.dart';
 
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.useEmployeeId = false});
 
  final bool useEmployeeId;
 
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
 
class _LoginScreenState extends State<LoginScreen> {
  static const Color _headerIndigo = Color(0xFF6366F1);
  static const Color _referenceDeepIndigo = Color(0xFF3C2FE3);
  static const Color _referenceIndigo = Color(0xFF4638E5);
  static const Color _referenceBlueViolet = Color(0xFF5144E7);
  static const Color _referenceViolet = Color(0xFF675BE9);
  static const Color _referenceSoftViolet = Color(0xFF8176EA);
  static const Color _referenceLavenderViolet = Color(0xFF9B91F0);
 
 
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _employeeIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  late bool _useEmployeeId;
  bool _mobileLogin = false;
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;
 
  @override
  void initState() {
    super.initState();
    _useEmployeeId = widget.useEmployeeId;
  }
 
  @override
  void dispose() {
    _emailCtrl.dispose();
    _employeeIdCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }
 
  void _changeMethod({required bool mobile, bool employee = false}) {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    _formKey.currentState?.reset();
    _passwordCtrl.clear();
    setState(() {
      _mobileLogin = mobile;
      _useEmployeeId = employee;
      _obscurePassword = true;
      _error = null;
    });
  }
 
  Future<void> _login() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      final error = _useEmployeeId
          ? await auth.loginWithEmployeeId(
              _employeeIdCtrl.text.trim(), _passwordCtrl.text)
          : await auth.loginWithEmailPassword(
              _emailCtrl.text.trim(), _passwordCtrl.text);
      if (!mounted) return;
      if (error == null) {
        TextInput.finishAutofillContext();
        Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.dashboard, (_) => false);
      } else {
        setState(() => _error = error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Login failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
 
  Future<void> _sendOtp() async {
    if (_loading || !_formKey.currentState!.validate()) {
      return;
    }
    final phone = '+91${_phoneCtrl.text.trim()}';
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await context.read<AuthService>().sendOtp(
        phone,
        onVerified: () {
          if (!mounted || !_mobileLogin) return;
          Navigator.pushNamedAndRemoveUntil(
              context, AppRoutes.verifyGate, (_) => false);
        },
        onCodeSent: (verificationId) {
          if (!mounted ||
              !_mobileLogin ||
              ModalRoute.of(context)?.isCurrent != true) {
            return;
          }
          setState(() => _loading = false);
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppSizes.radiusXxl),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            builder: (_) => FractionallySizedBox(
              heightFactor: 0.9,
              child: OtpScreen(
                phone: phone,
                verificationId: verificationId,
                embedded: true,
              ),
            ),
          );
        },
        onError: (error) {
          if (!mounted || !_mobileLogin) return;
          setState(() {
            _loading = false;
            _error = error;
          });
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to send OTP. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
 
  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: AppColors.textLabel,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: const TextStyle(
          color: _referenceDeepIndigo,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Container(
          margin: const EdgeInsets.only(left: 10, right: 6),
          child: Icon(icon, size: 19, color: _referenceDeepIndigo),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 44, minHeight: 44),
        filled: true,
        fillColor: AppColors.surfaceElevated,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        errorMaxLines: 3,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          borderSide: const BorderSide(color: _referenceDeepIndigo, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      );
 
  Widget _buildForm() {
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_mobileLogin)
              TextFormField(
                key: const ValueKey('login-phone'),
                controller: _phoneCtrl,
                enabled: !_loading,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 10,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark),
                decoration: _decoration('Mobile number', LucideIcons.phone)
                    .copyWith(prefixText: '+91 ', counterText: ''),
                validator: (value) =>
                    RegExp(r'^\d{10}$').hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Enter a valid 10-digit mobile number',
                onFieldSubmitted: (_) => _sendOtp(),
              )
            else ...[
              TextFormField(
                key:
                    ValueKey(_useEmployeeId ? 'login-employee' : 'login-email'),
                controller: _useEmployeeId ? _employeeIdCtrl : _emailCtrl,
                enabled: !_loading,
                keyboardType: _useEmployeeId
                    ? TextInputType.text
                    : TextInputType.emailAddress,
                textCapitalization: _useEmployeeId
                    ? TextCapitalization.characters
                    : TextCapitalization.none,
                textInputAction: TextInputAction.next,
                autofillHints: [
                  _useEmployeeId ? AutofillHints.username : AutofillHints.email
                ],
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark),
                decoration: _decoration(
                  _useEmployeeId ? 'Employee ID' : 'Email address',
                  _useEmployeeId ? LucideIcons.user : LucideIcons.mail,
                ),
                validator: (value) {
                  final input = value?.trim() ?? '';
                  if (_useEmployeeId) {
                    return RegExp(r'^SHR-?(?:\d{4}|\d{6})$',
                                caseSensitive: false)
                            .hasMatch(input)
                        ? null
                        : 'Enter a valid Employee ID (e.g. SHR-4450)';
                  }
                  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(input)
                      ? null
                      : 'Enter a valid email address';
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('login-password'),
                controller: _passwordCtrl,
                enabled: !_loading,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark),
                decoration: _decoration('Password', LucideIcons.lock).copyWith(
                  suffixIcon: IconButton(
                    tooltip:
                        _obscurePassword ? 'Show password' : 'Hide password',
                    onPressed: _loading
                        ? null
                        : () => setState(
                            () => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                        _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
                        size: 20,
                        color: AppColors.textMuted),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your password'
                    : null,
                onFieldSubmitted: (_) => _login(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(LucideIcons.alertCircle,
                            size: 18, color: AppColors.errorDark),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppColors.errorDark,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              height: AppSizes.buttonHeightLg,
              padding: const EdgeInsets.fromLTRB(24, 6, 6, 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: _loading
                      ? [
                          _referenceDeepIndigo.withValues(alpha: 0.60),
                          _referenceViolet.withValues(alpha: 0.60),
                        ]
                      : const [
                          _referenceDeepIndigo,
                          _referenceBlueViolet,
                          _referenceViolet,
                        ],
                ),
                borderRadius: BorderRadius.circular(100), // full pill
                boxShadow: _loading
                    ? null
                    : [
                        BoxShadow(
                          color:
                              _referenceDeepIndigo.withValues(alpha: 0.30),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(100),
                  onTap: _loading
                      ? null
                      : _mobileLogin
                          ? _sendOtp
                          : _login,
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                    semanticsLabel: 'Signing in',
                                  ),
                                )
                              : Text(
                                  _mobileLogin ? 'Send OTP' : 'Sign in',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                        ),
                      ),
                      AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(
                              alpha: _loading ? 0.60 : 1.0,
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            color: _referenceDeepIndigo,
                            size: 26,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Exit App?'),
            content: const Text('Do you want to exit Sherize?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        if (shouldExit == true) SystemNavigator.pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _headerIndigo,
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 360;
              final headerHeight = isCompact ? 240.0 : 280.0;
              final logoSize = _mobileLogin
                  ? (isCompact ? 224.0 : 260.0)
                  : (isCompact ? 196.0 : 228.0);
 
              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    height: headerHeight,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _headerIndigo,
                          _referenceIndigo.withValues(alpha: 0.95),
                        ],
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        Positioned(
                          top: -70,
                          right: -50,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 10,
                          left: -70,
                          child: Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            SizedBox(height: isCompact ? 6 : 8),
                            Image.asset(
                              'assets/images/sherize_logo.png',
                              width: logoSize,
                              height: logoSize,
                              fit: BoxFit.contain,
                              semanticLabel: 'Sherize',
                            ),
                            if (!_mobileLogin)
                              Transform.translate(
                                offset: const Offset(0, -50),
                                child: Text(
                                  'Welcome back',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        fontSize: isCompact ? 24 : 27,
                                        letterSpacing: -0.5,
                                      ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppSizes.radiusXxl),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 20,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              isCompact
                                  ? AppSizes.base
                                  : AppSizes.screenPaddingH,
                              isCompact ? AppSizes.md : AppSizes.lg,
                              isCompact
                                  ? AppSizes.base
                                  : AppSizes.screenPaddingH,
                              AppSizes.xxl +
                                  MediaQuery.viewInsetsOf(context).bottom,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_mobileLogin) ...[
                                  const Text(
                                    'Mobile Login',
                                    style: TextStyle(
                                      color: AppColors.textDark,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                                if (!_mobileLogin) ...[
                                  SegmentedButton<bool>(
                                    segments: const [
                                      ButtonSegment(
                                          value: false,
                                          label: Text('Email'),
                                          icon: Icon(LucideIcons.mail,
                                              size: 16)),
                                      ButtonSegment(
                                          value: true,
                                          label: Text('Employee ID'),
                                          icon: Icon(LucideIcons.user,
                                              size: 16)),
                                    ],
                                    selected: {_useEmployeeId},
                                    showSelectedIcon: false,
                                    direction:
                                        MediaQuery.sizeOf(context).width <
                                                    360 ||
                                                MediaQuery.textScalerOf(context)
                                                        .scale(14) >
                                                    20
                                            ? Axis.vertical
                                            : Axis.horizontal,
                                    onSelectionChanged: _loading
                                        ? null
                                        : (selection) => _changeMethod(
                                            mobile: false,
                                            employee: selection.single),
                                    style: SegmentedButton.styleFrom(
                                      minimumSize: const Size(0, 50),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            AppSizes.radiusLg),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0,
                                      ),
                                      selectedBackgroundColor:
                                          _referenceLavenderViolet.withValues(
                                              alpha: 0.18),
                                      selectedForegroundColor:
                                          _referenceDeepIndigo,
                                      foregroundColor: AppColors.textBody,
                                      side: const BorderSide(
                                          color: AppColors.border),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                                _buildForm(),
                                if (_mobileLogin) const SizedBox(height: 24),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    const Expanded(
                                        child: Divider(
                                            color: AppColors.border,
                                            height: 1)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Text(
                                        'or',
                                        style: TextStyle(
                                          color: AppColors.textMuted
                                              .withValues(alpha: 0.9),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Expanded(
                                        child: Divider(
                                            color: AppColors.border,
                                            height: 1)),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                OutlinedButton.icon(
                                  onPressed: _loading
                                      ? null
                                      : () =>
                                          _changeMethod(mobile: !_mobileLogin),
                                  icon: Icon(
                                    _mobileLogin
                                        ? LucideIcons.mail
                                        : LucideIcons.smartphone,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _mobileLogin
                                        ? 'Login with email'
                                        : 'Login with mobile number',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize:
                                        const Size(double.infinity, 52),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    foregroundColor: _referenceDeepIndigo,
                                    backgroundColor: AppColors.surface,
                                    side: BorderSide(
                                        color: _referenceDeepIndigo
                                            .withValues(alpha: 0.35)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppSizes.radiusLg),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 16,
                                  children: [
                                    TextButton.icon(
                                      onPressed: _loading
                                          ? null
                                          : () => Navigator.of(context)
                                              .pushReplacementNamed(
                                                  AppRoutes.publicJobs),
                                      icon: const Icon(LucideIcons.briefcase,
                                          size: 16),
                                      label: const Text('Job Portal'),
                                      style: TextButton.styleFrom(
                                          minimumSize: const Size(0, 48),
                                          foregroundColor: AppColors.textMuted),
                                    ),
                                    TextButton.icon(
                                      onPressed: _loading
                                          ? null
                                          : () => Navigator.pushNamed(
                                              context, AppRoutes.adminLogin),
                                      icon: const Icon(LucideIcons.shieldCheck,
                                          size: 16),
                                      label: const Text('Admin Login'),
                                      style: TextButton.styleFrom(
                                          minimumSize: const Size(0, 48),
                                          foregroundColor: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const DeveloperCredit(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

