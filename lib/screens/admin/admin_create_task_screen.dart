// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:flutter/material.dart' as flutter;
// import 'package:flutter/services.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_storage/firebase_storage.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:csv/csv.dart';
// import 'package:excel/excel.dart' hide Border;
// import 'package:lucide_icons/lucide_icons.dart';
// import 'package:provider/provider.dart';
// import '../../core/constants/constants.dart';
// import '../../services/task_service.dart';
// import '../../services/platform_settings_service.dart';
// import '../../core/utils/snackbar_utils.dart';
// import '../../routes.dart';

// /// Admin Task Creation Screen.
// ///
// /// Provides a clean form for admins to create new calling tasks
// /// that appear in the Worker Task Marketplace.
// class AdminCreateTaskScreen extends StatefulWidget {
//   const AdminCreateTaskScreen({Key? key}) : super(key: key);

//   @override
//   State<AdminCreateTaskScreen> createState() => _AdminCreateTaskScreenState();
// }

// class _AdminCreateTaskScreenState extends State<AdminCreateTaskScreen> {
//   final _formKey = GlobalKey<FormState>();
//   final _taskService = TaskService();

//   // ─── Controllers ───────────────────────────────────────────
//   final _titleController = TextEditingController();
//   final _clientController = TextEditingController();
//   final _descriptionController = TextEditingController();
//   final _scriptController = TextEditingController();
//   final _payoutController = TextEditingController();
//   final _slotsController = TextEditingController();
//   final _leadsToAllocateController = TextEditingController();

//   // ─── Dropdown Values ───────────────────────────────────────
//   String _priority = 'Medium';
//   String _status = 'active';

//   // ─── Leads ─────────────────────────────────────────────────
//   final List<Map<String, String>> _leads = [];

//   // ─── Campaign Picker ────────────────────────────────────────
//   List<Map<String, dynamic>> _availableCampaigns = [];
//   String? _selectedCampaignId;
//   int _selectedCampaignLeadCount = 0;
//   bool _isLoadingCampaigns = false;

//   // ─── State ─────────────────────────────────────────────────
//   bool _isSubmitting = false;
//   bool _isAdmin = false;
//   bool _isCheckingRole = true;

//   bool _isParsing = false;
//   double _uploadProgress = 0.0;
//   String _uploadStatus = '';
//   late String _predefinedTaskId;

//   @override
//   void initState() {
//     super.initState();
//     _predefinedTaskId = FirebaseFirestore.instance.collection('tasks').doc().id;
//     _verifyAdminRole();
//     _loadCampaigns();
//   }

//   @override
//   void dispose() {
//     _titleController.dispose();
//     _clientController.dispose();
//     _descriptionController.dispose();
//     _scriptController.dispose();
//     _payoutController.dispose();
//     _slotsController.dispose();
//     _leadsToAllocateController.dispose();
//     super.dispose();
//   }

//   // ─── Lead Upload & Parsing ─────────────────────────────────
//   Future<void> _pickAndUploadLeadSheet() async {
//     try {
//       final result = await FilePicker.platform.pickFiles(
//         type: FileType.custom,
//         allowedExtensions: ['csv', 'xlsx', 'xls'],
//         withData: true,
//       );

//       if (result == null || result.files.isEmpty) return;

//       final file = result.files.first;
//       final fileBytes = file.bytes;
//       final fileName = file.name;

//       if (fileBytes == null) {
//         _showError('Unable to read file content.');
//         return;
//       }

//       setState(() {
//         _isParsing = true;
//         _uploadStatus = 'Uploading...';
//       });

//       // 1. Upload to Storage
//       // Use campaignId path when linked to a campaign, otherwise taskId
//       final leadOwnerId = _selectedCampaignId ?? _predefinedTaskId;
//       final storageRef = FirebaseStorage.instance
//           .ref()
//           .child('lead_sheets')
//           .child(leadOwnerId)
//           .child(fileName);

//       final uploadTask = storageRef.putData(
//         fileBytes,
//         SettableMetadata(contentType: 'application/octet-stream'),
//       );

//       uploadTask.snapshotEvents.listen((event) {
//         final progress = event.bytesTransferred / event.totalBytes;
//         if (mounted) {
//           setState(() {
//             _uploadProgress = progress;
//           });
//         }
//       });

//       await uploadTask;

//       // 2. Parse File
//       if (mounted) {
//         setState(() {
//           _uploadStatus = 'Parsing file...';
//           _uploadProgress = 0.0;
//         });
//       }

//       List<Map<String, String>> newLeads = [];

//       if (fileName.toLowerCase().endsWith('.csv')) {
//         final csvString = utf8.decode(fileBytes);
//         final rows = const CsvToListConverter().convert(csvString);
//         if (rows.isNotEmpty) {
//           final headers =
//               rows.first.map((e) => e.toString().toLowerCase().trim()).toList();
//           for (int i = 1; i < rows.length; i++) {
//             final leadData = _extractLeadFromRow(headers, rows[i]);
//             if (leadData != null) newLeads.add(leadData);
//           }
//         }
//       } else if (fileName.toLowerCase().endsWith('.xlsx') ||
//           fileName.toLowerCase().endsWith('.xls')) {
//         var excelParser = Excel.decodeBytes(fileBytes);
//         for (var table in excelParser.tables.keys) {
//           final sheet = excelParser.tables[table];
//           if (sheet == null || sheet.maxRows == 0) continue;

//           final headers = sheet
//               .row(0)
//               .map((e) => e?.value?.toString().toLowerCase().trim() ?? '')
//               .toList();
//           for (int i = 1; i < sheet.maxRows; i++) {
//             final row = sheet.row(i).map((e) => e?.value).toList();
//             final leadData = _extractLeadFromRow(headers, row);
//             if (leadData != null) newLeads.add(leadData);
//           }
//           break; // Process first sheet only
//         }
//       }

//       if (mounted) {
//         setState(() {
//           _leads.addAll(newLeads);
//           _isParsing = false;
//           _uploadStatus = '';
//           _uploadProgress = 0.0;
//         });

//         if (newLeads.isNotEmpty) {
//           _showSuccess('Successfully loaded ${newLeads.length} leads!');
//         } else {
//           _showError(
//               'No valid leads found in file (Need at least Name and Phone).');
//         }
//       }
//     } catch (e) {
//       if (mounted) {
//         setState(() {
//           _isParsing = false;
//           _uploadStatus = '';
//         });
//         _showError('Upload or parsing failed: $e');
//       }
//     }
//   }

//   Map<String, String>? _extractLeadFromRow(
//       List<String> headers, List<dynamic> row) {
//     String name = '';
//     String phone = '';
//     String email = '';
//     String city = '';

//     for (int j = 0; j < headers.length; j++) {
//       if (j >= row.length) break;
//       final val = row[j]?.toString().trim() ?? '';
//       if (val.isEmpty) continue;

//       final header = headers[j];

//       if (header.contains('name') || header.contains('student')) {
//         name = val;
//       } else if (header.contains('phone') ||
//           header.contains('mobile') ||
//           header.contains('contact') ||
//           header.contains('no')) {
//         phone = val;
//       } else if (header.contains('email') || header.contains('mail')) {
//         email = val;
//       } else if (header.contains('city') || header.contains('location')) {
//         city = val;
//       }
//     }

//     if (name.isNotEmpty && phone.isNotEmpty) {
//       // Basic formatting to catch purely numeric fields imported incorrectly
//       return {
//         'name': name,
//         'phone': phone.replaceAll(RegExp(r'[^0-9+]'), ''),
//         'email': email,
//         'city': city,
//       };
//     }
//     return null;
//   }

//   void _showError(String message) {
//     SnackBarUtils.showError(message);
//   }
//   void _showSuccess(String message) {
//     SnackBarUtils.showSuccess(message);
//   }

//   // ─── Admin Role Verification ───────────────────────────────
//   Future<void> _verifyAdminRole() async {
//     try {
//       final user = FirebaseAuth.instance.currentUser;
//       if (user == null) {
//         setState(() {
//           _isAdmin = false;
//           _isCheckingRole = false;
//         });
//         return;
//       }

//       final userDoc = await FirebaseFirestore.instance
//           .collection('users')
//           .doc(user.uid)
//           .get();

//       final data = userDoc.data() ?? {};
//       final role = (data['role'] ?? '').toString().toLowerCase();
//       final roles = (data['roles'] is List)
//           ? (data['roles'] as List).map((e) => e.toString().toLowerCase())
//           : const <String>[];
//       // Full admins (admin / super_admin) may create tasks. Matches the
//       // dashboard's superView gate and the Firestore rules (isAdmin()).
//       const allowed = {'admin', 'super_admin'};

//       setState(() {
//         _isAdmin = allowed.contains(role) || roles.any(allowed.contains);
//         _isCheckingRole = false;
//       });
//     } catch (e) {
//       setState(() {
//         _isAdmin = false;
//         _isCheckingRole = false;
//       });
//     }
//   }

//   // ─── Phone Validation ──────────────────────────────────────
//   bool _isValidPhone(String phone) {
//     final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
//     // Supports +91XXXXXXXXXX, 91XXXXXXXXXX, or 10-digit
//     return RegExp(r'^(\+?91)?[6-9]\d{9}$').hasMatch(cleaned);
//   }

//   // ─── Load Campaigns from Firestore ─────────────────────────
//   Future<void> _loadCampaigns() async {
//     setState(() => _isLoadingCampaigns = true);
//     try {
//       final snap = await FirebaseFirestore.instance
//           .collection('campaigns')
//           .orderBy('createdAt', descending: true)
//           .limit(50)
//           .get();
//       setState(() {
//         _availableCampaigns = snap.docs.map((d) {
//           final data = d.data();
//           return {
//             'id': d.id,
//             'name': data['name'] ?? data['title'] ?? d.id,
//             'totalLeads': data['totalLeads'] ?? 0,
//             'clientName': data['clientName'] ?? '',
//           };
//         }).toList();
//       });
//     } catch (_) {
//       // Campaign lookup is optional — swallow error silently
//     } finally {
//       if (mounted) setState(() => _isLoadingCampaigns = false);
//     }
//   }

//   Future<void> _onCampaignSelected(String campaignId) async {
//     setState(() => _selectedCampaignId = campaignId);
//     try {
//       final count = await FirebaseFirestore.instance
//           .collection('campaign_leads')
//           .where('campaignId', isEqualTo: campaignId)
//           .where('status', isEqualTo: 'pending')
//           .where('taskId', isNull: true)
//           .count()
//           .get();
//       setState(() {
//         _selectedCampaignLeadCount = count.count ?? 0;
//         _leadsToAllocateController.text = _selectedCampaignLeadCount.toString();
//       });
//     } catch (_) {
//       setState(() => _selectedCampaignLeadCount = 0);
//     }
//   }


//   // ─── Add Lead Dialog ───────────────────────────────────────
//   void _showAddLeadDialog() {
//     final nameCtrl = TextEditingController();
//     final phoneCtrl = TextEditingController();
//     final emailCtrl = TextEditingController();
//     final leadFormKey = GlobalKey<FormState>();

//     showDialog(
//       context: context,
//       builder: (ctx) => AlertDialog(
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//         ),
//         title: const Row(
//           children: [
//             Icon(LucideIcons.userPlus, size: 22, color: AppColors.accent),
//             SizedBox(width: 10),
//             Text(
//               'Add Lead',
//               style: TextStyle(
//                 fontSize: 18,
//                 fontWeight: FontWeight.w700,
//                 color: AppColors.textDark,
//               ),
//             ),
//           ],
//         ),
//         content: Form(
//           key: leadFormKey,
//           child: SingleChildScrollView(
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 TextFormField(
//                   controller: nameCtrl,
//                   decoration: _inputDecor(
//                     label: 'Student Name',
//                     icon: LucideIcons.user,
//                   ),
//                   validator: (v) =>
//                       (v == null || v.trim().isEmpty) ? 'Name required' : null,
//                 ),
//                 const SizedBox(height: AppSizes.md),
//                 TextFormField(
//                   controller: phoneCtrl,
//                   decoration: _inputDecor(
//                     label: 'Phone Number',
//                     icon: LucideIcons.phone,
//                   ),
//                   keyboardType: TextInputType.phone,
//                   validator: (v) {
//                     if (v == null || v.trim().isEmpty) return 'Phone required';
//                     if (!_isValidPhone(v.trim())) return 'Invalid phone number';
//                     return null;
//                   },
//                 ),
//                 const SizedBox(height: AppSizes.md),
//                 TextFormField(
//                   controller: emailCtrl,
//                   decoration: _inputDecor(
//                     label: 'Email (optional)',
//                     icon: LucideIcons.mail,
//                   ),
//                   keyboardType: TextInputType.emailAddress,
//                 ),
//               ],
//             ),
//           ),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(ctx),
//             child: const Text('Cancel'),
//           ),
//           ElevatedButton(
//             style: ElevatedButton.styleFrom(
//               backgroundColor: AppColors.accent,
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(AppSizes.radiusSm),
//               ),
//             ),
//             onPressed: () {
//               if (leadFormKey.currentState!.validate()) {
//                 setState(() {
//                   _leads.add({
//                     'name': nameCtrl.text.trim(),
//                     'phone': phoneCtrl.text.trim(),
//                     'email': emailCtrl.text.trim(),
//                   });
//                 });
//                 Navigator.pop(ctx);
//               }
//             },
//             child: const Text('Add'),
//           ),
//         ],
//       ),
//     );
//   }

//   // ─── Remove Lead ───────────────────────────────────────────
//   void _removeLead(int index) {
//     setState(() {
//       _leads.removeAt(index);
//     });
//   }

//   // ─── Determine if form is valid ────────────────────────────
//   bool get _isFormValid {
//     final title = _titleController.text.trim();
//     final client = _clientController.text.trim();
//     final payoutText = _payoutController.text.trim();
//     final slotsText = _slotsController.text.trim();

//     if (title.isEmpty || client.isEmpty) return false;
//     final payout = double.tryParse(payoutText) ?? 0;
//     final slots = int.tryParse(slotsText) ?? 0;
//     if (payout <= 0 || slots <= 0) return false;
//     return true;
//   }

//   // ─── Submit Form ───────────────────────────────────────────
//   Future<void> _submitForm() async {
//     if (!_formKey.currentState!.validate()) return;
//     if (!_isFormValid) return;

//     setState(() => _isSubmitting = true);

//     try {
//       final user = FirebaseAuth.instance.currentUser;
//       if (user == null) throw Exception('Not authenticated');

//       final payout = double.parse(_payoutController.text.trim());
//       final totalSlots = int.parse(_slotsController.text.trim());

//       // Step 2 & 3: Create task + batch upload leads
//       await _taskService.createTaskWithLeads(
//         predefinedTaskId: _predefinedTaskId,
//         title: _titleController.text.trim(),
//         clientName: _clientController.text.trim(),
//         description: _descriptionController.text.trim(),
//         script: _scriptController.text.trim(),
//         payout: payout,
//         totalSlots: totalSlots,
//         priority: _priority.toLowerCase(),
//         status: _status,
//         adminId: user.uid,
//         totalLeads: _selectedCampaignId != null ? (int.tryParse(_leadsToAllocateController.text.trim()) ?? _selectedCampaignLeadCount) : _leads.length,
//         leads: _leads,
//         campaignId: _selectedCampaignId, // links to client-uploaded campaign
//       );

//       if (!mounted) return;

//       // Step 4: Success message
//       SnackBarUtils.showSuccess('Task created successfully');

//       // Step 5: Navigate to admin dashboard (task list)
//       Navigator.of(context).pushNamedAndRemoveUntil(
//         AppRoutes.adminDashboard,
//         (route) => false,
//       );
//     } catch (e) {
//       if (!mounted) return;
//       SnackBarUtils.showError('Failed: ${e.toString()}');
//     } finally {
//       if (mounted) setState(() => _isSubmitting = false);
//     }
//   }

//   // ─── Input Decoration Helper ───────────────────────────────
//   InputDecoration _inputDecor({
//     required String label,
//     required IconData icon,
//     String? hint,
//   }) {
//     return InputDecoration(
//       labelText: label,
//       hintText: hint,
//       prefixIcon: Icon(icon, size: 20, color: AppColors.textMuted),
//       labelStyle: const TextStyle(
//         color: AppColors.textLabel,
//         fontSize: 14,
//         fontWeight: FontWeight.w500,
//       ),
//       filled: true,
//       fillColor: AppColors.background,
//       border: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(AppSizes.radiusMd),
//         borderSide: BorderSide.none,
//       ),
//       enabledBorder: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(AppSizes.radiusMd),
//         borderSide: const BorderSide(color: AppColors.border),
//       ),
//       focusedBorder: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(AppSizes.radiusMd),
//         borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
//       ),
//       errorBorder: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(AppSizes.radiusMd),
//         borderSide: const BorderSide(color: AppColors.error),
//       ),
//       focusedErrorBorder: OutlineInputBorder(
//         borderRadius: BorderRadius.circular(AppSizes.radiusMd),
//         borderSide: const BorderSide(color: AppColors.error, width: 1.5),
//       ),
//       contentPadding: const EdgeInsets.symmetric(
//         horizontal: AppSizes.base,
//         vertical: AppSizes.base,
//       ),
//     );
//   }

//   // ─── Build ─────────────────────────────────────────────────
//   @override
//   Widget build(BuildContext context) {
//     // Loading role check
//     if (_isCheckingRole) {
//       return const Scaffold(
//         body: Center(
//           child: CircularProgressIndicator(
//             color: AppColors.primary,
//             strokeWidth: 2.5,
//           ),
//         ),
//       );
//     }

//     // Access denied
//     if (!_isAdmin) {
//       return Scaffold(
//         backgroundColor: AppColors.background,
//         appBar: AppBar(
//           backgroundColor: AppColors.primary,
//           foregroundColor: Colors.white,
//           elevation: 0,
//           title: const Text('Access Denied'),
//         ),
//         body: Center(
//           child: Padding(
//             padding: const EdgeInsets.all(AppSizes.xxl),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Container(
//                   padding: const EdgeInsets.all(AppSizes.xl),
//                   decoration: const BoxDecoration(
//                     color: AppColors.errorBg,
//                     shape: BoxShape.circle,
//                   ),
//                   child: const Icon(
//                     LucideIcons.shieldOff,
//                     size: 48,
//                     color: AppColors.error,
//                   ),
//                 ),
//                 const SizedBox(height: AppSizes.xl),
//                 const Text(
//                   'Access Denied',
//                   style: TextStyle(
//                     fontSize: 22,
//                     fontWeight: FontWeight.w700,
//                     color: AppColors.textDark,
//                   ),
//                 ),
//                 const SizedBox(height: AppSizes.sm),
//                 const Text(
//                   'Only administrators can create tasks.\nPlease contact support if this is an error.',
//                   textAlign: TextAlign.center,
//                   style: TextStyle(
//                     fontSize: 14,
//                     color: AppColors.textMuted,
//                   ),
//                 ),
//                 const SizedBox(height: AppSizes.xl),
//                 OutlinedButton.icon(
//                   onPressed: () => Navigator.pop(context),
//                   icon: const Icon(LucideIcons.arrowLeft, size: 18),
//                   label: const Text('Go Back'),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       );
//     }

//     // Admin UI
//     return Scaffold(
//       backgroundColor: AppColors.background,
//       appBar: AppBar(
//         backgroundColor: AppColors.primary,
//         foregroundColor: Colors.white,
//         elevation: 0,
//         title: const Row(
//           children: [
//             Icon(LucideIcons.filePlus, size: 22),
//             SizedBox(width: 10),
//             Text(
//               'Create Task',
//               style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
//             ),
//           ],
//         ),
//       ),
//       body: GestureDetector(
//         onTap: () => FocusScope.of(context).unfocus(),
//         child: SingleChildScrollView(
//           padding: const EdgeInsets.symmetric(
//             horizontal: AppSizes.screenPaddingH,
//             vertical: AppSizes.screenPaddingV,
//           ),
//           child: Form(
//             key: _formKey,
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 // Deprecation Banner
//                 Container(
//                   width: double.infinity,
//                   padding: const EdgeInsets.all(AppSizes.md),
//                   decoration: BoxDecoration(
//                     color: AppColors.warning.withValues(alpha: 0.1),
//                     borderRadius: BorderRadius.circular(AppSizes.radiusMd),
//                     border: Border.all(color: AppColors.warning),
//                   ),
//                   child: const Row(
//                     children: [
//                       Icon(LucideIcons.alertTriangle, color: AppColors.warning),
//                       SizedBox(width: AppSizes.md),
//                       Expanded(
//                         child: Text(
//                           'DEPRECATED: Task creation is moving to the new Web Portal. This screen will be removed in a future update.',
//                           style: TextStyle(
//                             color: AppColors.warning,
//                             fontWeight: FontWeight.w600,
//                             fontSize: 13,
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//                 const SizedBox(height: AppSizes.md),
//                 // ── Section: Task Details ─────────────────────
//                 _sectionHeader('Task Details', LucideIcons.clipboardList),
//                 const SizedBox(height: AppSizes.md),

//                 _buildCard(
//                   children: [
//                     // Title
//                     TextFormField(
//                       controller: _titleController,
//                       style: const TextStyle(color: AppColors.textDark),
//                       decoration: _inputDecor(
//                         label: 'Task Title',
//                         icon: LucideIcons.type,
//                         hint: 'e.g. DSA Course Promotion Call',
//                       ),
//                       validator: (v) => (v == null || v.trim().isEmpty)
//                           ? 'Title is required'
//                           : null,
//                       onChanged: (_) => setState(() {}),
//                     ),
//                     const SizedBox(height: AppSizes.base),

//                     // Client Name
//                     TextFormField(
//                       controller: _clientController,
//                       style: const TextStyle(color: AppColors.textDark),
//                       decoration: _inputDecor(
//                         label: 'Client Name',
//                         icon: LucideIcons.building,
//                         hint: 'e.g. Sherize Academy',
//                       ),
//                       validator: (v) => (v == null || v.trim().isEmpty)
//                           ? 'Client name is required'
//                           : null,
//                       onChanged: (_) => setState(() {}),
//                     ),
//                     const SizedBox(height: AppSizes.base),

//                     // Description
//                     TextFormField(
//                       controller: _descriptionController,
//                       style: const TextStyle(color: AppColors.textDark),
//                       decoration: _inputDecor(
//                         label: 'Task Description',
//                         icon: LucideIcons.alignLeft,
//                         hint: 'Describe the task in detail...',
//                       ),
//                       maxLines: 4,
//                       textInputAction: TextInputAction.newline,
//                     ),
//                     const SizedBox(height: AppSizes.base),

//                     // Script
//                     TextFormField(
//                       controller: _scriptController,
//                       style: const TextStyle(color: AppColors.textDark),
//                       decoration: _inputDecor(
//                         label: 'Call Script',
//                         icon: LucideIcons.fileText,
//                         hint:
//                             'Hello, this is from [Client Name]...\nProvide the full call script here.',
//                       ),
//                       maxLines: 5,
//                       textInputAction: TextInputAction.newline,
//                     ),
//                   ],
//                 ),

//                 const SizedBox(height: AppSizes.xl),

//                 // ── Section: Link Campaign (optional) ──────────
//                 _sectionHeader('Link Campaign', LucideIcons.link),
//                 const SizedBox(height: AppSizes.md),

//                 _buildCard(
//                   children: [
//                     if (_isLoadingCampaigns)
//                       const Center(
//                         child: Padding(
//                           padding: EdgeInsets.all(AppSizes.base),
//                           child: CircularProgressIndicator(strokeWidth: 2),
//                         ),
//                       )
//                     else if (_availableCampaigns.isEmpty)
//                       const Text(
//                         'No campaigns found. Upload leads below to create a standalone task.',
//                         style: TextStyle(
//                             color: AppColors.textMuted, fontSize: 13),
//                       )
//                     else ...[
//                       DropdownButtonFormField<String>(
//                         initialValue: _selectedCampaignId,
//                         style: const TextStyle(color: AppColors.textDark),
//                         decoration: _inputDecor(
//                           label: 'Select Campaign (optional)',
//                           icon: LucideIcons.layers,
//                         ),
//                         items: [
//                           const DropdownMenuItem<String>(
//                             value: null,
//                             child: Text('— None (upload leads below) —'),
//                           ),
//                           ..._availableCampaigns
//                               .map((c) => DropdownMenuItem<String>(
//                                     value: c['id'] as String,
//                                     child: Text(
//                                       '${c['name']} · ${c['clientName']}',
//                                       overflow: TextOverflow.ellipsis,
//                                     ),
//                                   )),
//                         ],
//                         onChanged: (val) {
//                           if (val == null) {
//                             setState(() {
//                               _selectedCampaignId = null;
//                               _selectedCampaignLeadCount = 0;
//                             });
//                           } else {
//                             _onCampaignSelected(val);
//                           }
//                         },
//                       ),
//                       if (_selectedCampaignId != null) ...[
//                         const SizedBox(height: AppSizes.sm),
//                         Row(
//                           children: [
//                             const Icon(LucideIcons.users,
//                                 size: 14, color: AppColors.textMuted),
//                             const SizedBox(width: 6),
//                             Text(
//                               '$_selectedCampaignLeadCount leads in this campaign',
//                               style: const TextStyle(
//                                   fontSize: 13,
//                                   color: AppColors.textMuted),
//                             ),
//                           ],
//                         ),
//                       ],
//                     ],
//                   ],
//                 ),

//                 const SizedBox(height: AppSizes.xl),

//                 // ── Section: Payout ────────────────────────────
//                 _sectionHeader('Payout & Slots', LucideIcons.indianRupee),
//                 const SizedBox(height: AppSizes.md),

//                 _buildCard(
//                   children: [
//                     Row(
//                       children: [
//                         Expanded(
//                           child: TextFormField(
//                             controller: _payoutController,
//                             style: const TextStyle(color: AppColors.textDark),
//                             decoration: _inputDecor(
//                               label: 'Payout / Call (₹)',
//                               icon: LucideIcons.indianRupee,
//                               hint: '20',
//                             ),
//                             keyboardType: const TextInputType.numberWithOptions(
//                                 decimal: true),
//                             inputFormatters: [
//                               FilteringTextInputFormatter.allow(
//                                   RegExp(r'^\d*\.?\d{0,2}')),
//                             ],
//                             validator: (v) {
//                               if (v == null || v.trim().isEmpty) {
//                                 return 'Required';
//                               }
//                               final val = double.tryParse(v.trim());
//                               if (val == null || val <= 0) {
//                                 return 'Must be > 0';
//                               }
//                               final maxPayout = context.read<PlatformSettingsService>().maxTaskPayout;
//                               if (val > maxPayout) {
//                                 return 'Max payout is ₹$maxPayout';
//                               }
//                               return null;
//                             },
//                             onChanged: (_) => setState(() {}),
//                           ),
//                         ),
//                         const SizedBox(width: AppSizes.md),
//                         Expanded(
//                           child: TextFormField(
//                             controller: _slotsController,
//                             style: const TextStyle(color: AppColors.textDark),
//                             decoration: _inputDecor(
//                               label: 'Total Slots',
//                               icon: LucideIcons.users,
//                               hint: '100',
//                             ),
//                             keyboardType: TextInputType.number,
//                             inputFormatters: [
//                               FilteringTextInputFormatter.digitsOnly,
//                             ],
//                             validator: (v) {
//                               if (v == null || v.trim().isEmpty) {
//                                 return 'Required';
//                               }
//                               final val = int.tryParse(v.trim());
//                               if (val == null || val <= 0) {
//                                 return 'Must be > 0';
//                               }
//                               return null;
//                             },
//                             onChanged: (_) => setState(() {}),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),

//                 const SizedBox(height: AppSizes.xl),

//                 // ── Section: Configuration ────────────────────
//                 _sectionHeader('Configuration', LucideIcons.settings),
//                 const SizedBox(height: AppSizes.md),

//                 _buildCard(
//                   children: [
//                     // Priority Dropdown
//                     DropdownButtonFormField<String>(
//                       initialValue: _priority,
//                       style: const TextStyle(color: AppColors.textDark),
//                       decoration: _inputDecor(
//                         label: 'Priority Level',
//                         icon: LucideIcons.flag,
//                       ),
//                       items: ['Low', 'Medium', 'High']
//                           .map((p) => DropdownMenuItem(
//                                 value: p,
//                                 child: Row(
//                                   children: [
//                                     Container(
//                                       width: 8,
//                                       height: 8,
//                                       decoration: BoxDecoration(
//                                         color: _priorityColor(p),
//                                         shape: BoxShape.circle,
//                                       ),
//                                     ),
//                                     const SizedBox(width: 10),
//                                     Text(p),
//                                   ],
//                                 ),
//                               ))
//                           .toList(),
//                       onChanged: (v) => setState(() => _priority = v!),
//                     ),
//                     const SizedBox(height: AppSizes.base),

//                     // Status Dropdown
//                     DropdownButtonFormField<String>(
//                       initialValue: _status,
//                       style: const TextStyle(color: AppColors.textDark),
//                       decoration: _inputDecor(
//                         label: 'Task Status',
//                         icon: LucideIcons.toggleRight,
//                       ),
//                       items: [
//                         DropdownMenuItem(
//                           value: 'active',
//                           child: Row(
//                             children: [
//                               Container(
//                                 width: 8,
//                                 height: 8,
//                                 decoration: const BoxDecoration(
//                                   color: AppColors.success,
//                                   shape: BoxShape.circle,
//                                 ),
//                               ),
//                               const SizedBox(width: 10),
//                               const Text('Active'),
//                             ],
//                           ),
//                         ),
//                         DropdownMenuItem(
//                           value: 'inactive',
//                           child: Row(
//                             children: [
//                               Container(
//                                 width: 8,
//                                 height: 8,
//                                 decoration: const BoxDecoration(
//                                   color: AppColors.textMuted,
//                                   shape: BoxShape.circle,
//                                 ),
//                               ),
//                               const SizedBox(width: 10),
//                               const Text('Inactive'),
//                             ],
//                           ),
//                         ),
//                       ],
//                       onChanged: (v) => setState(() => _status = v!),
//                     ),
//                   ],
//                 ),

//                 const SizedBox(height: AppSizes.xl),

//                 // ── Section: Lead Upload ──────────────────────
//                 _sectionHeader(
//                     'Lead Upload (Optional)', LucideIcons.uploadCloud),
//                 const SizedBox(height: AppSizes.md),

//                 _buildCard(
//                   children: [
//                     // Buttons Row
//                     Row(
//                       children: [
//                         Expanded(
//                           child: ElevatedButton.icon(
//                             onPressed:
//                                 _isParsing ? null : _pickAndUploadLeadSheet,
//                             style: ElevatedButton.styleFrom(
//                               backgroundColor: AppColors.primary,
//                               foregroundColor: Colors.white,
//                               shape: RoundedRectangleBorder(
//                                 borderRadius:
//                                     BorderRadius.circular(AppSizes.radiusSm),
//                               ),
//                               padding: const EdgeInsets.symmetric(
//                                 vertical: AppSizes.md,
//                               ),
//                             ),
//                             icon: const Icon(LucideIcons.fileSpreadsheet,
//                                 size: 18),
//                             label: const Text('Upload CSV/XLSX'),
//                           ),
//                         ),
//                         const SizedBox(width: AppSizes.base),
//                         Expanded(
//                           child: OutlinedButton.icon(
//                             onPressed: _isParsing ? null : _showAddLeadDialog,
//                             style: OutlinedButton.styleFrom(
//                               foregroundColor: AppColors.accent,
//                               side: const BorderSide(color: AppColors.accent),
//                               shape: RoundedRectangleBorder(
//                                 borderRadius:
//                                     BorderRadius.circular(AppSizes.radiusSm),
//                               ),
//                               padding: const EdgeInsets.symmetric(
//                                 vertical: AppSizes.md,
//                               ),
//                             ),
//                             icon: const Icon(LucideIcons.userPlus, size: 18),
//                             label: const Text('Add Manually'),
//                           ),
//                         ),
//                       ],
//                     ),

//                     if (_isParsing) ...[
//                       const SizedBox(height: AppSizes.md),
//                       Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Row(
//                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                             children: [
//                               Text(
//                                 _uploadStatus,
//                                 style: const TextStyle(
//                                   fontSize: 14,
//                                   color: AppColors.textDark,
//                                   fontWeight: FontWeight.w600,
//                                 ),
//                               ),
//                               Text(
//                                 '${(_uploadProgress * 100).toStringAsFixed(0)}%',
//                                 style: const TextStyle(
//                                   fontSize: 14,
//                                   color: AppColors.primary,
//                                   fontWeight: FontWeight.w700,
//                                 ),
//                               ),
//                             ],
//                           ),
//                           const SizedBox(height: AppSizes.xs),
//                           LinearProgressIndicator(
//                             value: _uploadProgress,
//                             backgroundColor: AppColors.border,
//                             color: AppColors.primary,
//                             minHeight: 6,
//                             borderRadius:
//                                 BorderRadius.circular(AppSizes.radiusSm),
//                           ),
//                         ],
//                       ),
//                     ],

//                     if (_leads.isNotEmpty) ...[
//                       const SizedBox(height: AppSizes.base),
//                       Container(
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: AppSizes.md,
//                           vertical: AppSizes.sm,
//                         ),
//                         decoration: BoxDecoration(
//                           color: AppColors.infoBg,
//                           borderRadius:
//                               BorderRadius.circular(AppSizes.radiusSm),
//                         ),
//                         child: Row(
//                           children: [
//                             const Icon(LucideIcons.info,
//                                 size: 16, color: AppColors.info),
//                             const SizedBox(width: 8),
//                             Text(
//                               '${_leads.length} lead${_leads.length > 1 ? 's' : ''} added',
//                               style: const TextStyle(
//                                 color: AppColors.info,
//                                 fontSize: 13,
//                                 fontWeight: FontWeight.w600,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                       const SizedBox(height: AppSizes.md),

//                       // Lead List
//                       ...List.generate(_leads.length, (i) {
//                         final lead = _leads[i];
//                         return Container(
//                           margin: const EdgeInsets.only(bottom: AppSizes.sm),
//                           padding: const EdgeInsets.all(AppSizes.md),
//                           decoration: BoxDecoration(
//                             color: AppColors.surfaceVariant,
//                             borderRadius:
//                                 BorderRadius.circular(AppSizes.radiusSm),
//                             border: flutter.Border.all(color: AppColors.border),
//                           ),
//                           child: Row(
//                             children: [
//                               Container(
//                                 width: 36,
//                                 height: 36,
//                                 decoration: BoxDecoration(
//                                   color:
//                                       AppColors.accent.withValues(alpha: 0.1),
//                                   borderRadius:
//                                       BorderRadius.circular(AppSizes.radiusSm),
//                                 ),
//                                 child: Center(
//                                   child: Text(
//                                     '${i + 1}',
//                                     style: const TextStyle(
//                                       color: AppColors.accent,
//                                       fontWeight: FontWeight.w700,
//                                       fontSize: 14,
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                               const SizedBox(width: AppSizes.md),
//                               Expanded(
//                                 child: Column(
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     Text(
//                                       lead['name'] ?? '',
//                                       style: const TextStyle(
//                                         color: AppColors.textDark,
//                                         fontSize: 14,
//                                         fontWeight: FontWeight.w600,
//                                       ),
//                                     ),
//                                     const SizedBox(height: 2),
//                                     Text(
//                                       lead['phone'] ?? '',
//                                       style: const TextStyle(
//                                         color: AppColors.textMuted,
//                                         fontSize: 12,
//                                       ),
//                                     ),
//                                     if (lead['email']?.isNotEmpty == true)
//                                       Text(
//                                         lead['email']!,
//                                         style: const TextStyle(
//                                           color: AppColors.textMuted,
//                                           fontSize: 12,
//                                         ),
//                                       ),
//                                   ],
//                                 ),
//                               ),
//                               IconButton(
//                                 onPressed: () => _removeLead(i),
//                                 icon: const Icon(LucideIcons.trash2,
//                                     size: 18, color: AppColors.error),
//                                 tooltip: 'Remove lead',
//                               ),
//                             ],
//                           ),
//                         );
//                       }),
//                     ],
//                   ],
//                 ),

//                 const SizedBox(height: AppSizes.xxl),

//                 // ── Create Task Button ────────────────────────
//                 SizedBox(
//                   width: double.infinity,
//                   height: AppSizes.buttonHeight,
//                   child: ElevatedButton(
//                     onPressed:
//                         (_isSubmitting || !_isFormValid) ? null : _submitForm,
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: AppColors.accent,
//                       foregroundColor: Colors.white,
//                       disabledBackgroundColor:
//                           AppColors.accent.withValues(alpha: 0.4),
//                       disabledForegroundColor: Colors.white70,
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(AppSizes.radiusMd),
//                       ),
//                       elevation: _isFormValid ? 2 : 0,
//                       shadowColor: AppColors.accent.withValues(alpha: 0.3),
//                     ),
//                     child: _isSubmitting
//                         ? const SizedBox(
//                             width: 24,
//                             height: 24,
//                             child: CircularProgressIndicator(
//                               color: Colors.white,
//                               strokeWidth: 2.5,
//                             ),
//                           )
//                         : const Row(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: [
//                               Icon(LucideIcons.plus, size: 20),
//                               SizedBox(width: 10),
//                               Text(
//                                 'Create Task',
//                                 style: TextStyle(
//                                   fontSize: 16,
//                                   fontWeight: FontWeight.w700,
//                                 ),
//                               ),
//                             ],
//                           ),
//                   ),
//                 ),

//                 const SizedBox(height: AppSizes.xxl),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   // ─── Section Header Widget ─────────────────────────────────
//   Widget _sectionHeader(String title, IconData icon) {
//     return Row(
//       children: [
//         Container(
//           padding: const EdgeInsets.all(8),
//           decoration: BoxDecoration(
//             color: AppColors.accent.withValues(alpha: 0.1),
//             borderRadius: BorderRadius.circular(AppSizes.radiusSm),
//           ),
//           child: Icon(icon, size: 18, color: AppColors.accent),
//         ),
//         const SizedBox(width: AppSizes.md),
//         Text(
//           title,
//           style: const TextStyle(
//             fontSize: 17,
//             fontWeight: FontWeight.w700,
//             color: AppColors.textDark,
//           ),
//         ),
//       ],
//     );
//   }

//   // ─── Card Wrapper ──────────────────────────────────────────
//   Widget _buildCard({required List<Widget> children}) {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(AppSizes.lg),
//       decoration: BoxDecoration(
//         color: AppColors.surface,
//         borderRadius: BorderRadius.circular(AppSizes.radiusMd),
//         border: flutter.Border.all(color: AppColors.border),
//         boxShadow: [
//           BoxShadow(
//             color: AppColors.primary.withValues(alpha: 0.03),
//             blurRadius: 10,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: children,
//       ),
//     );
//   }

//   // ─── Priority Color Helper ─────────────────────────────────
//   Color _priorityColor(String priority) {
//     switch (priority.toLowerCase()) {
//       case 'high':
//         return AppColors.error;
//       case 'medium':
//         return AppColors.warning;
//       case 'low':
//         return AppColors.success;
//       default:
//         return AppColors.textMuted;
//     }
//   }
// }



import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as flutter;
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/constants.dart';
import '../../services/task_service.dart';
import '../../services/platform_settings_service.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../routes.dart';
 
/// Admin Task Creation Screen.
///
/// Provides a clean form for admins to create new calling tasks
/// that appear in the Worker Task Marketplace.
class AdminCreateTaskScreen extends StatefulWidget {
  const AdminCreateTaskScreen({Key? key}) : super(key: key);
 
  @override
  State<AdminCreateTaskScreen> createState() => _AdminCreateTaskScreenState();
}
 
class _AdminCreateTaskScreenState extends State<AdminCreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _taskService = TaskService();
 
  // ─── Controllers ───────────────────────────────────────────
  final _titleController = TextEditingController();
  final _clientController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _scriptController = TextEditingController();
  final _payoutController = TextEditingController();
  final _slotsController = TextEditingController();
  final _leadsToAllocateController = TextEditingController();
 
  // ─── Dropdown Values ───────────────────────────────────────
  String _priority = 'Medium';
  String _status = 'active';
 
  // ─── Leads ─────────────────────────────────────────────────
  final List<Map<String, String>> _leads = [];
 
  // ─── Campaign Picker ────────────────────────────────────────
  List<Map<String, dynamic>> _availableCampaigns = [];
  String? _selectedCampaignId;
  int _selectedCampaignLeadCount = 0;
  bool _isLoadingCampaigns = false;
 
  // ─── State ─────────────────────────────────────────────────
  bool _isSubmitting = false;
  bool _isAdmin = false;
  bool _isCheckingRole = true;
 
  bool _isParsing = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';
  late String _predefinedTaskId;
 
  @override
  void initState() {
    super.initState();
    _predefinedTaskId = FirebaseFirestore.instance.collection('tasks').doc().id;
    _verifyAdminRole();
    _loadCampaigns();
  }
 
  @override
  void dispose() {
    _titleController.dispose();
    _clientController.dispose();
    _descriptionController.dispose();
    _scriptController.dispose();
    _payoutController.dispose();
    _slotsController.dispose();
    _leadsToAllocateController.dispose();
    super.dispose();
  }
 
  // ─── Lead Upload & Parsing ─────────────────────────────────
  Future<void> _pickAndUploadLeadSheet() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        withData: true,
      );
 
      if (result == null || result.files.isEmpty) return;
 
      final file = result.files.first;
      final fileBytes = file.bytes;
      final fileName = file.name;
 
      if (fileBytes == null) {
        _showError('Unable to read file content.');
        return;
      }
 
      setState(() {
        _isParsing = true;
        _uploadStatus = 'Uploading...';
      });
 
      // 1. Upload to Storage
      // Use campaignId path when linked to a campaign, otherwise taskId
      final leadOwnerId = _selectedCampaignId ?? _predefinedTaskId;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('lead_sheets')
          .child(leadOwnerId)
          .child(fileName);
 
      final uploadTask = storageRef.putData(
        fileBytes,
        SettableMetadata(contentType: 'application/octet-stream'),
      );
 
      uploadTask.snapshotEvents.listen((event) {
        final progress = event.bytesTransferred / event.totalBytes;
        if (mounted) {
          setState(() {
            _uploadProgress = progress;
          });
        }
      });
 
      await uploadTask;
 
      // 2. Parse File
      if (mounted) {
        setState(() {
          _uploadStatus = 'Parsing file...';
          _uploadProgress = 0.0;
        });
      }
 
      List<Map<String, String>> newLeads = [];
 
      if (fileName.toLowerCase().endsWith('.csv')) {
        final csvString = utf8.decode(fileBytes);
        final rows = const CsvToListConverter().convert(csvString);
        if (rows.isNotEmpty) {
          final headers =
              rows.first.map((e) => e.toString().toLowerCase().trim()).toList();
          for (int i = 1; i < rows.length; i++) {
            final leadData = _extractLeadFromRow(headers, rows[i]);
            if (leadData != null) newLeads.add(leadData);
          }
        }
      } else if (fileName.toLowerCase().endsWith('.xlsx') ||
          fileName.toLowerCase().endsWith('.xls')) {
        var excelParser = Excel.decodeBytes(fileBytes);
        for (var table in excelParser.tables.keys) {
          final sheet = excelParser.tables[table];
          if (sheet == null || sheet.maxRows == 0) continue;
 
          final headers = sheet
              .row(0)
              .map((e) => e?.value?.toString().toLowerCase().trim() ?? '')
              .toList();
          for (int i = 1; i < sheet.maxRows; i++) {
            final row = sheet.row(i).map((e) => e?.value).toList();
            final leadData = _extractLeadFromRow(headers, row);
            if (leadData != null) newLeads.add(leadData);
          }
          break; // Process first sheet only
        }
      }
 
      if (mounted) {
        setState(() {
          _leads.addAll(newLeads);
          _isParsing = false;
          _uploadStatus = '';
          _uploadProgress = 0.0;
        });
 
        if (newLeads.isNotEmpty) {
          _showSuccess('Successfully loaded ${newLeads.length} leads!');
        } else {
          _showError(
              'No valid leads found in file (Need at least Name and Phone).');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isParsing = false;
          _uploadStatus = '';
        });
        _showError('Upload or parsing failed: $e');
      }
    }
  }
 
  Map<String, String>? _extractLeadFromRow(
      List<String> headers, List<dynamic> row) {
    String name = '';
    String phone = '';
    String email = '';
    String city = '';
 
    for (int j = 0; j < headers.length; j++) {
      if (j >= row.length) break;
      final val = row[j]?.toString().trim() ?? '';
      if (val.isEmpty) continue;
 
      final header = headers[j];
 
      if (header.contains('name') || header.contains('student')) {
        name = val;
      } else if (header.contains('phone') ||
          header.contains('mobile') ||
          header.contains('contact') ||
          header.contains('no')) {
        phone = val;
      } else if (header.contains('email') || header.contains('mail')) {
        email = val;
      } else if (header.contains('city') || header.contains('location')) {
        city = val;
      }
    }
 
    if (name.isNotEmpty && phone.isNotEmpty) {
      // Basic formatting to catch purely numeric fields imported incorrectly
      return {
        'name': name,
        'phone': phone.replaceAll(RegExp(r'[^0-9+]'), ''),
        'email': email,
        'city': city,
      };
    }
    return null;
  }
 
  void _showError(String message) {
    SnackBarUtils.showError(message);
  }
  void _showSuccess(String message) {
    SnackBarUtils.showSuccess(message);
  }
 
  // ─── Admin Role Verification ───────────────────────────────
  Future<void> _verifyAdminRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isAdmin = false;
          _isCheckingRole = false;
        });
        return;
      }
 
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
 
      final data = userDoc.data() ?? {};
      final role = (data['role'] ?? '').toString().toLowerCase();
      final roles = (data['roles'] is List)
          ? (data['roles'] as List).map((e) => e.toString().toLowerCase())
          : const <String>[];
      // Full admins (admin / super_admin) may create tasks. Matches the
      // dashboard's superView gate and the Firestore rules (isAdmin()).
      const allowed = {'admin', 'super_admin'};
 
      setState(() {
        _isAdmin = allowed.contains(role) || roles.any(allowed.contains);
        _isCheckingRole = false;
      });
    } catch (e) {
      setState(() {
        _isAdmin = false;
        _isCheckingRole = false;
      });
    }
  }
 
  // ─── Phone Validation ──────────────────────────────────────
  bool _isValidPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    // Supports +91XXXXXXXXXX, 91XXXXXXXXXX, or 10-digit
    return RegExp(r'^(\+?91)?[6-9]\d{9}$').hasMatch(cleaned);
  }
 
  // ─── Load Campaigns from Firestore ─────────────────────────
  Future<void> _loadCampaigns() async {
    setState(() => _isLoadingCampaigns = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('campaigns')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      setState(() {
        _availableCampaigns = snap.docs.map((d) {
          final data = d.data();
          return {
            'id': d.id,
            'name': data['name'] ?? data['title'] ?? d.id,
            'totalLeads': data['totalLeads'] ?? 0,
            'clientName': data['clientName'] ?? '',
          };
        }).toList();
      });
    } catch (_) {
      // Campaign lookup is optional — swallow error silently
    } finally {
      if (mounted) setState(() => _isLoadingCampaigns = false);
    }
  }
 
  Future<void> _onCampaignSelected(String campaignId) async {
    setState(() => _selectedCampaignId = campaignId);
    try {
      final count = await FirebaseFirestore.instance
          .collection('campaign_leads')
          .where('campaignId', isEqualTo: campaignId)
          .where('status', isEqualTo: 'pending')
          .where('taskId', isNull: true)
          .count()
          .get();
      setState(() {
        _selectedCampaignLeadCount = count.count ?? 0;
        _leadsToAllocateController.text = _selectedCampaignLeadCount.toString();
      });
    } catch (_) {
      setState(() => _selectedCampaignLeadCount = 0);
    }
  }
 
 
  // ─── Add Lead Dialog ───────────────────────────────────────
  void _showAddLeadDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final leadFormKey = GlobalKey<FormState>();
 
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(LucideIcons.userPlus,
                  size: 20, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            const Text(
              'Add Lead',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        content: Form(
          key: leadFormKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                TextFormField(
                  controller: nameCtrl,
                  decoration: _inputDecor(
                    label: 'Student Name',
                    icon: LucideIcons.user,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name required' : null,
                ),
                const SizedBox(height: AppSizes.md),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: _inputDecor(
                    label: 'Phone Number',
                    icon: LucideIcons.phone,
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Phone required';
                    if (!_isValidPhone(v.trim())) return 'Invalid phone number';
                    return null;
                  },
                ),
                const SizedBox(height: AppSizes.md),
                TextFormField(
                  controller: emailCtrl,
                  decoration: _inputDecor(
                    label: 'Email (optional)',
                    icon: LucideIcons.mail,
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              if (leadFormKey.currentState!.validate()) {
                setState(() {
                  _leads.add({
                    'name': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim(),
                    'email': emailCtrl.text.trim(),
                  });
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
 
  // ─── Remove Lead ───────────────────────────────────────────
  void _removeLead(int index) {
    setState(() {
      _leads.removeAt(index);
    });
  }
 
  // ─── Determine if form is valid ────────────────────────────
  bool get _isFormValid {
    final title = _titleController.text.trim();
    final client = _clientController.text.trim();
    final payoutText = _payoutController.text.trim();
    final slotsText = _slotsController.text.trim();
 
    if (title.isEmpty || client.isEmpty) return false;
    final payout = double.tryParse(payoutText) ?? 0;
    final slots = int.tryParse(slotsText) ?? 0;
    if (payout <= 0 || slots <= 0) return false;
    return true;
  }
 
  // ─── Submit Form ───────────────────────────────────────────
  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isFormValid) return;
 
    setState(() => _isSubmitting = true);
 
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');
 
      final payout = double.parse(_payoutController.text.trim());
      final totalSlots = int.parse(_slotsController.text.trim());
 
      // Step 2 & 3: Create task + batch upload leads
      await _taskService.createTaskWithLeads(
        predefinedTaskId: _predefinedTaskId,
        title: _titleController.text.trim(),
        clientName: _clientController.text.trim(),
        description: _descriptionController.text.trim(),
        script: _scriptController.text.trim(),
        payout: payout,
        totalSlots: totalSlots,
        priority: _priority.toLowerCase(),
        status: _status,
        adminId: user.uid,
        totalLeads: _selectedCampaignId != null ? (int.tryParse(_leadsToAllocateController.text.trim()) ?? _selectedCampaignLeadCount) : _leads.length,
        leads: _leads,
        campaignId: _selectedCampaignId, // links to client-uploaded campaign
      );
 
      if (!mounted) return;
 
      // Step 4: Success message
      SnackBarUtils.showSuccess('Task created successfully');
 
      // Step 5: Navigate to admin dashboard (task list)
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.adminDashboard,
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
 
  // ─── Input Decoration Helper ───────────────────────────────
  InputDecoration _inputDecor({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20, color: AppColors.textMuted),
      labelStyle: const TextStyle(
        color: AppColors.textLabel,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 14,
      ),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSizes.base,
        vertical: AppSizes.base,
      ),
    );
  }
 
  // ─── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Loading role check
    if (_isCheckingRole) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2.5,
          ),
        ),
      );
    }
 
    // Access denied
    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Access Denied'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSizes.xl),
                  decoration: const BoxDecoration(
                    color: AppColors.errorBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.shieldOff,
                    size: 48,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: AppSizes.xl),
                const Text(
                  'Access Denied',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                const Text(
                  'Only administrators can create tasks.\nPlease contact support if this is an error.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: AppSizes.xl),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.arrowLeft, size: 18),
                  label: const Text('Go Back'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
 
    // Admin UI
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          children: [
            Icon(LucideIcons.filePlus, size: 22),
            SizedBox(width: 10),
            Text(
              'Create Task',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPaddingH,
            vertical: AppSizes.screenPaddingV,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Deprecation Banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSizes.md),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.6)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(LucideIcons.alertTriangle,
                              size: 20, color: AppColors.warning),
                          SizedBox(width: AppSizes.md),
                          Expanded(
                            child: Text(
                              'DEPRECATED: Task creation is moving to the new Web Portal. This screen will be removed in a future update.',
                              style: TextStyle(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.lg),
                    // ── Section: Task Details ─────────────────────
                    _sectionHeader('Task Details', LucideIcons.clipboardList),
                    const SizedBox(height: AppSizes.md),
 
                    _buildCard(
                      children: [
                        // Title
                        TextFormField(
                          controller: _titleController,
                          style: const TextStyle(color: AppColors.textDark),
                          decoration: _inputDecor(
                            label: 'Task Title',
                            icon: LucideIcons.type,
                            hint: 'e.g. DSA Course Promotion Call',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Title is required'
                              : null,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSizes.base),
 
                        // Client Name
                        TextFormField(
                          controller: _clientController,
                          style: const TextStyle(color: AppColors.textDark),
                          decoration: _inputDecor(
                            label: 'Client Name',
                            icon: LucideIcons.building,
                            hint: 'e.g. Sherize Academy',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Client name is required'
                              : null,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSizes.base),
 
                        // Description
                        TextFormField(
                          controller: _descriptionController,
                          style: const TextStyle(color: AppColors.textDark),
                          decoration: _inputDecor(
                            label: 'Task Description',
                            icon: LucideIcons.alignLeft,
                            hint: 'Describe the task in detail...',
                          ),
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                        ),
                        const SizedBox(height: AppSizes.base),
 
                        // Script
                        TextFormField(
                          controller: _scriptController,
                          style: const TextStyle(color: AppColors.textDark),
                          decoration: _inputDecor(
                            label: 'Call Script',
                            icon: LucideIcons.fileText,
                            hint:
                                'Hello, this is from [Client Name]...\nProvide the full call script here.',
                          ),
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                        ),
                      ],
                    ),
 
                    const SizedBox(height: AppSizes.xl),
 
                    // ── Section: Link Campaign (optional) ──────────
                    _sectionHeader('Link Campaign', LucideIcons.link),
                    const SizedBox(height: AppSizes.md),
 
                    _buildCard(
                      children: [
                        if (_isLoadingCampaigns)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(AppSizes.base),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (_availableCampaigns.isEmpty)
                          const Text(
                            'No campaigns found. Upload leads below to create a standalone task.',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                                height: 1.4),
                          )
                        else ...[
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _selectedCampaignId,
                            style: const TextStyle(color: AppColors.textDark),
                            decoration: _inputDecor(
                              label: 'Select Campaign (optional)',
                              icon: LucideIcons.layers,
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('— None (upload leads below) —'),
                              ),
                              ..._availableCampaigns
                                  .map((c) => DropdownMenuItem<String>(
                                        value: c['id'] as String,
                                        child: Text(
                                          '${c['name']} · ${c['clientName']}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )),
                            ],
                            onChanged: (val) {
                              if (val == null) {
                                setState(() {
                                  _selectedCampaignId = null;
                                  _selectedCampaignLeadCount = 0;
                                });
                              } else {
                                _onCampaignSelected(val);
                              }
                            },
                          ),
                          if (_selectedCampaignId != null) ...[
                            const SizedBox(height: AppSizes.md),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.users,
                                      size: 14, color: AppColors.textMuted),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$_selectedCampaignLeadCount leads in this campaign',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
 
                    const SizedBox(height: AppSizes.xl),
 
                    // ── Section: Payout ────────────────────────────
                    _sectionHeader('Payout & Slots', LucideIcons.indianRupee),
                    const SizedBox(height: AppSizes.md),
 
                    _buildCard(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _payoutController,
                                style:
                                    const TextStyle(color: AppColors.textDark),
                                decoration: _inputDecor(
                                  label: 'Payout / Call (₹)',
                                  icon: LucideIcons.indianRupee,
                                  hint: '20',
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,2}')),
                                ],
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  final val = double.tryParse(v.trim());
                                  if (val == null || val <= 0) {
                                    return 'Must be > 0';
                                  }
                                  final maxPayout = context.read<PlatformSettingsService>().maxTaskPayout;
                                  if (val > maxPayout) {
                                    return 'Max payout is ₹$maxPayout';
                                  }
                                  return null;
                                },
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: AppSizes.md),
                            Expanded(
                              child: TextFormField(
                                controller: _slotsController,
                                style:
                                    const TextStyle(color: AppColors.textDark),
                                decoration: _inputDecor(
                                  label: 'Total Slots',
                                  icon: LucideIcons.users,
                                  hint: '100',
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  final val = int.tryParse(v.trim());
                                  if (val == null || val <= 0) {
                                    return 'Must be > 0';
                                  }
                                  return null;
                                },
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
 
                    const SizedBox(height: AppSizes.xl),
 
                    // ── Section: Configuration ────────────────────
                    _sectionHeader('Configuration', LucideIcons.settings),
                    const SizedBox(height: AppSizes.md),
 
                    _buildCard(
                      children: [
                        // Priority Dropdown
                        DropdownButtonFormField<String>(
                          initialValue: _priority,
                          style: const TextStyle(color: AppColors.textDark),
                          decoration: _inputDecor(
                            label: 'Priority Level',
                            icon: LucideIcons.flag,
                          ),
                          items: ['Low', 'Medium', 'High']
                              .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: _priorityColor(p),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(p),
                                      ],
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _priority = v!),
                        ),
                        const SizedBox(height: AppSizes.base),
 
                        // Status Dropdown
                        DropdownButtonFormField<String>(
                          initialValue: _status,
                          style: const TextStyle(color: AppColors.textDark),
                          decoration: _inputDecor(
                            label: 'Task Status',
                            icon: LucideIcons.toggleRight,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'active',
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppColors.success,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text('Active'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'inactive',
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppColors.textMuted,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text('Inactive'),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _status = v!),
                        ),
                      ],
                    ),
 
                    const SizedBox(height: AppSizes.xl),
 
                    // ── Section: Lead Upload ──────────────────────
                    _sectionHeader(
                        'Lead Upload (Optional)', LucideIcons.uploadCloud),
                    const SizedBox(height: AppSizes.md),
 
                    _buildCard(
                      children: [
                        // Buttons Row
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed:
                                    _isParsing ? null : _pickAndUploadLeadSheet,
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  elevation: 0,
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  textStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSizes.md,
                                  ),
                                ),
                                icon: const Icon(LucideIcons.fileSpreadsheet,
                                    size: 18),
                                label: const Text('Upload CSV/XLSX'),
                              ),
                            ),
                            const SizedBox(width: AppSizes.md),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    _isParsing ? null : _showAddLeadDialog,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  foregroundColor: AppColors.accent,
                                  side: const BorderSide(
                                      color: AppColors.accent),
                                  textStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSizes.md,
                                  ),
                                ),
                                icon:
                                    const Icon(LucideIcons.userPlus, size: 18),
                                label: const Text('Add Manually'),
                              ),
                            ),
                          ],
                        ),
 
                        if (_isParsing) ...[
                          const SizedBox(height: AppSizes.md),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _uploadStatus,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textDark,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSizes.xs),
                              LinearProgressIndicator(
                                value: _uploadProgress,
                                backgroundColor: AppColors.border,
                                color: AppColors.primary,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ],
                          ),
                        ],
 
                        if (_leads.isNotEmpty) ...[
                          const SizedBox(height: AppSizes.base),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSizes.md,
                              vertical: AppSizes.sm + 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.infoBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(LucideIcons.info,
                                    size: 16, color: AppColors.info),
                                const SizedBox(width: 8),
                                Text(
                                  '${_leads.length} lead${_leads.length > 1 ? 's' : ''} added',
                                  style: const TextStyle(
                                    color: AppColors.info,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSizes.md),
 
                          // Lead List
                          ...List.generate(_leads.length, (i) {
                            final lead = _leads[i];
                            return Container(
                              margin:
                                  const EdgeInsets.only(bottom: AppSizes.sm),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSizes.md, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(12),
                                border: flutter.Border.all(
                                    color: AppColors.border),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppColors.accent
                                          .withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${i + 1}',
                                        style: const TextStyle(
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSizes.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          lead['name'] ?? '',
                                          style: const TextStyle(
                                            color: AppColors.textDark,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          lead['phone'] ?? '',
                                          style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (lead['email']?.isNotEmpty == true)
                                          Text(
                                            lead['email']!,
                                            style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _removeLead(i),
                                    icon: const Icon(LucideIcons.trash2,
                                        size: 18, color: AppColors.error),
                                    tooltip: 'Remove lead',
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
 
                    const SizedBox(height: AppSizes.xxl),
 
                    // ── Create Task Button ────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: AppSizes.buttonHeight,
                      child: ElevatedButton(
                        onPressed: (_isSubmitting || !_isFormValid)
                            ? null
                            : _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.accent.withValues(alpha: 0.4),
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: _isFormValid ? 2 : 0,
                          shadowColor:
                              AppColors.accent.withValues(alpha: 0.3),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(LucideIcons.plus, size: 20),
                                  SizedBox(width: 10),
                                  Text(
                                    'Create Task',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
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
 
  // ─── Section Header Widget ─────────────────────────────────
  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.accent),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
 
  // ─── Card Wrapper ──────────────────────────────────────────
  Widget _buildCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: flutter.Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
 
  // ─── Priority Color Helper ─────────────────────────────────
  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return AppColors.error;
      case 'medium':
        return AppColors.warning;
      case 'low':
        return AppColors.success;
      default:
        return AppColors.textMuted;
    }
  }
}