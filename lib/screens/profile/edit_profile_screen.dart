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
import '../../core/utils/snackbar_utils.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';

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
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.xl, bottom: AppSizes.md),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(BuildContext context, String label, IconData icon,
      {Widget? suffix}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
          color: isDark ? Colors.white38 : AppColors.textBody,
          fontSize: 13,
          fontWeight: FontWeight.w500),
      prefixIcon: Icon(icon, size: 20, color: isDark ? Colors.white38 : AppColors.textMuted),
      suffixIcon: suffix,
      filled: true,
      fillColor: Theme.of(context).cardColor,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.base, vertical: AppSizes.base),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: isDark ? Colors.white : AppColors.textDark,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: isDark ? Colors.white : AppColors.textDark),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.screenPaddingH),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Profile Photo ─────────────────────────────
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          if (!_isSaving) _pickImage();
                        },
                        child: Stack(
                          children: [
                            Container(
                              width: AppSizes.avatarLg,
                              height: AppSizes.avatarLg,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.primaryLight,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Theme.of(context).cardColor, width: 4),
                                boxShadow: isDark ? null : [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: ClipOval(
                                child: _newProfileBytes != null
                                    ? Image.memory(_newProfileBytes!,
                                        fit: BoxFit.cover)
                                    : (_existingProfileImageUrl != null &&
                                            _existingProfileImageUrl!.isNotEmpty)
                                        ? Image.network(
                                            _existingProfileImageUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Center(
                                              child: Icon(LucideIcons.user,
                                                  size: 32, color: isDark ? Colors.white24 : Colors.white),
                                            ),
                                          )
                                        : Center(
                                            child: Icon(LucideIcons.user,
                                                size: 32, color: isDark ? Colors.white24 : Colors.white),
                                          ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Theme.of(context).cardColor, width: 2),
                                ),
                                child: const Icon(LucideIcons.camera,
                                    color: Colors.white, size: 14),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // ── Basic Information ─────────────────────────
                    _buildSectionHeader('Basic Information'),
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

                    DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration:
                          _buildInputDecoration(context, 'Gender', LucideIcons.users),
                      dropdownColor: Theme.of(context).cardColor,
                      icon: Icon(LucideIcons.chevronDown,
                          color: isDark ? Colors.white38 : AppColors.textMuted, size: 20),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white : AppColors.textDark, fontSize: 14),
                      items: _genderOptions.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value,
                              style: TextStyle(
                                  color: isDark ? Colors.white : AppColors.textDark)),
                        );
                      }).toList(),
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
                              : DateFormat('dd MMM yyyy').format(_dob!),
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

                    // ── Contact / Address Information ─────────────
                    _buildSectionHeader('Address Information'),
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
                                      color: Theme.of(context).primaryColor),
                                ),
                              )
                            : null,
                      ).copyWith(counterText: ''),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white : AppColors.textDark, fontSize: 14),
                    ),
                    const SizedBox(height: AppSizes.md),

                    Row(
                      children: [
                        Expanded(
                          child: CustomTextField(
                            controller: _cityController,
                            label: 'City',
                            hintText: 'Auto-filled',
                            readOnly: _isSaving,
                          ),
                        ),
                        const SizedBox(width: AppSizes.md),
                        Expanded(
                          child: CustomTextField(
                            controller: _stateController,
                            label: 'State',
                            hintText: 'Auto-filled',
                            readOnly: _isSaving,
                          ),
                        ),
                      ],
                    ),

                    // ── Work Preferences ──────────────────────────
                    _buildSectionHeader('Work Preferences'),
                    DropdownButtonFormField<String>(
                      initialValue: _language,
                      decoration: _buildInputDecoration(
                          context, 'Preferred Language', LucideIcons.languages),
                      dropdownColor: Theme.of(context).cardColor,
                      icon: Icon(LucideIcons.chevronDown,
                          color: isDark ? Colors.white38 : AppColors.textMuted, size: 20),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white : AppColors.textDark, fontSize: 14),
                      items: [
                        'English',
                        'Hindi',
                        'Telugu',
                        'Tamil',
                        'Kannada',
                        'Malayalam'
                      ].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value,
                              style: TextStyle(
                                  color: isDark ? Colors.white : AppColors.textDark)),
                        );
                      }).toList(),
                      onChanged: _isSaving
                          ? null
                          : (value) =>
                              setState(() => _language = value),
                    ),
                    const SizedBox(height: AppSizes.md),

                    DropdownButtonFormField<String>(
                      initialValue: _education,
                      decoration: _buildInputDecoration(
                          context, 'Education Level', LucideIcons.graduationCap),
                      dropdownColor: Theme.of(context).cardColor,
                      icon: Icon(LucideIcons.chevronDown,
                          color: isDark ? Colors.white38 : AppColors.textMuted, size: 20),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white : AppColors.textDark, fontSize: 14),
                      items: _educationOptions.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value,
                              style: TextStyle(
                                  color: isDark ? Colors.white : AppColors.textDark)),
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

                    // ── Equipment Details ─────────────────────────
                    _buildSectionHeader('Equipment Details'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Headset Available',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isDark ? Colors.white : AppColors.textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w500)),
                      value: _headsetAvailable,
                      activeThumbColor: AppColors.primary,
                      onChanged: _isSaving
                          ? null
                          : (value) =>
                              setState(() => _headsetAvailable = value),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _deviceType,
                      decoration: _buildInputDecoration(
                          context, 'Device Type', LucideIcons.smartphone),
                      dropdownColor: Theme.of(context).cardColor,
                      icon: Icon(LucideIcons.chevronDown,
                          color: isDark ? Colors.white38 : AppColors.textMuted, size: 20),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white : AppColors.textDark, fontSize: 14),
                      items: ['Android', 'iPhone', 'Laptop', 'Desktop']
                          .map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value,
                              style: TextStyle(
                                  color: isDark ? Colors.white : AppColors.textDark)),
                        );
                      }).toList(),
                      onChanged: _isSaving
                          ? null
                          : (value) =>
                              setState(() => _deviceType = value),
                    ),
                    const SizedBox(height: AppSizes.md),
                    DropdownButtonFormField<String>(
                      initialValue: _internetType,
                      decoration: _buildInputDecoration(
                          context, 'Internet Type', LucideIcons.wifi),
                      dropdownColor: Theme.of(context).cardColor,
                      icon: Icon(LucideIcons.chevronDown,
                          color: isDark ? Colors.white38 : AppColors.textMuted, size: 20),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white : AppColors.textDark, fontSize: 14),
                      items: ['WiFi', 'Mobile Data', 'Broadband']
                          .map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value,
                              style: TextStyle(
                                  color: isDark ? Colors.white : AppColors.textDark)),
                        );
                      }).toList(),
                      onChanged: _isSaving
                          ? null
                          : (value) =>
                              setState(() => _internetType = value),
                    ),
                    const SizedBox(height: AppSizes.xxxl),

                    CustomButton(
                      label: 'Save Profile Changes',
                      icon: LucideIcons.checkCircle,
                      isLoading: _isSaving,
                      isDisabled: _isSaving,
                      onPressed: _saveProfile,
                    ),
                    const SizedBox(height: AppSizes.xxl),
                  ],
                ),
              ),
            ),
    );
  }
}
