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

    setState(() => _isSubmitting = true);

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
        return uploadTask.ref.getDownloadURL();
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
    final textTheme = Theme.of(context).textTheme;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('User not logged in.')));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('KYC Verification')),
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
          final isUnderReview = dbStatus == 'pending';
          final isApproved = dbStatus == 'approved';
          final isDisabled = isUnderReview || isApproved;

          String displayStatus = 'Verification required';
          String statusDescription =
              'Complete the three steps below to verify your identity.';
          String statusLabel = 'NOT STARTED';
          Color statusColor =
              isDark ? AppColors.primaryLight : AppColors.primary;
          IconData statusIcon = LucideIcons.shield;

          if (isUnderReview) {
            displayStatus = 'Verification in progress';
            statusDescription =
                'Your documents are with our review team. We’ll update your status once the review is complete.';
            statusLabel = 'UNDER REVIEW';
            statusColor = AppColors.warning;
            statusIcon = LucideIcons.clock;
          } else if (isApproved) {
            displayStatus = 'Identity verified';
            statusDescription =
                'Your KYC is complete and your account is ready to accept tasks.';
            statusLabel = 'APPROVED';
            statusColor = AppColors.success;
            statusIcon = LucideIcons.shieldCheck;
          } else if (dbStatus == 'rejected') {
            displayStatus = 'Action needed';
            statusDescription =
                'We couldn’t verify the previous submission. Replace all three images with clear, readable photos.';
            statusLabel = 'RESUBMISSION REQUIRED';
            statusColor = AppColors.error;
            statusIcon = LucideIcons.alertCircle;
          }

          final selectedCount = [
            _profilePhoto,
            _aadhaarPhoto,
            _panPhoto,
          ].where((file) => file != null).length;

          return LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth < 380
                  ? AppSizes.base
                  : AppSizes.screenPaddingH;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppSizes.md,
                  horizontalPadding,
                  AppSizes.xxxl,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStatusPanel(
                          context: context,
                          title: displayStatus,
                          description: statusDescription,
                          label: statusLabel,
                          icon: statusIcon,
                          color: statusColor,
                          isDark: isDark,
                        ),
                        const SizedBox(height: AppSizes.xxl),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isDisabled
                                        ? 'Submitted information'
                                        : 'Required information',
                                    style: textTheme.titleLarge?.copyWith(
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.textDark,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.xs),
                                  Text(
                                    isDisabled
                                        ? 'These documents are included in your verification.'
                                        : 'Use original, well-lit images with every detail visible.',
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: isDark
                                          ? Colors.white54
                                          : AppColors.textMuted,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isDisabled) ...[
                              const SizedBox(width: AppSizes.md),
                              Text(
                                '$selectedCount of 3',
                                style: textTheme.labelLarge?.copyWith(
                                  color: selectedCount == 3
                                      ? AppColors.success
                                      : (isDark
                                          ? AppColors.primaryLight
                                          : AppColors.primary),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSizes.lg),
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius:
                                BorderRadius.circular(AppSizes.radiusLg),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : AppColors.border,
                            ),
                          ),
                          child: Column(
                            children: [
                              _buildUploadRow(
                                context: context,
                                step: '1',
                                icon: LucideIcons.camera,
                                title: 'Recent selfie',
                                subtitle:
                                    'Face the camera without a mask or filter',
                                file: _profilePhoto,
                                bytes: _profileBytes,
                                networkUrl: data['profileImageUrl'],
                                typeKey: 'profile',
                                isDisabled: isDisabled,
                                isDark: isDark,
                              ),
                              _buildDocumentDivider(isDark),
                              _buildUploadRow(
                                context: context,
                                step: '2',
                                icon: LucideIcons.fileText,
                                title: 'Aadhaar card',
                                subtitle:
                                    'Upload a clear image with all details visible',
                                file: _aadhaarPhoto,
                                bytes: _aadhaarBytes,
                                networkUrl:
                                    data['aadhaarUrl'] ?? data['aadharUrl'],
                                typeKey: 'aadhaar',
                                isDisabled: isDisabled,
                                isDark: isDark,
                              ),
                              _buildDocumentDivider(isDark),
                              _buildUploadRow(
                                context: context,
                                step: '3',
                                icon: LucideIcons.fileText,
                                title: 'PAN card',
                                subtitle:
                                    'Make sure your name and PAN are readable',
                                file: _panPhoto,
                                bytes: _panBytes,
                                networkUrl: data['panUrl'],
                                typeKey: 'pan',
                                isDisabled: isDisabled,
                                isDark: isDark,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSizes.lg),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              LucideIcons.lock,
                              size: 16,
                              color: isDark
                                  ? Colors.white38
                                  : AppColors.textMuted,
                            ),
                            const SizedBox(width: AppSizes.sm),
                            Expanded(
                              child: Text(
                                'Your documents are encrypted and used only to verify your identity.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: isDark
                                      ? Colors.white38
                                      : AppColors.textMuted,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!isApproved) ...[
                          const SizedBox(height: AppSizes.xxl),
                          CustomButton(
                            label: isUnderReview
                                ? 'Verification under review'
                                : dbStatus == 'rejected'
                                    ? 'Resubmit for verification'
                                    : 'Submit for verification',
                            icon: isUnderReview
                                ? LucideIcons.clock
                                : LucideIcons.shieldCheck,
                            isLoading: _isSubmitting,
                            isDisabled: isDisabled ||
                                _isSubmitting ||
                                selectedCount < 3,
                            onPressed: _submitKyc,
                          ),
                          if (!isUnderReview) ...[
                            const SizedBox(height: AppSizes.sm),
                            Text(
                              selectedCount == 3
                                  ? 'All required images are ready.'
                                  : 'Select all 3 images before submitting.',
                              textAlign: TextAlign.center,
                              style: textTheme.bodySmall?.copyWith(
                                color: selectedCount == 3
                                    ? AppColors.success
                                    : (isDark
                                        ? Colors.white38
                                        : AppColors.textMuted),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusPanel({
    required BuildContext context,
    required String title,
    required String description,
    required String label,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.xl),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.18 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 23),
          ),
          const SizedBox(width: AppSizes.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSizes.radiusRound),
                  ),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: isDark ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isDark ? Colors.white60 : AppColors.textBody,
                        height: 1.45,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentDivider(bool isDark) {
    return Divider(
      height: 1,
      indent: AppSizes.lg,
      endIndent: AppSizes.lg,
      color: isDark
          ? Colors.white.withValues(alpha: 0.07)
          : AppColors.borderLight,
    );
  }

  Widget _buildUploadRow({
    required BuildContext context,
    required String step,
    required IconData icon,
    required String title,
    required String subtitle,
    required XFile? file,
    Uint8List? bytes,
    String? networkUrl,
    required String typeKey,
    required bool isDisabled,
    required bool isDark,
  }) {
    final hasSelectedFile = file != null;
    final hasSubmittedFile = isDisabled && networkUrl != null;
    final isComplete = hasSelectedFile || hasSubmittedFile;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled || _isSubmitting ? null : () => _pickImage(typeKey),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isComplete
                      ? AppColors.success
                          .withValues(alpha: isDark ? 0.16 : 0.1)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : AppColors.primarySoft.withValues(alpha: 0.7)),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Icon(
                  isComplete ? LucideIcons.check : icon,
                  color: isComplete
                      ? AppColors.success
                      : (isDark
                          ? AppColors.primaryLight
                          : AppColors.primary),
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSizes.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$step. $title',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color:
                                isDark ? Colors.white : AppColors.textDark,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: AppSizes.xs),
                    Text(
                      isComplete
                          ? (hasSelectedFile
                              ? 'Ready to submit'
                              : 'Included in submission')
                          : subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isComplete
                                ? AppColors.success
                                : (isDark
                                    ? Colors.white38
                                    : AppColors.textMuted),
                            fontWeight: isComplete
                                ? FontWeight.w600
                                : FontWeight.w400,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.md),
              if (hasSelectedFile || hasSubmittedFile)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  child: hasSelectedFile && bytes != null
                      ? Image.memory(
                          bytes,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          networkUrl!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              LucideIcons.imageOff,
                              size: 20,
                              color: isDark
                                  ? Colors.white24
                                  : AppColors.textLight,
                            ),
                          ),
                        ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppSizes.radiusRound),
                  ),
                  child: Text(
                    'Upload',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isDark
                              ? AppColors.primaryLight
                              : AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
