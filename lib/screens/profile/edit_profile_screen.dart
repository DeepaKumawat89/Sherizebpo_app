// import 'dart:convert';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_storage/firebase_storage.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:http/http.dart' as http;
// import 'package:image_picker/image_picker.dart';
// import 'package:lucide_icons/lucide_icons.dart';
// import 'package:intl/intl.dart';

// import '../../core/constants/constants.dart';
// import '../../core/theme/app_decorations.dart';
// import '../../core/utils/snackbar_utils.dart';
// import '../../widgets/custom_button.dart';
// import '../../widgets/custom_popup_menu.dart';

// class EditProfileScreen extends StatefulWidget {
//   const EditProfileScreen({Key? key}) : super(key: key);

//   @override
//   State<EditProfileScreen> createState() => _EditProfileScreenState();
// }

// class _EditProfileScreenState extends State<EditProfileScreen> {
//   final _formKey = GlobalKey<FormState>();

//   // Basic Info
//   final TextEditingController _nameController = TextEditingController();
//   final TextEditingController _emailController = TextEditingController();
//   final TextEditingController _phoneController = TextEditingController();
//   String? _gender;
//   DateTime? _dob;

//   // Address Fields
//   final TextEditingController _houseNumberController = TextEditingController();
//   final TextEditingController _areaController = TextEditingController();
//   final TextEditingController _landmarkController = TextEditingController();
//   final TextEditingController _cityController = TextEditingController();
//   final TextEditingController _stateController = TextEditingController();
//   final TextEditingController _pincodeController = TextEditingController();
//   bool _isFetchingPincode = false;

//   // Work Preferences
//   String? _language;
//   String? _education;
//   final TextEditingController _experienceController = TextEditingController();

//   // Equipment
//   bool _headsetAvailable = false;
//   String? _deviceType;
//   String? _internetType;

//   final ImagePicker _picker = ImagePicker();
//   XFile? _newProfileImage;
//   Uint8List? _newProfileBytes;
//   String? _existingProfileImageUrl;
//   bool _isLoading = true;
//   bool _isSaving = false;

//   // ── Options ────────────────────────────────────────────────────────
//   static const List<String> _genderOptions = ['Female', 'Male', 'Other'];
//   static const List<String> _educationOptions = [
//     'Uneducated',
//     'Below SSC',
//     'SSC',
//     'Intermediate',
//     'Graduation',
//     'Post Graduation',
//   ];

//   @override
//   void initState() {
//     super.initState();
//     _loadUserData();
//   }

//   @override
//   void dispose() {
//     _nameController.dispose();
//     _emailController.dispose();
//     _phoneController.dispose();
//     _houseNumberController.dispose();
//     _areaController.dispose();
//     _landmarkController.dispose();
//     _cityController.dispose();
//     _stateController.dispose();
//     _pincodeController.dispose();
//     _experienceController.dispose();
//     super.dispose();
//   }

//   Future<void> _loadUserData() async {
//     try {
//       final user = FirebaseAuth.instance.currentUser;
//       if (user == null) return;

//       final doc = await FirebaseFirestore.instance
//           .collection('users')
//           .doc(user.uid)
//           .get();
//       if (doc.exists && mounted) {
//         final data = doc.data()!;
//         _nameController.text = data['fullName'] ?? data['name'] ?? '';
//         _emailController.text = data['email'] ?? user.email ?? '';
//         _phoneController.text =
//             data['phone'] ?? data['phoneNumber'] ?? user.phoneNumber ?? '';

//         final savedGender = data['gender'] as String?;
//         _gender = _genderOptions.contains(savedGender) ? savedGender : null;

//         if (data['dateOfBirth'] != null) {
//           try {
//             _dob = DateFormat('yyyy-MM-dd').parse(data['dateOfBirth']);
//           } catch (_) {}
//         }

//         _houseNumberController.text = data['houseNumber'] ?? '';
//         _areaController.text = data['area'] ?? '';
//         _landmarkController.text = data['landmark'] ?? '';
//         _cityController.text = data['city'] ?? '';
//         _stateController.text = data['state'] ?? '';
//         _pincodeController.text = data['pincode'] ?? '';

//         _language = data['language'];

//         final savedEdu = data['education'] as String?;
//         _education = _educationOptions.contains(savedEdu) ? savedEdu : null;

//         _experienceController.text = data['experience'] ?? '';
//         _headsetAvailable = data['headsetAvailable'] == 'Yes';
//         _deviceType = data['deviceType'];
//         _internetType = data['internetType'];
//         _existingProfileImageUrl = data['profileImage'] ??
//             data['profileImageUrl'] ??
//             data['avatar_url'];
//       }
//     } catch (e) {
//       if (mounted) {
//         SnackBarUtils.showError('Error loading profile: $e');
//       }
//     } finally {
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }

//   Future<void> _fetchPincodeData(String pincode) async {
//     if (pincode.length != 6) return;
//     setState(() => _isFetchingPincode = true);
//     try {
//       final response = await http
//           .get(Uri.parse('https://api.postalpincode.in/pincode/$pincode'))
//           .timeout(const Duration(seconds: 8));

//       if (response.statusCode == 200) {
//         final List data = json.decode(response.body);
//         if (data.isNotEmpty && data[0]['Status'] == 'Success') {
//           final postOffices = data[0]['PostOffice'] as List;
//           if (postOffices.isNotEmpty) {
//             final po = postOffices[0];
//             setState(() {
//               _cityController.text = po['District'] ?? po['Name'] ?? '';
//               _stateController.text = po['State'] ?? '';
//             });
//           }
//         } else {
//           if (mounted) {
//             SnackBarUtils.showError('Invalid pincode — no location found');
//           }
//         }
//       }
//     } catch (e) {
//       if (mounted) {
//         SnackBarUtils.showError('Could not fetch location. Check your connection.');
//       }
//     } finally {
//       if (mounted) setState(() => _isFetchingPincode = false);
//     }
//   }

//   Future<void> _pickImage() async {
//     try {
//       final XFile? image = await _picker.pickImage(
//           source: ImageSource.gallery,
//           maxWidth: 512,
//           maxHeight: 512,
//           imageQuality: 85);
//       if (image != null && mounted) {
//         final bytes = await image.readAsBytes();
//         setState(() {
//           _newProfileImage = image;
//           _newProfileBytes = bytes;
//         });
//       }
//     } catch (e) {
//       if (mounted) {
//         SnackBarUtils.showError('Failed to pick image: $e');
//       }
//     }
//   }

//   Future<void> _selectDate(BuildContext context) async {
//     final DateTime maxDate =
//         DateTime.now().subtract(const Duration(days: 18 * 365));
//     final DateTime? picked = await showDatePicker(
//       context: context,
//       initialDate: _dob ?? maxDate,
//       firstDate: DateTime(1950),
//       lastDate: maxDate,
//     );
//     if (picked != null && picked != _dob) {
//       setState(() => _dob = picked);
//     }
//   }

//   Future<void> _saveProfile() async {
//     if (!_formKey.currentState!.validate()) {
//       SnackBarUtils.showInfo('Please correct the highlighted errors before saving.');
//       return;
//     }

//     if (_dob != null) {
//       final age = _ageFromDob(_dob!);
//       if (age < 18) {
//         SnackBarUtils.showInfo('You must be at least 18 years old.');
//         return;
//       }
//     }

//     final user = FirebaseAuth.instance.currentUser;
//     if (user == null) return;

//     setState(() => _isSaving = true);

//     try {
//       String? newImageUrl = _existingProfileImageUrl;
//       if (_newProfileImage != null) {
//         final storageRef = FirebaseStorage.instance
//             .ref()
//             .child('profile/${user.uid}/profile.jpg');
//         final bytes = await _newProfileImage!.readAsBytes();
//         final metadata = SettableMetadata(contentType: 'image/jpeg');
//         final uploadTask = await storageRef.putData(bytes, metadata);
//         newImageUrl = await uploadTask.ref.getDownloadURL();
//       }

//       final Map<String, dynamic> updateData = {
//         'fullName': _nameController.text.trim(),
//         'email': _emailController.text.trim(),
//         'phone': _phoneController.text.trim(),
//         'gender': _gender,
//         'dateOfBirth':
//             _dob != null ? DateFormat('yyyy-MM-dd').format(_dob!) : null,
//         'houseNumber': _houseNumberController.text.trim(),
//         'area': _areaController.text.trim(),
//         'landmark': _landmarkController.text.trim(),
//         'city': _cityController.text.trim(),
//         'state': _stateController.text.trim(),
//         'pincode': _pincodeController.text.trim(),
//         'language': _language,
//         'education': _education,
//         'experience': _experienceController.text.trim(),
//         'headsetAvailable': _headsetAvailable ? 'Yes' : 'No',
//         'deviceType': _deviceType,
//         'internetType': _internetType,
//         if (newImageUrl != null && newImageUrl.isNotEmpty)
//           'profileImage': newImageUrl,
//         'updatedAt': FieldValue.serverTimestamp(),
//       };

//       await FirebaseFirestore.instance
//           .collection('users')
//           .doc(user.uid)
//           .set(updateData, SetOptions(merge: true))
//           .timeout(const Duration(seconds: 10), onTimeout: () {
//             throw Exception('Network timeout. Please check your connection.');
//           });

//       if (!mounted) return;
//       SnackBarUtils.showSuccess('Profile updated successfully');
//       Navigator.pop(context);
//     } catch (e) {
//       if (!mounted) return;
//       SnackBarUtils.showError('Failed to save profile: $e');
//     } finally {
//       if (mounted) setState(() => _isSaving = false);
//     }
//   }

//   int _ageFromDob(DateTime dob) {
//     final today = DateTime.now();
//     int age = today.year - dob.year;
//     if (today.month < dob.month ||
//         (today.month == dob.month && today.day < dob.day)) {
//       age--;
//     }
//     return age;
//   }

//   Widget _buildSectionHeader(String title) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     IconData icon;
//     String subtitle;
//     switch (title) {
//       case 'Basic Information':
//         icon = LucideIcons.user;
//         subtitle = 'Your personal and contact details';
//         break;
//       case 'Address Information':
//         icon = LucideIcons.mapPin;
//         subtitle = 'Your current residential address';
//         break;
//       case 'Work Preferences':
//         icon = LucideIcons.briefcase;
//         subtitle = 'Language, education and experience';
//         break;
//       default:
//         icon = LucideIcons.headphones;
//         subtitle = 'Devices and connectivity available to you';
//     }

//     return Padding(
//       padding: const EdgeInsets.only(top: AppSizes.xxl, bottom: AppSizes.base),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Container(
//             width: 42,
//             height: 42,
//             decoration: BoxDecoration(
//               color: isDark
//                   ? AppColors.primary.withValues(alpha: 0.14)
//                   : AppColors.primarySoft,
//               borderRadius: BorderRadius.circular(AppSizes.radiusMd),
//             ),
//             child: Icon(icon, size: 19, color: AppColors.primary),
//           ),
//           const SizedBox(width: AppSizes.md),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   title,
//                   style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                         color: isDark ? Colors.white : AppColors.textDark,
//                         fontSize: 17,
//                         fontWeight: FontWeight.w800,
//                         letterSpacing: -0.2,
//                       ),
//                 ),
//                 const SizedBox(height: AppSizes.xs),
//                 Text(
//                   subtitle,
//                   style: Theme.of(context).textTheme.bodySmall?.copyWith(
//                         color:
//                             isDark ? Colors.white54 : AppColors.textMuted,
//                         height: 1.3,
//                       ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   InputDecoration _buildInputDecoration(BuildContext context, String label, IconData icon,
//       {Widget? suffix}) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     final borderColor =
//         isDark ? Colors.white.withValues(alpha: 0.10) : AppColors.border;
//     return InputDecoration(
//       labelText: label,
//       labelStyle: TextStyle(
//           color: isDark ? Colors.white70 : AppColors.textLabel,
//           fontSize: 13,
//           fontWeight: FontWeight.w600),
//       floatingLabelStyle: const TextStyle(
//         color: AppColors.primary,
//         fontSize: 13,
//         fontWeight: FontWeight.w700,
//       ),
//       prefixIcon: Icon(
//         icon,
//         size: 19,
//         color: isDark ? AppColors.primaryLight : AppColors.primary,
//       ),
//       suffixIcon: suffix,
//       filled: true,
//       fillColor: isDark
//           ? Colors.white.withValues(alpha: 0.04)
//           : AppColors.surfaceElevated,
//       contentPadding: const EdgeInsets.symmetric(
//           horizontal: AppSizes.base, vertical: AppSizes.base),
//       border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           borderSide: BorderSide(color: borderColor)),
//       enabledBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           borderSide: BorderSide(color: borderColor)),
//       disabledBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           borderSide: BorderSide(color: borderColor.withValues(alpha: 0.7))),
//       focusedBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           borderSide:
//               const BorderSide(color: AppColors.primary, width: 1.5)),
//       errorBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           borderSide: const BorderSide(color: AppColors.error)),
//       focusedErrorBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
//     );
//   }

//   Widget _buildAvatarFallback() {
//     final initial = _nameController.text.trim().isNotEmpty
//         ? _nameController.text.trim().characters.first.toUpperCase()
//         : 'U';
//     return DecoratedBox(
//       decoration: const BoxDecoration(
//         gradient: AppDecorations.primaryLightGradient,
//       ),
//       child: Center(
//         child: Text(
//           initial,
//           style: const TextStyle(
//             color: Colors.white,
//             fontSize: 32,
//             fontWeight: FontWeight.w800,
//           ),
//         ),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     final horizontalPadding = MediaQuery.sizeOf(context).width < 360
//         ? AppSizes.base
//         : AppSizes.screenPaddingH;

//     return Scaffold(
//       resizeToAvoidBottomInset: true,
//       backgroundColor: Theme.of(context).scaffoldBackgroundColor,
//       appBar: AppBar(
//         title: const Text('Edit Profile'),
//         backgroundColor: Colors.white,
//         foregroundColor: AppColors.textDark,
//         toolbarHeight: 72,
//         elevation: 0,
//         scrolledUnderElevation: 0,
//         centerTitle: false,
//         titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
//           color: AppColors.textDark,
//           fontSize: 20,
//           fontWeight: FontWeight.w600,
//           letterSpacing: 0,
//         ),
//         iconTheme: const IconThemeData(color: AppColors.textDark),
//       ),
//       body: _isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : SafeArea(
//               top: false,
//               child: SingleChildScrollView(
//                 keyboardDismissBehavior:
//                     ScrollViewKeyboardDismissBehavior.onDrag,
//                 padding: EdgeInsets.fromLTRB(
//                   horizontalPadding,
//                   AppSizes.lg,
//                   horizontalPadding,
//                   AppSizes.xxl + MediaQuery.viewInsetsOf(context).bottom,
//                 ),
//                 child: Form(
//                 key: _formKey,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.stretch,
//                   children: [
//                     // ── Profile Photo ─────────────────────────────
//                     Container(
//                       padding: const EdgeInsets.all(AppSizes.xl),
//                       decoration: BoxDecoration(
//                         gradient: isDark
//                             ? AppDecorations.darkGradient
//                             : AppDecorations.primaryGradient,
//                         borderRadius:
//                             BorderRadius.circular(AppSizes.radiusXl),
//                         boxShadow: isDark
//                             ? null
//                             : AppDecorations.primaryShadow(alpha: 0.18),
//                       ),
//                       child: LayoutBuilder(
//                         builder: (context, constraints) {
//                           final compact = constraints.maxWidth < 300;
//                           final avatar = Semantics(
//                             button: true,
//                             label: 'Change profile photo',
//                             child: GestureDetector(
//                               behavior: HitTestBehavior.opaque,
//                               onTap: _isSaving ? null : _pickImage,
//                               child: Stack(
//                                 clipBehavior: Clip.none,
//                                 children: [
//                                   Container(
//                                     width: AppSizes.avatarXl,
//                                     height: AppSizes.avatarXl,
//                                     padding:
//                                         const EdgeInsets.all(AppSizes.xs),
//                                     decoration: BoxDecoration(
//                                       color: Colors.white,
//                                       shape: BoxShape.circle,
//                                       boxShadow: [
//                                         BoxShadow(
//                                           color: AppColors.secondary
//                                               .withValues(alpha: 0.20),
//                                           blurRadius: 20,
//                                           offset: const Offset(0, 8),
//                                         ),
//                                       ],
//                                     ),
//                                     child: ClipOval(
//                                       child: _newProfileBytes != null
//                                           ? Image.memory(
//                                               _newProfileBytes!,
//                                               fit: BoxFit.cover,
//                                             )
//                                           : (_existingProfileImageUrl != null &&
//                                                   _existingProfileImageUrl!
//                                                       .isNotEmpty)
//                                               ? Image.network(
//                                                   _existingProfileImageUrl!,
//                                                   fit: BoxFit.cover,
//                                                   errorBuilder: (_, __, ___) =>
//                                                       _buildAvatarFallback(),
//                                                 )
//                                               : _buildAvatarFallback(),
//                                     ),
//                                   ),
//                                   Positioned(
//                                     right: -2,
//                                     bottom: 2,
//                                     child: Container(
//                                       width: 36,
//                                       height: 36,
//                                       decoration: BoxDecoration(
//                                         color: AppColors.primary,
//                                         shape: BoxShape.circle,
//                                         border: Border.all(
//                                           color: Colors.white,
//                                           width: 3,
//                                         ),
//                                         boxShadow: [
//                                           BoxShadow(
//                                             color: AppColors.secondary
//                                                 .withValues(alpha: 0.18),
//                                             blurRadius: 8,
//                                             offset: const Offset(0, 3),
//                                           ),
//                                         ],
//                                       ),
//                                       child: const Icon(
//                                         LucideIcons.camera,
//                                         color: Colors.white,
//                                         size: 16,
//                                       ),
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           );
//                           final details = Column(
//                             crossAxisAlignment: compact
//                                 ? CrossAxisAlignment.center
//                                 : CrossAxisAlignment.start,
//                             children: [
//                               Text(
//                                 'Profile photo',
//                                 textAlign:
//                                     compact ? TextAlign.center : TextAlign.left,
//                                 style: Theme.of(context)
//                                     .textTheme
//                                     .titleLarge
//                                     ?.copyWith(
//                                       color: Colors.white,
//                                       fontSize: 20,
//                                       fontWeight: FontWeight.w800,
//                                       letterSpacing: -0.3,
//                                     ),
//                               ),
//                               const SizedBox(height: AppSizes.xs),
//                               Text(
//                                 'Add a clear photo so your profile is easy to recognise.',
//                                 textAlign:
//                                     compact ? TextAlign.center : TextAlign.left,
//                                 style: Theme.of(context)
//                                     .textTheme
//                                     .bodySmall
//                                     ?.copyWith(
//                                       color: Colors.white70,
//                                       height: 1.4,
//                                     ),
//                               ),
//                               const SizedBox(height: AppSizes.md),
//                               GestureDetector(
//                                 behavior: HitTestBehavior.opaque,
//                                 onTap: _isSaving ? null : _pickImage,
//                                 child: Container(
//                                   padding: const EdgeInsets.symmetric(
//                                     horizontal: AppSizes.md,
//                                     vertical: AppSizes.sm,
//                                   ),
//                                   decoration: BoxDecoration(
//                                     color: Colors.white.withValues(alpha: 0.14),
//                                     borderRadius: BorderRadius.circular(
//                                       AppSizes.radiusRound,
//                                     ),
//                                     border: Border.all(
//                                       color: Colors.white
//                                           .withValues(alpha: 0.20),
//                                     ),
//                                   ),
//                                   child: const Row(
//                                     mainAxisSize: MainAxisSize.min,
//                                     children: [
//                                       Icon(
//                                         LucideIcons.image,
//                                         size: 15,
//                                         color: Colors.white,
//                                       ),
//                                       SizedBox(width: AppSizes.sm),
//                                       Text(
//                                         'Choose photo',
//                                         style: TextStyle(
//                                           color: Colors.white,
//                                           fontSize: 13,
//                                           fontWeight: FontWeight.w700,
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           );

//                           if (compact) {
//                             return Column(
//                               children: [
//                                 avatar,
//                                 const SizedBox(height: AppSizes.lg),
//                                 details,
//                               ],
//                             );
//                           }
//                           return Row(
//                             children: [
//                               avatar,
//                               const SizedBox(width: AppSizes.lg),
//                               Expanded(child: details),
//                             ],
//                           );
//                         },
//                       ),
//                     ),

//                     // ── Basic Information ─────────────────────────
//                     _buildSectionHeader('Basic Information'),
//                     CustomTextField(
//                       controller: _nameController,
//                       label: 'Full Name',
//                       hintText: 'Enter your full name',
//                       prefixIcon: LucideIcons.user,
//                       readOnly: _isSaving,
//                       validator: (value) {
//                         if (value == null || value.trim().isEmpty) {
//                           return 'Please enter your name';
//                         }
//                         return null;
//                       },
//                     ),
//                     const SizedBox(height: AppSizes.md),
//                     CustomTextField(
//                       controller: _emailController,
//                       label: 'Email Address',
//                       hintText: 'Enter your email',
//                       prefixIcon: LucideIcons.mail,
//                       keyboardType: TextInputType.emailAddress,
//                       readOnly: _isSaving,
//                       validator: (value) {
//                         if (value == null || value.trim().isEmpty) {
//                           return null; // Optional
//                         }
//                         final emailRegex =
//                             RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
//                         if (!emailRegex.hasMatch(value)) {
//                           return 'Enter a valid email address';
//                         }
//                         return null;
//                       },
//                     ),
//                     const SizedBox(height: AppSizes.md),
//                     CustomTextField(
//                       controller: _phoneController,
//                       label: 'Phone Number',
//                       hintText: 'Enter your phone number',
//                       prefixIcon: LucideIcons.phone,
//                       keyboardType: TextInputType.phone,
//                       readOnly: _isSaving,
//                       validator: (value) {
//                         if (value == null || value.trim().isEmpty) {
//                           return null; // Optional
//                         }
//                         if (value.length < 10) {
//                           return 'Phone number must be at least 10 digits';
//                         }
//                         return null;
//                       },
//                     ),
//                     const SizedBox(height: AppSizes.md),

//                     CustomPopupMenuFormField<String>(
//                       initialValue: _gender,
//                       decoration:
//                           _buildInputDecoration(context, 'Gender', LucideIcons.users),
//                       style: Theme.of(context).textTheme.bodyMedium?.copyWith(
//                           color: isDark ? Colors.white : AppColors.textDark,
//                           fontSize: 14),
//                       items: _genderOptions
//                           .map((value) => CustomPopupMenuItem(
//                                 value: value,
//                                 label: value,
//                               ))
//                           .toList(),
//                       onChanged: _isSaving
//                           ? null
//                           : (value) => setState(() => _gender = value),
//                     ),
//                     const SizedBox(height: AppSizes.md),

//                     GestureDetector(
//                       onTap: () =>
//                           _isSaving ? null : _selectDate(context),
//                       child: AbsorbPointer(
//                         child: CustomTextField(
//                           label: 'Date of Birth',
//                           hintText: _dob == null
//                               ? 'Select Date (must be 18+)'
//                               : DateFormat('dd MMM yyyy').format(_dob!),
//                           prefixIcon: LucideIcons.calendar,
//                           readOnly: true,
//                           validator: (_) {
//                             if (_dob == null) return null; // Optional
//                             if (_ageFromDob(_dob!) < 18) {
//                               return 'You must be at least 18 years old';
//                             }
//                             return null;
//                           },
//                         ),
//                       ),
//                     ),

//                     // ── Contact / Address Information ─────────────
//                     _buildSectionHeader('Address Information'),
//                     CustomTextField(
//                       controller: _houseNumberController,
//                       label: 'House Number',
//                       hintText: 'Flat / House / Plot No.',
//                       prefixIcon: LucideIcons.home,
//                       readOnly: _isSaving,
//                     ),
//                     const SizedBox(height: AppSizes.md),
//                     CustomTextField(
//                       controller: _areaController,
//                       label: 'Area / Street',
//                       hintText: 'Colony, Street, Locality',
//                       prefixIcon: LucideIcons.mapPin,
//                       readOnly: _isSaving,
//                     ),
//                     const SizedBox(height: AppSizes.md),
//                     CustomTextField(
//                       controller: _landmarkController,
//                       label: 'Landmark',
//                       hintText: 'Near school, temple, etc.',
//                       prefixIcon: LucideIcons.landmark,
//                       readOnly: _isSaving,
//                     ),
//                     const SizedBox(height: AppSizes.md),

//                     TextFormField(
//                       controller: _pincodeController,
//                       keyboardType: TextInputType.number,
//                       maxLength: 6,
//                       inputFormatters: [
//                         FilteringTextInputFormatter.digitsOnly
//                       ],
//                       enabled: !_isSaving,
//                       onChanged: (value) {
//                         if (value.length == 6) {
//                           _fetchPincodeData(value);
//                         }
//                       },
//                       decoration: _buildInputDecoration(
//                         context,
//                         'Pincode',
//                         LucideIcons.hash,
//                         suffix: _isFetchingPincode
//                             ? Padding(
//                                 padding: const EdgeInsets.all(12),
//                                 child: SizedBox(
//                                   width: 16,
//                                   height: 16,
//                                   child: CircularProgressIndicator(
//                                       strokeWidth: 2,
//                                       color: Theme.of(context).primaryColor),
//                                 ),
//                               )
//                             : null,
//                       ).copyWith(counterText: ''),
//                       style: Theme.of(context).textTheme.bodyMedium?.copyWith(
//                           color: isDark ? Colors.white : AppColors.textDark, fontSize: 14),
//                     ),
//                     const SizedBox(height: AppSizes.md),

//                     LayoutBuilder(
//                       builder: (context, constraints) {
//                         final city = CustomTextField(
//                           controller: _cityController,
//                           label: 'City',
//                           hintText: 'Auto-filled',
//                           prefixIcon: LucideIcons.mapPin,
//                           readOnly: _isSaving,
//                         );
//                         final state = CustomTextField(
//                           controller: _stateController,
//                           label: 'State',
//                           hintText: 'Auto-filled',
//                           prefixIcon: LucideIcons.map,
//                           readOnly: _isSaving,
//                         );
//                         if (constraints.maxWidth < 340) {
//                           return Column(
//                             children: [
//                               city,
//                               const SizedBox(height: AppSizes.md),
//                               state,
//                             ],
//                           );
//                         }
//                         return Row(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Expanded(child: city),
//                             const SizedBox(width: AppSizes.md),
//                             Expanded(child: state),
//                           ],
//                         );
//                       },
//                     ),

//                     // ── Work Preferences ──────────────────────────
//                     _buildSectionHeader('Work Preferences'),
//                     CustomPopupMenuFormField<String>(
//                       initialValue: _language,
//                       decoration: _buildInputDecoration(
//                           context, 'Preferred Language', LucideIcons.languages),
//                       style: Theme.of(context).textTheme.bodyMedium?.copyWith(
//                           color: isDark ? Colors.white : AppColors.textDark, fontSize: 14),
//                       items: [
//                         'English',
//                         'Hindi',
//                         'Telugu',
//                         'Tamil',
//                         'Kannada',
//                         'Malayalam'
//                       ].map((String value) {
//                         return CustomPopupMenuItem<String>(
//                           value: value,
//                           label: value,
//                         );
//                       }).toList(),
//                       onChanged: _isSaving
//                           ? null
//                           : (value) =>
//                               setState(() => _language = value),
//                     ),
//                     const SizedBox(height: AppSizes.md),

//                     CustomPopupMenuFormField<String>(
//                       initialValue: _education,
//                       decoration: _buildInputDecoration(
//                           context, 'Education Level', LucideIcons.graduationCap),
//                       style: Theme.of(context).textTheme.bodyMedium?.copyWith(
//                           color: isDark ? Colors.white : AppColors.textDark, fontSize: 14),
//                       items: _educationOptions.map((String value) {
//                         return CustomPopupMenuItem<String>(
//                           value: value,
//                           label: value,
//                         );
//                       }).toList(),
//                       onChanged: _isSaving
//                           ? null
//                           : (value) =>
//                               setState(() => _education = value),
//                     ),
//                     const SizedBox(height: AppSizes.md),
//                     CustomTextField(
//                       controller: _experienceController,
//                       label: 'Work Experience',
//                       hintText: 'e.g. 2 years in BPO',
//                       prefixIcon: LucideIcons.briefcase,
//                       readOnly: _isSaving,
//                     ),

//                     // ── Equipment Details ─────────────────────────
//                     _buildSectionHeader('Equipment Details'),
//                     Container(
//                       margin: const EdgeInsets.only(bottom: AppSizes.md),
//                       decoration: BoxDecoration(
//                         color: isDark
//                             ? Colors.white.withValues(alpha: 0.04)
//                             : AppColors.surfaceElevated,
//                         borderRadius:
//                             BorderRadius.circular(AppSizes.radiusLg),
//                         border: Border.all(
//                           color: isDark
//                               ? Colors.white.withValues(alpha: 0.10)
//                               : AppColors.border,
//                         ),
//                       ),
//                       child: SwitchListTile(
//                         contentPadding: const EdgeInsets.symmetric(
//                           horizontal: AppSizes.base,
//                           vertical: AppSizes.xs,
//                         ),
//                         secondary: Icon(
//                           LucideIcons.headphones,
//                           size: 19,
//                           color: isDark
//                               ? AppColors.primaryLight
//                               : AppColors.primary,
//                         ),
//                         title: Text(
//                           'Headset Available',
//                           style:
//                               Theme.of(context).textTheme.bodyMedium?.copyWith(
//                                     color: isDark
//                                         ? Colors.white
//                                         : AppColors.textDark,
//                                     fontSize: 15,
//                                     fontWeight: FontWeight.w700,
//                                   ),
//                         ),
//                         subtitle: Text(
//                           _headsetAvailable ? 'Available' : 'Not available',
//                           style:
//                               Theme.of(context).textTheme.bodySmall?.copyWith(
//                                     color: isDark
//                                         ? Colors.white54
//                                         : AppColors.textMuted,
//                                   ),
//                         ),
//                         value: _headsetAvailable,
//                         activeThumbColor: AppColors.primary,
//                         onChanged: _isSaving
//                             ? null
//                             : (value) =>
//                                 setState(() => _headsetAvailable = value),
//                       ),
//                     ),
//                     CustomPopupMenuFormField<String>(
//                       initialValue: _deviceType,
//                       decoration: _buildInputDecoration(
//                           context, 'Device Type', LucideIcons.smartphone),
//                       style: Theme.of(context).textTheme.bodyMedium?.copyWith(
//                           color: isDark ? Colors.white : AppColors.textDark, fontSize: 14),
//                       items: ['Android', 'iPhone', 'Laptop', 'Desktop']
//                           .map((String value) {
//                         return CustomPopupMenuItem<String>(
//                           value: value,
//                           label: value,
//                         );
//                       }).toList(),
//                       onChanged: _isSaving
//                           ? null
//                           : (value) =>
//                               setState(() => _deviceType = value),
//                     ),
//                     const SizedBox(height: AppSizes.md),
//                     CustomPopupMenuFormField<String>(
//                       initialValue: _internetType,
//                       decoration: _buildInputDecoration(
//                           context, 'Internet Type', LucideIcons.wifi),
//                       style: Theme.of(context).textTheme.bodyMedium?.copyWith(
//                           color: isDark ? Colors.white : AppColors.textDark, fontSize: 14),
//                       items: ['WiFi', 'Mobile Data', 'Broadband']
//                           .map((String value) {
//                         return CustomPopupMenuItem<String>(
//                           value: value,
//                           label: value,
//                         );
//                       }).toList(),
//                       onChanged: _isSaving
//                           ? null
//                           : (value) =>
//                               setState(() => _internetType = value),
//                     ),
//                     const SizedBox(height: AppSizes.xxxl),

//                     Container(
//                       padding: const EdgeInsets.all(AppSizes.xs),
//                       decoration: BoxDecoration(
//                         color: Theme.of(context).cardColor,
//                         borderRadius:
//                             BorderRadius.circular(AppSizes.radiusLg),
//                         boxShadow: isDark ? null : AppDecorations.shadowSm,
//                       ),
//                       child: CustomButton(
//                         label: 'Save Profile Changes',
//                         icon: LucideIcons.checkCircle,
//                         isLoading: _isSaving,
//                         isDisabled: _isSaving,
//                         height: AppSizes.buttonHeightLg,
//                         fontSize: 16,
//                         onPressed: _saveProfile,
//                       ),
//                     ),
//                     const SizedBox(height: AppSizes.xxl),
//                   ],
//                 ),
//                 ),
//               ),
//             ),
//     );
//   }
// }

// /// Screen-local field styling keeps the Edit Profile redesign isolated from
// /// every other form in the application.
// class CustomTextField extends StatelessWidget {
//   const CustomTextField({
//     super.key,
//     this.controller,
//     required this.label,
//     required this.hintText,
//     this.prefixIcon,
//     this.keyboardType = TextInputType.text,
//     this.readOnly = false,
//     this.validator,
//   });

//   final TextEditingController? controller;
//   final String label;
//   final String hintText;
//   final IconData? prefixIcon;
//   final TextInputType keyboardType;
//   final bool readOnly;
//   final FormFieldValidator<String>? validator;

//   @override
//   Widget build(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     final borderColor =
//         isDark ? Colors.white.withValues(alpha: 0.10) : AppColors.border;

//     OutlineInputBorder border(Color color, {double width = 1}) {
//       return OutlineInputBorder(
//         borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//         borderSide: BorderSide(color: color, width: width),
//       );
//     }

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Text(
//           label,
//           style: Theme.of(context).textTheme.labelMedium?.copyWith(
//                 color: isDark ? Colors.white70 : AppColors.textLabel,
//                 fontSize: 13,
//                 fontWeight: FontWeight.w700,
//                 letterSpacing: 0.1,
//               ),
//         ),
//         const SizedBox(height: AppSizes.sm),
//         TextFormField(
//           controller: controller,
//           keyboardType: keyboardType,
//           readOnly: readOnly,
//           validator: validator,
//           style: Theme.of(context).textTheme.bodyMedium?.copyWith(
//                 color: isDark ? Colors.white : AppColors.textDark,
//                 fontSize: 15,
//                 fontWeight: FontWeight.w600,
//               ),
//           decoration: InputDecoration(
//             hintText: hintText,
//             hintStyle: TextStyle(
//               color: isDark ? Colors.white30 : AppColors.textPlaceholder,
//               fontSize: 14,
//               fontWeight: FontWeight.w400,
//             ),
//             prefixIcon: prefixIcon == null
//                 ? null
//                 : Icon(
//                     prefixIcon,
//                     size: 19,
//                     color:
//                         isDark ? AppColors.primaryLight : AppColors.primary,
//                   ),
//             filled: true,
//             fillColor: isDark
//                 ? Colors.white.withValues(alpha: 0.04)
//                 : AppColors.surfaceElevated,
//             contentPadding: const EdgeInsets.symmetric(
//               horizontal: AppSizes.base,
//               vertical: AppSizes.base,
//             ),
//             border: border(borderColor),
//             enabledBorder: border(borderColor),
//             focusedBorder: border(AppColors.primary, width: 1.5),
//             errorBorder: border(AppColors.error),
//             focusedErrorBorder: border(AppColors.error, width: 1.5),
//             errorStyle: const TextStyle(
//               color: AppColors.error,
//               fontSize: 12,
//               fontWeight: FontWeight.w500,
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }



import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
 
import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_popup_menu.dart';
 
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);
 
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}
 
class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
 
  // Basic Info
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String? _gender;
  DateTime? _dob;
 
  // Address Fields
  final TextEditingController _houseNumberController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _pincodeController = TextEditingController();
  bool _isFetchingPincode = false;
 
  // Work Preferences
  String? _language;
  String? _education;
  final TextEditingController _experienceController = TextEditingController();
 
  // Equipment
  bool _headsetAvailable = false;
  String? _deviceType;
  String? _internetType;
 
  final ImagePicker _picker = ImagePicker();
  XFile? _newProfileImage;
  Uint8List? _newProfileBytes;
  String? _existingProfileImageUrl;
  bool _isLoading = true;
  bool _isSaving = false;
 
  // ── Options ────────────────────────────────────────────────────────
  static const List<String> _genderOptions = ['Female', 'Male', 'Other'];
  static const List<String> _educationOptions = [
    'Uneducated',
    'Below SSC',
    'SSC',
    'Intermediate',
    'Graduation',
    'Post Graduation',
  ];
 
  @override
  void initState() {
    super.initState();
    _loadUserData();
  }
 
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _houseNumberController.dispose();
    _areaController.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _experienceController.dispose();
    super.dispose();
  }
 
  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
 
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        _nameController.text = data['fullName'] ?? data['name'] ?? '';
        _emailController.text = data['email'] ?? user.email ?? '';
        _phoneController.text =
            data['phone'] ?? data['phoneNumber'] ?? user.phoneNumber ?? '';
 
        final savedGender = data['gender'] as String?;
        _gender = _genderOptions.contains(savedGender) ? savedGender : null;
 
        if (data['dateOfBirth'] != null) {
          try {
            _dob = DateFormat('yyyy-MM-dd').parse(data['dateOfBirth']);
          } catch (_) {}
        }
 
        _houseNumberController.text = data['houseNumber'] ?? '';
        _areaController.text = data['area'] ?? '';
        _landmarkController.text = data['landmark'] ?? '';
        _cityController.text = data['city'] ?? '';
        _stateController.text = data['state'] ?? '';
        _pincodeController.text = data['pincode'] ?? '';
 
        _language = data['language'];
 
        final savedEdu = data['education'] as String?;
        _education = _educationOptions.contains(savedEdu) ? savedEdu : null;
 
        _experienceController.text = data['experience'] ?? '';
        _headsetAvailable = data['headsetAvailable'] == 'Yes';
        _deviceType = data['deviceType'];
        _internetType = data['internetType'];
        _existingProfileImageUrl = data['profileImage'] ??
            data['profileImageUrl'] ??
            data['avatar_url'];
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError('Error loading profile: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
 
  Future<void> _fetchPincodeData(String pincode) async {
    if (pincode.length != 6) return;
    setState(() => _isFetchingPincode = true);
    try {
      final response = await http
          .get(Uri.parse('https://api.postalpincode.in/pincode/$pincode'))
          .timeout(const Duration(seconds: 8));
 
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty && data[0]['Status'] == 'Success') {
          final postOffices = data[0]['PostOffice'] as List;
          if (postOffices.isNotEmpty) {
            final po = postOffices[0];
            setState(() {
              _cityController.text = po['District'] ?? po['Name'] ?? '';
              _stateController.text = po['State'] ?? '';
            });
          }
        } else {
          if (mounted) {
            SnackBarUtils.showError('Invalid pincode — no location found');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError('Could not fetch location. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _isFetchingPincode = false);
    }
  }
 
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 85);
      if (image != null && mounted) {
        final bytes = await image.readAsBytes();
        setState(() {
          _newProfileImage = image;
          _newProfileBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError('Failed to pick image: $e');
      }
    }
  }
 
  Future<void> _selectDate(BuildContext context) async {
    final DateTime maxDate =
        DateTime.now().subtract(const Duration(days: 18 * 365));
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? maxDate,
      firstDate: DateTime(1950),
      lastDate: maxDate,
    );
    if (picked != null && picked != _dob) {
      setState(() => _dob = picked);
    }
  }
 
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      SnackBarUtils.showInfo('Please correct the highlighted errors before saving.');
      return;
    }
 
    if (_dob != null) {
      final age = _ageFromDob(_dob!);
      if (age < 18) {
        SnackBarUtils.showInfo('You must be at least 18 years old.');
        return;
      }
    }
 
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
 
    setState(() => _isSaving = true);
 
    try {
      String? newImageUrl = _existingProfileImageUrl;
      if (_newProfileImage != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('profile/${user.uid}/profile.jpg');
        final bytes = await _newProfileImage!.readAsBytes();
        final metadata = SettableMetadata(contentType: 'image/jpeg');
        final uploadTask = await storageRef.putData(bytes, metadata);
        newImageUrl = await uploadTask.ref.getDownloadURL();
      }
 
      final Map<String, dynamic> updateData = {
        'fullName': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'gender': _gender,
        'dateOfBirth':
            _dob != null ? DateFormat('yyyy-MM-dd').format(_dob!) : null,
        'houseNumber': _houseNumberController.text.trim(),
        'area': _areaController.text.trim(),
        'landmark': _landmarkController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim(),
        'pincode': _pincodeController.text.trim(),
        'language': _language,
        'education': _education,
        'experience': _experienceController.text.trim(),
        'headsetAvailable': _headsetAvailable ? 'Yes' : 'No',
        'deviceType': _deviceType,
        'internetType': _internetType,
        if (newImageUrl != null && newImageUrl.isNotEmpty)
          'profileImage': newImageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };
 
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10), onTimeout: () {
            throw Exception('Network timeout. Please check your connection.');
          });
 
      if (!mounted) return;
      SnackBarUtils.showSuccess('Profile updated successfully');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Failed to save profile: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
 
  int _ageFromDob(DateTime dob) {
    final today = DateTime.now();
    int age = today.year - dob.year;
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return age;
  }
 
  Widget _buildSectionHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    IconData icon;
    String subtitle;
    switch (title) {
      case 'Basic Information':
        icon = LucideIcons.user;
        subtitle = 'Your personal and contact details';
        break;
      case 'Address Information':
        icon = LucideIcons.mapPin;
        subtitle = 'Your current residential address';
        break;
      case 'Work Preferences':
        icon = LucideIcons.briefcase;
        subtitle = 'Language, education and experience';
        break;
      default:
        icon = LucideIcons.headphones;
        subtitle = 'Devices and connectivity available to you';
    }
 
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.xxl, bottom: AppSizes.base),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: isDark ? 0.30 : 0.22),
                  AppColors.primary.withValues(alpha: isDark ? 0.12 : 0.08),
                ],
              ),
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isDark ? Colors.white : AppColors.textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            isDark ? Colors.white54 : AppColors.textMuted,
                        height: 1.3,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
 
  /// Rounded card that groups the fields of one section.
  Widget _formCard(List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(AppSizes.base),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.border.withValues(alpha: 0.7),
        ),
        boxShadow: isDark ? null : AppDecorations.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
 
  InputDecoration _buildInputDecoration(BuildContext context, String label, IconData icon,
      {Widget? suffix}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? Colors.white.withValues(alpha: 0.10) : AppColors.border;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
          color: isDark ? Colors.white70 : AppColors.textLabel,
          fontSize: 13,
          fontWeight: FontWeight.w600),
      floatingLabelStyle: const TextStyle(
        color: AppColors.primary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(
        icon,
        size: 19,
        color: isDark ? AppColors.primaryLight : AppColors.primary,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : AppColors.surfaceElevated,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.base, vertical: AppSizes.base),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          borderSide: BorderSide(color: borderColor)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          borderSide: BorderSide(color: borderColor)),
      disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          borderSide: BorderSide(color: borderColor.withValues(alpha: 0.7))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          borderSide: const BorderSide(color: AppColors.error)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
    );
  }
 
  Widget _buildAvatarFallback() {
    final initial = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim().characters.first.toUpperCase()
        : 'U';
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: AppDecorations.primaryLightGradient,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final horizontalPadding = MediaQuery.sizeOf(context).width < 360
        ? AppSizes.base
        : AppSizes.screenPaddingH;
 
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        toolbarHeight: 72,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: AppColors.textDark,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSizes.lg,
                      horizontalPadding,
                      AppSizes.xxl + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Profile Photo ─────────────────────────────
                          Container(
                            clipBehavior: Clip.antiAlias,
                            padding: const EdgeInsets.all(AppSizes.xl),
                            decoration: BoxDecoration(
                              gradient: isDark
                                  ? AppDecorations.darkGradient
                                  : AppDecorations.primaryGradient,
                              borderRadius:
                                  BorderRadius.circular(AppSizes.radiusXl),
                              boxShadow: isDark
                                  ? null
                                  : AppDecorations.primaryShadow(alpha: 0.18),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  right: -60,
                                  top: -70,
                                  child: Container(
                                    width: 170,
                                    height: 170,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(alpha: 0.08),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: -50,
                                  bottom: -80,
                                  child: Container(
                                    width: 140,
                                    height: 140,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(alpha: 0.06),
                                    ),
                                  ),
                                ),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final compact = constraints.maxWidth < 300;
                                    final avatar = Semantics(
                                      button: true,
                                      label: 'Change profile photo',
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: _isSaving ? null : _pickImage,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Container(
                                              width: AppSizes.avatarXl,
                                              height: AppSizes.avatarXl,
                                              padding: const EdgeInsets.all(
                                                  AppSizes.xs),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.22),
                                                    blurRadius: 20,
                                                    offset: const Offset(0, 8),
                                                  ),
                                                ],
                                              ),
                                              child: ClipOval(
                                                child: _newProfileBytes != null
                                                    ? Image.memory(
                                                        _newProfileBytes!,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : (_existingProfileImageUrl !=
                                                                null &&
                                                            _existingProfileImageUrl!
                                                                .isNotEmpty)
                                                        ? Image.network(
                                                            _existingProfileImageUrl!,
                                                            fit: BoxFit.cover,
                                                            errorBuilder:
                                                                (_, __, ___) =>
                                                                    _buildAvatarFallback(),
                                                          )
                                                        : _buildAvatarFallback(),
                                              ),
                                            ),
                                            Positioned(
                                              right: -2,
                                              bottom: 2,
                                              child: Container(
                                                width: 36,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  color: AppColors.primary,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white,
                                                    width: 3,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: AppColors.secondary
                                                          .withValues(
                                                              alpha: 0.18),
                                                      blurRadius: 8,
                                                      offset:
                                                          const Offset(0, 3),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  LucideIcons.camera,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    final details = Column(
                                      crossAxisAlignment: compact
                                          ? CrossAxisAlignment.center
                                          : CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Profile photo',
                                          textAlign: compact
                                              ? TextAlign.center
                                              : TextAlign.left,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.3,
                                              ),
                                        ),
                                        const SizedBox(height: AppSizes.xs),
                                        Text(
                                          'Add a clear photo so your profile is easy to recognise.',
                                          textAlign: compact
                                              ? TextAlign.center
                                              : TextAlign.left,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Colors.white70,
                                                height: 1.4,
                                              ),
                                        ),
                                        const SizedBox(height: AppSizes.md),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _isSaving ? null : _pickImage,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: AppSizes.md,
                                              vertical: AppSizes.sm,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: 0.18),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                AppSizes.radiusRound,
                                              ),
                                              border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.28),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  LucideIcons.image,
                                                  size: 15,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(width: AppSizes.sm),
                                                Text(
                                                  'Choose photo',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
 
                                    if (compact) {
                                      return Column(
                                        children: [
                                          avatar,
                                          const SizedBox(height: AppSizes.lg),
                                          details,
                                        ],
                                      );
                                    }
                                    return Row(
                                      children: [
                                        avatar,
                                        const SizedBox(width: AppSizes.lg),
                                        Expanded(child: details),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
 
                          // ── Basic Information ─────────────────────────
                          _buildSectionHeader('Basic Information'),
                          _formCard([
                            CustomTextField(
                              controller: _nameController,
                              label: 'Full Name',
                              hintText: 'Enter your full name',
                              prefixIcon: LucideIcons.user,
                              readOnly: _isSaving,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppSizes.md),
                            CustomTextField(
                              controller: _emailController,
                              label: 'Email Address',
                              hintText: 'Enter your email',
                              prefixIcon: LucideIcons.mail,
                              keyboardType: TextInputType.emailAddress,
                              readOnly: _isSaving,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return null; // Optional
                                }
                                final emailRegex =
                                    RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                                if (!emailRegex.hasMatch(value)) {
                                  return 'Enter a valid email address';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppSizes.md),
                            CustomTextField(
                              controller: _phoneController,
                              label: 'Phone Number',
                              hintText: 'Enter your phone number',
                              prefixIcon: LucideIcons.phone,
                              keyboardType: TextInputType.phone,
                              readOnly: _isSaving,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return null; // Optional
                                }
                                if (value.length < 10) {
                                  return 'Phone number must be at least 10 digits';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppSizes.md),
                            CustomPopupMenuFormField<String>(
                              initialValue: _gender,
                              decoration: _buildInputDecoration(
                                  context, 'Gender', LucideIcons.users),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.textDark,
                                      fontSize: 14),
                              items: _genderOptions
                                  .map((value) => CustomPopupMenuItem(
                                        value: value,
                                        label: value,
                                      ))
                                  .toList(),
                              onChanged: _isSaving
                                  ? null
                                  : (value) => setState(() => _gender = value),
                            ),
                            const SizedBox(height: AppSizes.md),
                            GestureDetector(
                              onTap: () =>
                                  _isSaving ? null : _selectDate(context),
                              child: AbsorbPointer(
                                child: CustomTextField(
                                  label: 'Date of Birth',
                                  hintText: _dob == null
                                      ? 'Select Date (must be 18+)'
                                      : DateFormat('dd MMM yyyy')
                                          .format(_dob!),
                                  prefixIcon: LucideIcons.calendar,
                                  readOnly: true,
                                  validator: (_) {
                                    if (_dob == null) return null; // Optional
                                    if (_ageFromDob(_dob!) < 18) {
                                      return 'You must be at least 18 years old';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                          ]),
 
                          // ── Contact / Address Information ─────────────
                          _buildSectionHeader('Address Information'),
                          _formCard([
                            CustomTextField(
                              controller: _houseNumberController,
                              label: 'House Number',
                              hintText: 'Flat / House / Plot No.',
                              prefixIcon: LucideIcons.home,
                              readOnly: _isSaving,
                            ),
                            const SizedBox(height: AppSizes.md),
                            CustomTextField(
                              controller: _areaController,
                              label: 'Area / Street',
                              hintText: 'Colony, Street, Locality',
                              prefixIcon: LucideIcons.mapPin,
                              readOnly: _isSaving,
                            ),
                            const SizedBox(height: AppSizes.md),
                            CustomTextField(
                              controller: _landmarkController,
                              label: 'Landmark',
                              hintText: 'Near school, temple, etc.',
                              prefixIcon: LucideIcons.landmark,
                              readOnly: _isSaving,
                            ),
                            const SizedBox(height: AppSizes.md),
                            TextFormField(
                              controller: _pincodeController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              enabled: !_isSaving,
                              onChanged: (value) {
                                if (value.length == 6) {
                                  _fetchPincodeData(value);
                                }
                              },
                              decoration: _buildInputDecoration(
                                context,
                                'Pincode',
                                LucideIcons.hash,
                                suffix: _isFetchingPincode
                                    ? Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Theme.of(context)
                                                  .primaryColor),
                                        ),
                                      )
                                    : null,
                              ).copyWith(counterText: ''),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.textDark,
                                      fontSize: 14),
                            ),
                            const SizedBox(height: AppSizes.md),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final city = CustomTextField(
                                  controller: _cityController,
                                  label: 'City',
                                  hintText: 'Auto-filled',
                                  prefixIcon: LucideIcons.mapPin,
                                  readOnly: _isSaving,
                                );
                                final state = CustomTextField(
                                  controller: _stateController,
                                  label: 'State',
                                  hintText: 'Auto-filled',
                                  prefixIcon: LucideIcons.map,
                                  readOnly: _isSaving,
                                );
                                if (constraints.maxWidth < 340) {
                                  return Column(
                                    children: [
                                      city,
                                      const SizedBox(height: AppSizes.md),
                                      state,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: city),
                                    const SizedBox(width: AppSizes.md),
                                    Expanded(child: state),
                                  ],
                                );
                              },
                            ),
                          ]),
 
                          // ── Work Preferences ──────────────────────────
                          _buildSectionHeader('Work Preferences'),
                          _formCard([
                            CustomPopupMenuFormField<String>(
                              initialValue: _language,
                              decoration: _buildInputDecoration(context,
                                  'Preferred Language', LucideIcons.languages),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.textDark,
                                      fontSize: 14),
                              items: [
                                'English',
                                'Hindi',
                                'Telugu',
                                'Tamil',
                                'Kannada',
                                'Malayalam'
                              ].map((String value) {
                                return CustomPopupMenuItem<String>(
                                  value: value,
                                  label: value,
                                );
                              }).toList(),
                              onChanged: _isSaving
                                  ? null
                                  : (value) =>
                                      setState(() => _language = value),
                            ),
                            const SizedBox(height: AppSizes.md),
                            CustomPopupMenuFormField<String>(
                              initialValue: _education,
                              decoration: _buildInputDecoration(
                                  context,
                                  'Education Level',
                                  LucideIcons.graduationCap),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.textDark,
                                      fontSize: 14),
                              items: _educationOptions.map((String value) {
                                return CustomPopupMenuItem<String>(
                                  value: value,
                                  label: value,
                                );
                              }).toList(),
                              onChanged: _isSaving
                                  ? null
                                  : (value) =>
                                      setState(() => _education = value),
                            ),
                            const SizedBox(height: AppSizes.md),
                            CustomTextField(
                              controller: _experienceController,
                              label: 'Work Experience',
                              hintText: 'e.g. 2 years in BPO',
                              prefixIcon: LucideIcons.briefcase,
                              readOnly: _isSaving,
                            ),
                          ]),
 
                          // ── Equipment Details ─────────────────────────
                          _buildSectionHeader('Equipment Details'),
                          _formCard([
                            Container(
                              margin:
                                  const EdgeInsets.only(bottom: AppSizes.md),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : AppColors.surfaceElevated,
                                borderRadius:
                                    BorderRadius.circular(AppSizes.radiusLg),
                                border: Border.all(
                                  color: _headsetAvailable
                                      ? AppColors.primary.withValues(alpha: 0.35)
                                      : (isDark
                                          ? Colors.white.withValues(alpha: 0.10)
                                          : AppColors.border),
                                ),
                              ),
                              child: SwitchListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSizes.base,
                                  vertical: AppSizes.xs,
                                ),
                                secondary: Icon(
                                  LucideIcons.headphones,
                                  size: 19,
                                  color: isDark
                                      ? AppColors.primaryLight
                                      : AppColors.primary,
                                ),
                                title: Text(
                                  'Headset Available',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white
                                            : AppColors.textDark,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                subtitle: Text(
                                  _headsetAvailable
                                      ? 'Available'
                                      : 'Not available',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white54
                                            : AppColors.textMuted,
                                      ),
                                ),
                                value: _headsetAvailable,
                                activeThumbColor: AppColors.primary,
                                onChanged: _isSaving
                                    ? null
                                    : (value) => setState(
                                        () => _headsetAvailable = value),
                              ),
                            ),
                            CustomPopupMenuFormField<String>(
                              initialValue: _deviceType,
                              decoration: _buildInputDecoration(context,
                                  'Device Type', LucideIcons.smartphone),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.textDark,
                                      fontSize: 14),
                              items: ['Android', 'iPhone', 'Laptop', 'Desktop']
                                  .map((String value) {
                                return CustomPopupMenuItem<String>(
                                  value: value,
                                  label: value,
                                );
                              }).toList(),
                              onChanged: _isSaving
                                  ? null
                                  : (value) =>
                                      setState(() => _deviceType = value),
                            ),
                            const SizedBox(height: AppSizes.md),
                            CustomPopupMenuFormField<String>(
                              initialValue: _internetType,
                              decoration: _buildInputDecoration(
                                  context, 'Internet Type', LucideIcons.wifi),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.textDark,
                                      fontSize: 14),
                              items: ['WiFi', 'Mobile Data', 'Broadband']
                                  .map((String value) {
                                return CustomPopupMenuItem<String>(
                                  value: value,
                                  label: value,
                                );
                              }).toList(),
                              onChanged: _isSaving
                                  ? null
                                  : (value) =>
                                      setState(() => _internetType = value),
                            ),
                          ]),
                          const SizedBox(height: AppSizes.xxxl),
 
                          Container(
                            padding: const EdgeInsets.all(AppSizes.xs),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius:
                                  BorderRadius.circular(AppSizes.radiusLg),
                              boxShadow:
                                  isDark ? null : AppDecorations.shadowSm,
                            ),
                            child: CustomButton(
                              label: 'Save Profile Changes',
                              icon: LucideIcons.checkCircle,
                              isLoading: _isSaving,
                              isDisabled: _isSaving,
                              height: AppSizes.buttonHeightLg,
                              fontSize: 16,
                              onPressed: _saveProfile,
                            ),
                          ),
                          const SizedBox(height: AppSizes.xxl),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
 
/// Screen-local field styling keeps the Edit Profile redesign isolated from
/// every other form in the application.
class CustomTextField extends StatelessWidget {
  const CustomTextField({
    super.key,
    this.controller,
    required this.label,
    required this.hintText,
    this.prefixIcon,
    this.keyboardType = TextInputType.text,
    this.readOnly = false,
    this.validator,
  });
 
  final TextEditingController? controller;
  final String label;
  final String hintText;
  final IconData? prefixIcon;
  final TextInputType keyboardType;
  final bool readOnly;
  final FormFieldValidator<String>? validator;
 
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? Colors.white.withValues(alpha: 0.10) : AppColors.border;
 
    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        borderSide: BorderSide(color: color, width: width),
      );
    }
 
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: isDark ? Colors.white70 : AppColors.textLabel,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
        ),
        const SizedBox(height: AppSizes.sm),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          validator: validator,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.white : AppColors.textDark,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: isDark ? Colors.white30 : AppColors.textPlaceholder,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: prefixIcon == null
                ? null
                : Icon(
                    prefixIcon,
                    size: 19,
                    color:
                        isDark ? AppColors.primaryLight : AppColors.primary,
                  ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : AppColors.surfaceElevated,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSizes.base,
              vertical: AppSizes.base,
            ),
            border: border(borderColor),
            enabledBorder: border(borderColor),
            focusedBorder: border(AppColors.primary, width: 1.5),
            errorBorder: border(AppColors.error),
            focusedErrorBorder: border(AppColors.error, width: 1.5),
            errorStyle: const TextStyle(
              color: AppColors.error,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
 