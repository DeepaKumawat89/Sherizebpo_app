import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../widgets/custom_button.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({Key? key}) : super(key: key);

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  final ImagePicker _picker = ImagePicker();

  XFile? _profilePhoto;
  XFile? _aadhaarPhoto;
  XFile? _panPhoto;

  Uint8List? _profileBytes;
  Uint8List? _aadhaarBytes;
  Uint8List? _panBytes;

  bool _isSubmitting = false;

  Future<void> _pickImage(String type) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1200,
        imageQuality: 70,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          if (type == 'profile') {
            _profilePhoto = image;
            _profileBytes = bytes;
          } else if (type == 'aadhaar') {
            _aadhaarPhoto = image;
            _aadhaarBytes = bytes;
          } else if (type == 'pan') {
            _panPhoto = image;
            _panBytes = bytes;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Failed to pick image: $e');
    }
  }

  Future<void> _submitKyc() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_profilePhoto == null || _aadhaarPhoto == null || _panPhoto == null) {
      SnackBarUtils.showInfo('Please upload all required KYC documents.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        final currentStatus = (data['kycStatus'] ?? data['kyc_status'] ?? '')
            .toString()
            .toLowerCase();
        if (currentStatus == 'approved' || currentStatus == 'pending') {
          throw Exception('KYC is already $currentStatus. Cannot resubmit.');
        }
      }

      final storage = FirebaseStorage.instance;

      Future<String> uploadFile(XFile file, String type) async {
        final ref = storage.ref().child('kyc/${user.uid}/$type.jpg');
        final bytes = await file.readAsBytes();
        final metadata = SettableMetadata(contentType: 'image/jpeg');
        final uploadTask = await ref.putData(bytes, metadata);
        return await uploadTask.ref.getDownloadURL();
      }

      final profileUrl = await uploadFile(_profilePhoto!, 'profile');
      final aadhaarUrl = await uploadFile(_aadhaarPhoto!, 'aadhaar');
      final panUrl = await uploadFile(_panPhoto!, 'pan');

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'profileImageUrl': profileUrl,
        'aadhaarUrl': aadhaarUrl,
        'panUrl': panUrl,
        'kycStatus': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      SnackBarUtils.showSuccess('KYC documents submitted successfully!');
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Failed to submit KYC: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('User not logged in.')));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('KYC Verification'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          final dbStatus =
              (data['kycStatus'] ?? data['kyc_status'] ?? 'unverified')
                  .toString()
                  .toLowerCase();

          final bool isUnderReview = dbStatus == 'pending';
          final bool isApproved = dbStatus == 'approved';
          final bool isDisabled = isUnderReview || isApproved;

          String displayStatus = 'Not Started';
          Color statusColor = isDark ? Colors.white54 : AppColors.textMuted;
          IconData statusIcon = LucideIcons.alertCircle;

          if (isUnderReview) {
            displayStatus = 'Application submitted';
            statusColor = AppColors.warning;
            statusIcon = LucideIcons.clock;
          } else if (isApproved) {
            displayStatus = 'KYC Approved';
            statusColor = AppColors.success;
            statusIcon = LucideIcons.checkCircle2;
          } else if (dbStatus == 'rejected') {
            displayStatus = 'Rejected (Please re-upload)';
            statusColor = AppColors.error;
            statusIcon = LucideIcons.xCircle;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.screenPaddingH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Verification Status Card ──
                Container(
                  padding: const EdgeInsets.all(AppSizes.lg),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        statusIcon,
                        color: statusColor,
                        size: 24,
                      ),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Verification Status',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: isDark
                                        ? Colors.white38
                                        : AppColors.textMuted,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              displayStatus,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.xxl),

                Text(
                  'Required Documents',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isDark ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppSizes.md),
                Text(
                  'Please provide clear pictures of the following to activate your account for task acceptance.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isDark ? Colors.white70 : AppColors.textBody,
                      ),
                ),
                const SizedBox(height: AppSizes.xxl),

                // ── Upload Tiles ──
                _buildUploadTile(
                  context: context,
                  title: 'Profile Photo',
                  subtitle: 'Clear selfie facing the camera',
                  file: _profilePhoto,
                  bytes: _profileBytes,
                  networkUrl: data['profileImageUrl'],
                  typeKey: 'profile',
                  isDisabled: isDisabled,
                  isDark: isDark,
                ),
                const SizedBox(height: AppSizes.base),

                _buildUploadTile(
                  context: context,
                  title: 'Aadhaar Card',
                  subtitle: 'Front and back side',
                  file: _aadhaarPhoto,
                  bytes: _aadhaarBytes,
                  networkUrl: data['aadhaarUrl'] ?? data['aadharUrl'],
                  typeKey: 'aadhaar',
                  isDisabled: isDisabled,
                  isDark: isDark,
                ),
                const SizedBox(height: AppSizes.base),

                _buildUploadTile(
                  context: context,
                  title: 'PAN Card',
                  subtitle: 'Clear photo showing the PAN number',
                  file: _panPhoto,
                  bytes: _panBytes,
                  networkUrl: data['panUrl'],
                  typeKey: 'pan',
                  isDisabled: isDisabled,
                  isDark: isDark,
                ),
                const SizedBox(height: AppSizes.xxxl),

                if (!isApproved)
                  CustomButton(
                    label:
                        isUnderReview ? 'Under Review' : 'Submit Verification',
                    icon: LucideIcons.send,
                    isLoading: _isSubmitting,
                    isDisabled: isDisabled || _isSubmitting,
                    onPressed: _submitKyc,
                  ),
                const SizedBox(height: AppSizes.xxl),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildUploadTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required XFile? file,
    Uint8List? bytes,
    String? networkUrl,
    required String typeKey,
    required bool isDisabled,
    required bool isDark,
  }) {
    final bool hasFile = file != null || networkUrl != null;

    return GestureDetector(
      onTap: () {
        if (!isDisabled && !_isSubmitting) {
          _pickImage(typeKey);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(AppSizes.lg),
        decoration: BoxDecoration(
          color: hasFile
              ? AppColors.success.withValues(alpha: 0.05)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(
            color: hasFile
                ? AppColors.success.withValues(alpha: 0.5)
                : Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: hasFile
                    ? AppColors.success
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : AppColors.background),
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              ),
              child: Icon(
                hasFile ? LucideIcons.checkCircle : LucideIcons.uploadCloud,
                color: hasFile
                    ? Colors.white
                    : (isDark ? Colors.white38 : AppColors.textMuted),
                size: 20,
              ),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: isDark ? Colors.white : AppColors.textDark,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasFile ? 'File attached' : subtitle,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: hasFile
                              ? AppColors.success
                              : (isDark ? Colors.white38 : AppColors.textMuted),
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
            if (hasFile)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                child: file != null && bytes != null
                    ? Image.memory(
                        bytes,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      )
                    : Image.network(
                        networkUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                            LucideIcons.imageOff,
                            size: 20,
                            color:
                                isDark ? Colors.white24 : AppColors.textLight),
                      ),
              )
            else
              Icon(
                LucideIcons.chevronRight,
                color: isDark ? Colors.white24 : AppColors.textLight,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
