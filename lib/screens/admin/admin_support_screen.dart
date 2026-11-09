// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import '../../core/constants/constants.dart';
// import '../../core/utils/snackbar_utils.dart';

// class AdminSupportScreen extends StatefulWidget {
//   const AdminSupportScreen({Key? key}) : super(key: key);

//   @override
//   State<AdminSupportScreen> createState() => _AdminSupportScreenState();
// }

// class _AdminSupportScreenState extends State<AdminSupportScreen> {
//   final Set<String> _processingIds = {};
//   Future<QuerySnapshot>? _ticketsFuture;

//   @override
//   void initState() {
//     super.initState();
//     _loadTickets();
//   }

//   void _loadTickets() {
//     _ticketsFuture = _fetchTickets();
//   }

//   Future<QuerySnapshot> _fetchTickets() async {
//     // Best-effort token refresh so a freshly-assigned support_admin role claim
//     // reaches the Firestore rules. Bounded + guarded: on web getIdToken(true)
//     // can hang, so we never let it block the query (falls back to cached token).
//     try {
//       await FirebaseAuth.instance.currentUser
//           ?.getIdToken(true)
//           .timeout(const Duration(seconds: 4));
//     } catch (_) {
//       // Ignore — proceed with the existing (cached) token.
//     }
//     return FirebaseFirestore.instance
//         .collection('support_requests')
//         .orderBy('createdAt', descending: true)
//         .limit(50)
//         .get();
//   }

//   Future<void> _updateTicketStatus(
//       DocumentSnapshot doc, String newStatus) async {
//     final id = doc.id;
//     if (_processingIds.contains(id)) return;

//     setState(() => _processingIds.add(id));
//     try {
//       await doc.reference.update({
//         'status': newStatus,
//         'updatedAt': FieldValue.serverTimestamp(),
//       });
//       if (!mounted) return;
//       SnackBarUtils.showSuccess('Ticket marked as $newStatus');
//       setState(() => _loadTickets()); // Refresh after action
//     } catch (e) {
//       if (!mounted) return;
//       SnackBarUtils.showError('Error: $e');
//     } finally {
//       if (mounted) setState(() => _processingIds.remove(id));
//     }
//   }

//   /// Opens an attached screenshot full-screen with pinch-to-zoom.
//   void _openImage(String url) {
//     showDialog(
//       context: context,
//       builder: (ctx) => Dialog(
//         backgroundColor: Colors.black,
//         insetPadding: const EdgeInsets.all(12),
//         child: Stack(
//           children: [
//             InteractiveViewer(
//               child: Center(child: Image.network(url)),
//             ),
//             Positioned(
//               top: 8,
//               right: 8,
//               child: IconButton(
//                 icon: const Icon(Icons.close, color: Colors.white),
//                 onPressed: () => Navigator.of(ctx).pop(),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: AppColors.background,
//       appBar: AppBar(
//         title: const Text('Support Tickets'),
//         backgroundColor: AppColors.primary,
//         foregroundColor: Colors.white,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: () => setState(() => _loadTickets()),
//           ),
//         ],
//       ),
//       body: FutureBuilder<QuerySnapshot>(
//         future: _ticketsFuture,
//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.waiting) {
//             return const Center(child: CircularProgressIndicator());
//           }
//           if (snapshot.hasError) {
//             return Center(child: Text('Error: ${snapshot.error}'));
//           }

//           final docs = snapshot.data?.docs ?? [];
//           if (docs.isEmpty) {
//             return const Center(
//               child: Text(
//                 'No support tickets found.',
//                 style: TextStyle(color: AppColors.textMuted, fontSize: 16),
//               ),
//             );
//           }

//           return ListView.builder(
//             padding: const EdgeInsets.all(AppSizes.md),
//             itemCount: docs.length,
//             itemBuilder: (context, index) {
//               final doc = docs[index];
//               final data = doc.data() as Map<String, dynamic>;
//               final isProcessing = _processingIds.contains(doc.id);
//               final userName =
//                   (data['name'] ?? data['userName'] ?? 'User').toString();
//               final subject = data['subject']?.toString() ?? 'No Subject';
//               final message = data['message']?.toString() ?? 'No Message';
//               final status = data['status']?.toString() ?? 'pending';
//               final isClient =
//                   (data['source']?.toString() ?? '') == 'client_portal';
//               final priority = data['priority']?.toString() ?? '';
//               final email = data['email']?.toString() ?? '';
//               final screenshotUrl = data['screenshotUrl']?.toString() ?? '';

//               return Card(
//                 margin: const EdgeInsets.only(bottom: AppSizes.md),
//                 child: Padding(
//                   padding: const EdgeInsets.all(AppSizes.lg),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Expanded(
//                             child: Text(userName,
//                                 style: const TextStyle(
//                                     fontWeight: FontWeight.bold, fontSize: 16)),
//                           ),
//                           Container(
//                             padding: const EdgeInsets.symmetric(
//                                 horizontal: 8, vertical: 4),
//                             decoration: BoxDecoration(
//                               color: status == 'resolved'
//                                   ? AppColors.successBg
//                                   : AppColors.warning.withValues(alpha: 0.1),
//                               borderRadius: BorderRadius.circular(8),
//                             ),
//                             child: Text(
//                               status.toUpperCase(),
//                               style: TextStyle(
//                                 color: status == 'resolved'
//                                     ? AppColors.success
//                                     : AppColors.warning,
//                                 fontSize: 12,
//                                 fontWeight: FontWeight.w600,
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                       const SizedBox(height: AppSizes.sm),
//                       Row(
//                         children: [
//                           Container(
//                             padding: const EdgeInsets.symmetric(
//                                 horizontal: 8, vertical: 3),
//                             decoration: BoxDecoration(
//                               color: (isClient
//                                       ? AppColors.info
//                                       : AppColors.primary)
//                                   .withValues(alpha: 0.1),
//                               borderRadius: BorderRadius.circular(6),
//                             ),
//                             child: Text(
//                               isClient ? 'CLIENT' : 'EMPLOYEE',
//                               style: TextStyle(
//                                 fontSize: 10,
//                                 fontWeight: FontWeight.w800,
//                                 color: isClient
//                                     ? AppColors.info
//                                     : AppColors.primary,
//                               ),
//                             ),
//                           ),
//                           if (priority.isNotEmpty) ...[
//                             const SizedBox(width: 8),
//                             Text('Priority: $priority',
//                                 style: const TextStyle(
//                                     fontSize: 12, color: AppColors.textMuted)),
//                           ],
//                         ],
//                       ),
//                       if (email.isNotEmpty) ...[
//                         const SizedBox(height: 4),
//                         Text(email,
//                             style: const TextStyle(
//                                 fontSize: 12, color: AppColors.textMuted)),
//                       ],
//                       const SizedBox(height: AppSizes.sm),
//                       Text('Subject: $subject',
//                           style: const TextStyle(
//                               fontWeight: FontWeight.w600, fontSize: 14)),
//                       const SizedBox(height: AppSizes.sm),
//                       Text(message,
//                           style: const TextStyle(
//                               color: AppColors.textBody, fontSize: 14)),
//                       if (screenshotUrl.isNotEmpty) ...[
//                         const SizedBox(height: AppSizes.md),
//                         const Text('Attachment',
//                             style: TextStyle(
//                                 fontSize: 12,
//                                 fontWeight: FontWeight.w600,
//                                 color: AppColors.textMuted)),
//                         const SizedBox(height: AppSizes.sm),
//                         GestureDetector(
//                           onTap: () => _openImage(screenshotUrl),
//                           child: ClipRRect(
//                             borderRadius: BorderRadius.circular(8),
//                             child: Image.network(
//                               screenshotUrl,
//                               height: 140,
//                               width: double.infinity,
//                               fit: BoxFit.cover,
//                               loadingBuilder: (context, child, progress) =>
//                                   progress == null
//                                       ? child
//                                       : Container(
//                                           height: 140,
//                                           alignment: Alignment.center,
//                                           color: AppColors.surfaceVariant,
//                                           child:
//                                               const CircularProgressIndicator(),
//                                         ),
//                               errorBuilder: (context, error, stack) => Container(
//                                 height: 140,
//                                 alignment: Alignment.center,
//                                 color: AppColors.surfaceVariant,
//                                 child: const Text('Could not load attachment',
//                                     style:
//                                         TextStyle(color: AppColors.textMuted)),
//                               ),
//                             ),
//                           ),
//                         ),
//                       ],
//                       const SizedBox(height: AppSizes.md),
//                       const Divider(),
//                       const SizedBox(height: AppSizes.sm),
//                       Row(
//                         children: [
//                           Expanded(
//                             child: OutlinedButton(
//                               onPressed: isProcessing || status == 'in_progress'
//                                   ? null
//                                   : () =>
//                                       _updateTicketStatus(doc, 'in_progress'),
//                               style: OutlinedButton.styleFrom(
//                                   foregroundColor: AppColors.warning),
//                               child: const Text('In Progress'),
//                             ),
//                           ),
//                           const SizedBox(width: AppSizes.md),
//                           Expanded(
//                             child: ElevatedButton(
//                               onPressed: isProcessing || status == 'resolved'
//                                   ? null
//                                   : () => _updateTicketStatus(doc, 'resolved'),
//                               style: ElevatedButton.styleFrom(
//                                   backgroundColor: AppColors.success,
//                                   foregroundColor: Colors.white),
//                               child: isProcessing
//                                   ? const SizedBox(
//                                       width: 16,
//                                       height: 16,
//                                       child: CircularProgressIndicator(
//                                           color: Colors.white))
//                                   : const Text('Resolve'),
//                             ),
//                           ),
//                         ],
//                       )
//                     ],
//                   ),
//                 ),
//               );
//             },
//           );
//         },
//       ),
//     );
//   }
// }






// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import '../../core/constants/constants.dart';
// import '../../core/utils/snackbar_utils.dart';
 
// class AdminSupportScreen extends StatefulWidget {
//   const AdminSupportScreen({Key? key}) : super(key: key);
 
//   @override
//   State<AdminSupportScreen> createState() => _AdminSupportScreenState();
// }
 
// class _AdminSupportScreenState extends State<AdminSupportScreen> {
//   final Set<String> _processingIds = {};
//   Future<QuerySnapshot>? _ticketsFuture;
 
//   @override
//   void initState() {
//     super.initState();
//     _loadTickets();
//   }
 
//   void _loadTickets() {
//     _ticketsFuture = _fetchTickets();
//   }
 
//   Future<QuerySnapshot> _fetchTickets() async {
//     // Best-effort token refresh so a freshly-assigned support_admin role claim
//     // reaches the Firestore rules. Bounded + guarded: on web getIdToken(true)
//     // can hang, so we never let it block the query (falls back to cached token).
//     try {
//       await FirebaseAuth.instance.currentUser
//           ?.getIdToken(true)
//           .timeout(const Duration(seconds: 4));
//     } catch (_) {
//       // Ignore — proceed with the existing (cached) token.
//     }
//     return FirebaseFirestore.instance
//         .collection('support_requests')
//         .orderBy('createdAt', descending: true)
//         .limit(50)
//         .get();
//   }
 
//   Future<void> _updateTicketStatus(
//       DocumentSnapshot doc, String newStatus) async {
//     final id = doc.id;
//     if (_processingIds.contains(id)) return;
 
//     setState(() => _processingIds.add(id));
//     try {
//       await doc.reference.update({
//         'status': newStatus,
//         'updatedAt': FieldValue.serverTimestamp(),
//       });
//       if (!mounted) return;
//       SnackBarUtils.showSuccess('Ticket marked as $newStatus');
//       setState(() => _loadTickets()); // Refresh after action
//     } catch (e) {
//       if (!mounted) return;
//       SnackBarUtils.showError('Error: $e');
//     } finally {
//       if (mounted) setState(() => _processingIds.remove(id));
//     }
//   }
 
//   /// Opens an attached screenshot full-screen with pinch-to-zoom.
//   void _openImage(String url) {
//     showDialog(
//       context: context,
//       builder: (ctx) => Dialog(
//         backgroundColor: Colors.black,
//         insetPadding: const EdgeInsets.all(12),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//         clipBehavior: Clip.antiAlias,
//         child: Stack(
//           children: [
//             InteractiveViewer(
//               child: Center(child: Image.network(url)),
//             ),
//             Positioned(
//               top: 8,
//               right: 8,
//               child: IconButton(
//                 style: IconButton.styleFrom(
//                   backgroundColor: Colors.white.withValues(alpha: 0.18),
//                 ),
//                 icon: const Icon(Icons.close, color: Colors.white),
//                 onPressed: () => Navigator.of(ctx).pop(),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
 
//   Widget _centerMessage({
//     required IconData icon,
//     required String text,
//     required Color color,
//     TextStyle? style,
//   }) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(AppSizes.lg),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Container(
//               width: 84,
//               height: 84,
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 color: color.withValues(alpha: 0.1),
//               ),
//               child: Icon(icon, size: 38, color: color),
//             ),
//             const SizedBox(height: AppSizes.md),
//             Text(text, textAlign: TextAlign.center, style: style),
//           ],
//         ),
//       ),
//     );
//   }
 
//   Widget _chip(String label, Color color, {double fontSize = 11}) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
//       decoration: BoxDecoration(
//         color: color.withValues(alpha: 0.12),
//         borderRadius: BorderRadius.circular(20),
//       ),
//       child: Text(
//         label,
//         style: TextStyle(
//           color: color,
//           fontSize: fontSize,
//           fontWeight: FontWeight.w800,
//           letterSpacing: 0.3,
//         ),
//       ),
//     );
//   }
 
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: AppColors.background,
//       appBar: AppBar(
//         title: const Text('Support Tickets',
//             style: TextStyle(fontWeight: FontWeight.w700)),
//         backgroundColor: AppColors.primary,
//         foregroundColor: Colors.white,
//         elevation: 0,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: () => setState(() => _loadTickets()),
//           ),
//         ],
//       ),
//       body: FutureBuilder<QuerySnapshot>(
//         future: _ticketsFuture,
//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.waiting) {
//             return const Center(child: CircularProgressIndicator());
//           }
//           if (snapshot.hasError) {
//             return _centerMessage(
//               icon: Icons.error_outline_rounded,
//               text: 'Error: ${snapshot.error}',
//               color: AppColors.error,
//               style: const TextStyle(color: AppColors.error),
//             );
//           }
 
//           final docs = snapshot.data?.docs ?? [];
//           if (docs.isEmpty) {
//             return _centerMessage(
//               icon: Icons.support_agent_rounded,
//               text: 'No support tickets found.',
//               color: AppColors.textMuted,
//               style: const TextStyle(
//                   color: AppColors.textMuted,
//                   fontSize: 16,
//                   fontWeight: FontWeight.w500),
//             );
//           }
 
//           return Align(
//             alignment: Alignment.topCenter,
//             child: ConstrainedBox(
//               constraints: const BoxConstraints(maxWidth: 760),
//               child: ListView.builder(
//                 physics: const BouncingScrollPhysics(),
//                 padding: const EdgeInsets.all(AppSizes.md),
//                 itemCount: docs.length,
//                 itemBuilder: (context, index) {
//                   final doc = docs[index];
//                   final data = doc.data() as Map<String, dynamic>;
//                   final isProcessing = _processingIds.contains(doc.id);
//                   final userName =
//                       (data['name'] ?? data['userName'] ?? 'User').toString();
//                   final subject = data['subject']?.toString() ?? 'No Subject';
//                   final message = data['message']?.toString() ?? 'No Message';
//                   final status = data['status']?.toString() ?? 'pending';
//                   final isClient =
//                       (data['source']?.toString() ?? '') == 'client_portal';
//                   final priority = data['priority']?.toString() ?? '';
//                   final email = data['email']?.toString() ?? '';
//                   final screenshotUrl =
//                       data['screenshotUrl']?.toString() ?? '';
 
//                   final statusColor = status == 'resolved'
//                       ? AppColors.success
//                       : AppColors.warning;
//                   final typeColor =
//                       isClient ? AppColors.info : AppColors.primary;
//                   final initial =
//                       userName.isNotEmpty ? userName[0].toUpperCase() : '?';
 
//                   return Container(
//                     margin: const EdgeInsets.only(bottom: AppSizes.md),
//                     clipBehavior: Clip.antiAlias,
//                     decoration: BoxDecoration(
//                       color: Theme.of(context).cardColor,
//                       borderRadius: BorderRadius.circular(18),
//                       border: Border.all(
//                           color: statusColor.withValues(alpha: 0.18)),
//                       boxShadow: [
//                         BoxShadow(
//                           color: Colors.black.withValues(alpha: 0.05),
//                           blurRadius: 14,
//                           offset: const Offset(0, 5),
//                         ),
//                       ],
//                     ),
//                     child: IntrinsicHeight(
//                       child: Row(
//                         crossAxisAlignment: CrossAxisAlignment.stretch,
//                         children: [
//                           Container(
//                               width: 5,
//                               color: statusColor.withValues(alpha: 0.85)),
//                           Expanded(
//                             child: Padding(
//                               padding: const EdgeInsets.all(AppSizes.lg),
//                               child: Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   Row(
//                                     children: [
//                                       Container(
//                                         width: 42,
//                                         height: 42,
//                                         alignment: Alignment.center,
//                                         decoration: BoxDecoration(
//                                           borderRadius:
//                                               BorderRadius.circular(13),
//                                           gradient: LinearGradient(
//                                             begin: Alignment.topLeft,
//                                             end: Alignment.bottomRight,
//                                             colors: [
//                                               typeColor.withValues(alpha: 0.24),
//                                               typeColor.withValues(alpha: 0.09),
//                                             ],
//                                           ),
//                                         ),
//                                         child: Text(
//                                           initial,
//                                           style: TextStyle(
//                                             color: typeColor,
//                                             fontWeight: FontWeight.w800,
//                                             fontSize: 17,
//                                           ),
//                                         ),
//                                       ),
//                                       const SizedBox(width: 12),
//                                       Expanded(
//                                         child: Column(
//                                           crossAxisAlignment:
//                                               CrossAxisAlignment.start,
//                                           children: [
//                                             Text(userName,
//                                                 maxLines: 1,
//                                                 overflow: TextOverflow.ellipsis,
//                                                 style: const TextStyle(
//                                                     fontWeight: FontWeight.w800,
//                                                     fontSize: 16)),
//                                             if (email.isNotEmpty) ...[
//                                               const SizedBox(height: 2),
//                                               Text(email,
//                                                   maxLines: 1,
//                                                   overflow:
//                                                       TextOverflow.ellipsis,
//                                                   style: const TextStyle(
//                                                       fontSize: 12.5,
//                                                       color:
//                                                           AppColors.textMuted)),
//                                             ],
//                                           ],
//                                         ),
//                                       ),
//                                       const SizedBox(width: 8),
//                                       _chip(status.toUpperCase(), statusColor,
//                                           fontSize: 11),
//                                     ],
//                                   ),
//                                   const SizedBox(height: 12),
//                                   Row(
//                                     children: [
//                                       _chip(isClient ? 'CLIENT' : 'EMPLOYEE',
//                                           typeColor,
//                                           fontSize: 10),
//                                       if (priority.isNotEmpty) ...[
//                                         const SizedBox(width: 8),
//                                         const Icon(Icons.flag_rounded,
//                                             size: 14,
//                                             color: AppColors.textMuted),
//                                         const SizedBox(width: 3),
//                                         Flexible(
//                                           child: Text('Priority: $priority',
//                                               overflow: TextOverflow.ellipsis,
//                                               style: const TextStyle(
//                                                   fontSize: 12,
//                                                   fontWeight: FontWeight.w500,
//                                                   color: AppColors.textMuted)),
//                                         ),
//                                       ],
//                                     ],
//                                   ),
//                                   const SizedBox(height: AppSizes.md),
//                                   Text('Subject: $subject',
//                                       style: const TextStyle(
//                                           fontWeight: FontWeight.w700,
//                                           fontSize: 14.5)),
//                                   const SizedBox(height: AppSizes.sm),
//                                   Container(
//                                     width: double.infinity,
//                                     padding: const EdgeInsets.all(12),
//                                     decoration: BoxDecoration(
//                                       color: AppColors.surfaceVariant
//                                           .withValues(alpha: 0.6),
//                                       borderRadius: BorderRadius.circular(12),
//                                     ),
//                                     child: Text(message,
//                                         style: const TextStyle(
//                                             color: AppColors.textBody,
//                                             fontSize: 14,
//                                             height: 1.4)),
//                                   ),
//                                   if (screenshotUrl.isNotEmpty) ...[
//                                     const SizedBox(height: AppSizes.md),
//                                     const Row(
//                                       children: [
//                                         Icon(Icons.attach_file_rounded,
//                                             size: 15,
//                                             color: AppColors.textMuted),
//                                         SizedBox(width: 4),
//                                         Text('Attachment',
//                                             style: TextStyle(
//                                                 fontSize: 12,
//                                                 fontWeight: FontWeight.w600,
//                                                 color: AppColors.textMuted)),
//                                       ],
//                                     ),
//                                     const SizedBox(height: AppSizes.sm),
//                                     GestureDetector(
//                                       onTap: () => _openImage(screenshotUrl),
//                                       child: ClipRRect(
//                                         borderRadius: BorderRadius.circular(12),
//                                         child: Image.network(
//                                           screenshotUrl,
//                                           height: 140,
//                                           width: double.infinity,
//                                           fit: BoxFit.cover,
//                                           loadingBuilder:
//                                               (context, child, progress) =>
//                                                   progress == null
//                                                       ? child
//                                                       : Container(
//                                                           height: 140,
//                                                           alignment:
//                                                               Alignment.center,
//                                                           color: AppColors
//                                                               .surfaceVariant,
//                                                           child:
//                                                               const CircularProgressIndicator(),
//                                                         ),
//                                           errorBuilder:
//                                               (context, error, stack) =>
//                                                   Container(
//                                             height: 140,
//                                             alignment: Alignment.center,
//                                             color: AppColors.surfaceVariant,
//                                             child: const Text(
//                                                 'Could not load attachment',
//                                                 style: TextStyle(
//                                                     color:
//                                                         AppColors.textMuted)),
//                                           ),
//                                         ),
//                                       ),
//                                     ),
//                                   ],
//                                   const SizedBox(height: AppSizes.md),
//                                   const Divider(height: 1),
//                                   const SizedBox(height: AppSizes.md),
//                                   Row(
//                                     children: [
//                                       Expanded(
//                                         child: OutlinedButton(
//                                           onPressed: isProcessing ||
//                                                   status == 'in_progress'
//                                               ? null
//                                               : () => _updateTicketStatus(
//                                                   doc, 'in_progress'),
//                                           style: OutlinedButton.styleFrom(
//                                             foregroundColor: AppColors.warning,
//                                             padding: const EdgeInsets.symmetric(
//                                                 vertical: 13),
//                                             shape: RoundedRectangleBorder(
//                                                 borderRadius:
//                                                     BorderRadius.circular(12)),
//                                           ),
//                                           child: const Text('In Progress'),
//                                         ),
//                                       ),
//                                       const SizedBox(width: AppSizes.md),
//                                       Expanded(
//                                         child: ElevatedButton(
//                                           onPressed: isProcessing ||
//                                                   status == 'resolved'
//                                               ? null
//                                               : () => _updateTicketStatus(
//                                                   doc, 'resolved'),
//                                           style: ElevatedButton.styleFrom(
//                                             backgroundColor: AppColors.success,
//                                             foregroundColor: Colors.white,
//                                             elevation: 0,
//                                             padding: const EdgeInsets.symmetric(
//                                                 vertical: 13),
//                                             shape: RoundedRectangleBorder(
//                                                 borderRadius:
//                                                     BorderRadius.circular(12)),
//                                           ),
//                                           child: isProcessing
//                                               ? const SizedBox(
//                                                   width: 16,
//                                                   height: 16,
//                                                   child:
//                                                       CircularProgressIndicator(
//                                                           color: Colors.white))
//                                               : const Text('Resolve'),
//                                         ),
//                                       ),
//                                     ],
//                                   )
//                                 ],
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   );
//                 },
//               ),
//             ),
//           );
//         },
//       ),
//     );
//   }
// }
 

 import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';
 
/// Company name of a ticket (tries the common field names).
String _companyOf(Map<String, dynamic> d) =>
    (d['company'] ?? d['companyName'] ?? d['clientCompany'] ?? '')
        .toString()
        .trim();
 
/// Opens an attached screenshot full-screen with pinch-to-zoom.
void _showTicketImage(BuildContext context, String url) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InteractiveViewer(
            child: Center(child: Image.network(url)),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.18),
              ),
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}
 
Widget _ticketChip(String label, Color color, {double fontSize = 11}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
    ),
  );
}
 
class AdminSupportScreen extends StatefulWidget {
  const AdminSupportScreen({Key? key}) : super(key: key);
 
  @override
  State<AdminSupportScreen> createState() => _AdminSupportScreenState();
}
 
class _AdminSupportScreenState extends State<AdminSupportScreen> {
  final Set<String> _processingIds = {};
  Future<QuerySnapshot>? _ticketsFuture;
 
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  // Filters: status = all | in_progress | resolved, type = all | client | employee
  String _statusFilter = 'all';
  String _typeFilter = 'all';
 
  int get _activeFilterCount =>
      (_statusFilter != 'all' ? 1 : 0) + (_typeFilter != 'all' ? 1 : 0);
 
  @override
  void initState() {
    super.initState();
    _loadTickets();
  }
 
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
 
  void _loadTickets() {
    _ticketsFuture = _fetchTickets();
  }
 
  Future<QuerySnapshot> _fetchTickets() async {
    // Best-effort token refresh so a freshly-assigned support_admin role claim
    // reaches the Firestore rules. Bounded + guarded: on web getIdToken(true)
    // can hang, so we never let it block the query (falls back to cached token).
    try {
      await FirebaseAuth.instance.currentUser
          ?.getIdToken(true)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Ignore — proceed with the existing (cached) token.
    }
    return FirebaseFirestore.instance
        .collection('support_requests')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
  }
 
  Future<void> _updateTicketStatus(
      DocumentSnapshot doc, String newStatus) async {
    final id = doc.id;
    if (_processingIds.contains(id)) return;
 
    setState(() => _processingIds.add(id));
    try {
      await doc.reference.update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      SnackBarUtils.showSuccess('Ticket marked as $newStatus');
      setState(() => _loadTickets()); // Refresh after action
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }
 
  bool _matches(Map<String, dynamic> data) {
    final status = data['status']?.toString() ?? 'pending';
    final isClient = (data['source']?.toString() ?? '') == 'client_portal';
 
    if (_statusFilter != 'all' && status != _statusFilter) return false;
    if (_typeFilter == 'client' && !isClient) return false;
    if (_typeFilter == 'employee' && isClient) return false;
 
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final subject = (data['subject']?.toString() ?? '').toLowerCase();
    final name =
        (data['name'] ?? data['userName'] ?? '').toString().toLowerCase();
    final company = _companyOf(data).toLowerCase();
    return subject.contains(q) || name.contains(q) || company.contains(q);
  }
 
  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget group(String title, List<List<String>> options,
              String current, void Function(String) onPick) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options.map((o) {
                    final selected = current == o[0];
                    return ChoiceChip(
                      label: Text(o[1]),
                      selected: selected,
                      showCheckmark: false,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : AppColors.textBody,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) {
                        onPick(o[0]);
                        setSheet(() {});
                      },
                    );
                  }).toList(),
                ),
              ],
            );
          }
 
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Filter tickets',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 18)),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _statusFilter = 'all';
                            _typeFilter = 'all';
                          });
                          setSheet(() {});
                        },
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  group(
                    'Status',
                    const [
                      ['all', 'All'],
                      ['in_progress', 'In Progress'],
                      ['resolved', 'Resolved'],
                    ],
                    _statusFilter,
                    (v) => setState(() => _statusFilter = v),
                  ),
                  const SizedBox(height: 18),
                  group(
                    'Type',
                    const [
                      ['all', 'All'],
                      ['client', 'Client'],
                      ['employee', 'Employee'],
                    ],
                    _typeFilter,
                    (v) => setState(() => _typeFilter = v),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
 
  Widget _buildSearchBar() {
    final active = _activeFilterCount;
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(AppSizes.md, 4, AppSizes.md, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(
                        fontSize: 14.5, color: AppColors.textDark),
                    decoration: InputDecoration(
                      hintText: 'Search subject, employee or company',
                      hintStyle: const TextStyle(
                          fontSize: 13.5, color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.textMuted),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  size: 18, color: AppColors.textMuted),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Material(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _openFilterSheet,
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.tune_rounded, color: Colors.white),
                      ),
                    ),
                  ),
                  if (active > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 2),
                        ),
                        child: Text(
                          '$active',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
 
  Widget _centerMessage({
    required IconData icon,
    required String text,
    required Color color,
    TextStyle? style,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.1),
              ),
              child: Icon(icon, size: 38, color: color),
            ),
            const SizedBox(height: AppSizes.md),
            Text(text, textAlign: TextAlign.center, style: style),
          ],
        ),
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Support Tickets'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _loadTickets()),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: FutureBuilder<QuerySnapshot>(
              future: _ticketsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _centerMessage(
                    icon: Icons.error_outline_rounded,
                    text: 'Error: ${snapshot.error}',
                    color: AppColors.error,
                    style: const TextStyle(color: AppColors.error),
                  );
                }
 
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _centerMessage(
                    icon: Icons.support_agent_rounded,
                    text: 'No support tickets found.',
                    color: AppColors.textMuted,
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 16,
                        fontWeight: FontWeight.w500),
                  );
                }
 
                final filtered = docs
                    .where((d) => _matches(d.data() as Map<String, dynamic>))
                    .toList();
                if (filtered.isEmpty) {
                  return _centerMessage(
                    icon: Icons.search_off_rounded,
                    text: 'No tickets match your search or filters.',
                    color: AppColors.textMuted,
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 16,
                        fontWeight: FontWeight.w500),
                  );
                }
 
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(AppSizes.md),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final doc = filtered[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final isProcessing = _processingIds.contains(doc.id);
                        final userName =
                            (data['name'] ?? data['userName'] ?? 'User')
                                .toString();
                        final subject =
                            data['subject']?.toString() ?? 'No Subject';
                        final status = data['status']?.toString() ?? 'pending';
                        final isClient =
                            (data['source']?.toString() ?? '') ==
                                'client_portal';
                        final priority = data['priority']?.toString() ?? '';
                        final email = data['email']?.toString() ?? '';
                        final company = _companyOf(data);
 
                        final statusColor = status == 'resolved'
                            ? AppColors.success
                            : AppColors.warning;
                        final typeColor =
                            isClient ? AppColors.info : AppColors.primary;
                        final initial = userName.isNotEmpty
                            ? userName[0].toUpperCase()
                            : '?';
 
                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSizes.md),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Theme.of(context).cardColor,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(
                                  color: statusColor.withValues(alpha: 0.18)),
                            ),
                            child: InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      _TicketDetailScreen(data: data),
                                ),
                              ),
                              child: IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                        width: 5,
                                        color:
                                            statusColor.withValues(alpha: 0.85)),
                                    Expanded(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.all(AppSizes.lg),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  width: 42,
                                                  height: 42,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            13),
                                                    gradient: LinearGradient(
                                                      begin: Alignment.topLeft,
                                                      end:
                                                          Alignment.bottomRight,
                                                      colors: [
                                                        typeColor.withValues(
                                                            alpha: 0.24),
                                                        typeColor.withValues(
                                                            alpha: 0.09),
                                                      ],
                                                    ),
                                                  ),
                                                  child: Text(
                                                    initial,
                                                    style: TextStyle(
                                                      color: typeColor,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 17,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(userName,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  fontSize:
                                                                      16)),
                                                      if (email
                                                          .isNotEmpty) ...[
                                                        const SizedBox(
                                                            height: 2),
                                                        Text(email,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: const TextStyle(
                                                                fontSize: 12.5,
                                                                color: AppColors
                                                                    .textMuted)),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                _ticketChip(
                                                    status.toUpperCase(),
                                                    statusColor,
                                                    fontSize: 11),
                                                const SizedBox(width: 2),
                                                const Icon(
                                                    Icons.chevron_right_rounded,
                                                    color: AppColors.textMuted),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                _ticketChip(
                                                    isClient
                                                        ? 'CLIENT'
                                                        : 'EMPLOYEE',
                                                    typeColor,
                                                    fontSize: 10),
                                                if (company.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  const Icon(
                                                      Icons.business_rounded,
                                                      size: 14,
                                                      color:
                                                          AppColors.textMuted),
                                                  const SizedBox(width: 3),
                                                  Flexible(
                                                    child: Text(company,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: AppColors
                                                                .textMuted)),
                                                  ),
                                                ],
                                                if (priority.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  const Icon(
                                                      Icons.flag_rounded,
                                                      size: 14,
                                                      color:
                                                          AppColors.textMuted),
                                                  const SizedBox(width: 3),
                                                  Flexible(
                                                    child: Text(
                                                        'Priority: $priority',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: AppColors
                                                                .textMuted)),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: AppSizes.md),
                                            Text('Subject: $subject',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14.5)),
                                            const SizedBox(height: AppSizes.md),
                                            const Divider(height: 1),
                                            const SizedBox(height: AppSizes.md),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton(
                                                    onPressed: isProcessing ||
                                                            status ==
                                                                'in_progress'
                                                        ? null
                                                        : () =>
                                                            _updateTicketStatus(
                                                                doc,
                                                                'in_progress'),
                                                    style: OutlinedButton
                                                        .styleFrom(
                                                      foregroundColor:
                                                          AppColors.warning,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 13),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          12)),
                                                    ),
                                                    child: const Text(
                                                        'In Progress'),
                                                  ),
                                                ),
                                                const SizedBox(
                                                    width: AppSizes.md),
                                                Expanded(
                                                  child: ElevatedButton(
                                                    onPressed: isProcessing ||
                                                            status ==
                                                                'resolved'
                                                        ? null
                                                        : () =>
                                                            _updateTicketStatus(
                                                                doc,
                                                                'resolved'),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          AppColors.success,
                                                      foregroundColor:
                                                          Colors.white,
                                                      elevation: 0,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 13),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          12)),
                                                    ),
                                                    child: isProcessing
                                                        ? const SizedBox(
                                                            width: 16,
                                                            height: 16,
                                                            child: CircularProgressIndicator(
                                                                color: Colors
                                                                    .white))
                                                        : const Text('Resolve'),
                                                  ),
                                                ),
                                              ],
                                            )
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
 
// ─── Ticket detail screen ─────────────────────────────────────────────────────
class _TicketDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;
 
  const _TicketDetailScreen({required this.data});
 
  Widget _section(String title, Widget child) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.textLight.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textMuted)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
 
  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.textMuted),
          const SizedBox(width: 10),
          SizedBox(
            width: 82,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark)),
          ),
        ],
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    final userName = (data['name'] ?? data['userName'] ?? 'User').toString();
    final subject = data['subject']?.toString() ?? 'No Subject';
    final message = data['message']?.toString() ?? 'No Message';
    final status = data['status']?.toString() ?? 'pending';
    final isClient = (data['source']?.toString() ?? '') == 'client_portal';
    final priority = data['priority']?.toString() ?? '';
    final email = data['email']?.toString() ?? '';
    final screenshotUrl = data['screenshotUrl']?.toString() ?? '';
    final company = _companyOf(data);
    final createdAt = data['createdAt'];
    final createdStr = createdAt is Timestamp
        ? DateFormat('dd MMM yyyy · hh:mm a').format(createdAt.toDate())
        : '';
 
    final statusColor =
        status == 'resolved' ? AppColors.success : AppColors.warning;
    final typeColor = isClient ? AppColors.info : AppColors.primary;
    final initial = userName.isNotEmpty ? userName[0].toUpperCase() : '?';
 
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ticket Details'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(AppSizes.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Who + status
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSizes.md),
                  padding: const EdgeInsets.all(AppSizes.lg),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              typeColor.withValues(alpha: 0.24),
                              typeColor.withValues(alpha: 0.09),
                            ],
                          ),
                        ),
                        child: Text(initial,
                            style: TextStyle(
                                color: typeColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 22)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(userName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18)),
                            if (email.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(email,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textMuted)),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _ticketChip(status.toUpperCase(), statusColor),
                                _ticketChip(
                                    isClient ? 'CLIENT' : 'EMPLOYEE', typeColor,
                                    fontSize: 10),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
 
                // Info
                _section(
                  'Ticket info',
                  Column(
                    children: [
                      _infoRow(Icons.person_outline_rounded, 'Name', userName),
                      if (company.isNotEmpty)
                        _infoRow(Icons.business_rounded, 'Company', company),
                      if (email.isNotEmpty)
                        _infoRow(Icons.mail_outline_rounded, 'Email', email),
                      if (priority.isNotEmpty)
                        _infoRow(Icons.flag_rounded, 'Priority', priority),
                      if (createdStr.isNotEmpty)
                        _infoRow(Icons.schedule_rounded, 'Created', createdStr),
                    ],
                  ),
                ),
 
                _section(
                  'Subject',
                  Text(subject,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.35)),
                ),
 
                _section(
                  'Message',
                  Text(message,
                      style: const TextStyle(
                          color: AppColors.textBody,
                          fontSize: 14.5,
                          height: 1.5)),
                ),
 
                if (screenshotUrl.isNotEmpty)
                  _section(
                    'Attachment',
                    GestureDetector(
                      onTap: () => _showTicketImage(context, screenshotUrl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          screenshotUrl,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                                  ? child
                                  : Container(
                                      height: 180,
                                      alignment: Alignment.center,
                                      color: AppColors.surfaceVariant,
                                      child: const CircularProgressIndicator(),
                                    ),
                          errorBuilder: (context, error, stack) => Container(
                            height: 140,
                            alignment: Alignment.center,
                            color: AppColors.surfaceVariant,
                            child: const Text('Could not load attachment',
                                style: TextStyle(color: AppColors.textMuted)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}