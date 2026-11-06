import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../models/faq_model.dart';
import '../models/support_request_model.dart';

class SupportService extends ChangeNotifier {
  static final SupportService _instance = SupportService._internal();

  factory SupportService() => _instance;

  SupportService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ──────────────────────────────────────────────────────────────────────────
  // AUTO-SEEDER (Temporary logic to populate FAQs initially)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> seedFaqs() async {
    try {
      debugPrint('Seeding FAQs...');
      final batch = _firestore.batch();
      
      final Map<String, dynamic> faqs = {
        'faq1': {
          'question': 'What is Sherize?',
          'answer': 'We are a trusted platform that connects skilled professionals with businesses needing efficient BPO tasks. By completing assigned tasks, you earn real money directly into your wallet.',
          'category': 'General',
          'tags': ['about', 'bpo', 'platform'],
          'order': 1,
          'isActive': true,
        },
        'faq2': {
          'question': 'How do I accept a task?',
          'answer': 'Go to your main Dashboard, browse the Available Tasks list, tap on a task that interests you, and press Accept Task. It will immediately move to My Tasks so you can begin working.',
          'category': 'Tasks',
          'tags': ['accept', 'tasks', 'dashboard'],
          'order': 2,
          'isActive': true,
        },
        'faq3': {
          'question': 'Why does it say No leads available?',
          'answer': 'Every task is backed by a finite number of leads (e.g. phone numbers to call). If all leads have already been assigned to or completed by other users, you won\'t be able to accept the task.',
          'category': 'Tasks',
          'tags': ['leads', 'empty', 'error'],
          'order': 3,
          'isActive': true,
        },
        'faq4': {
          'question': 'When and how do I get paid?',
          'answer': 'Once you submit a completed task, your earnings go to Pending. After an admin reviews and approves your submission, the funds are added to your primary Wallet. You can request a withdrawal at any time once you reach the minimum balance.',
          'category': 'Payments',
          'tags': ['salary', 'payment', 'withdraw', 'wallet'],
          'order': 4,
          'isActive': true,
        },
        'faq5': {
          'question': 'How do I update my bank details?',
          'answer': 'To receive payouts, go to Settings > Edit Profile > Bank Details. Enter your secure Account Number and IFSC Code. Ensure the name matches your KYC exactly.',
          'category': 'Payments',
          'tags': ['bank', 'account', 'ifsc'],
          'order': 5,
          'isActive': true,
        },
        'faq6': {
          'question': 'Why do I need to complete KYC?',
          'answer': 'KYC (Know Your Customer) verification is required by law to process your payouts. It helps us prevent fraud and ensures an equitable environment for all employees.',
          'category': 'KYC',
          'tags': ['kyc', 'verification', 'auth'],
          'order': 6,
          'isActive': true,
        },
        'faq7': {
          'question': 'How long does KYC verification take?',
          'answer': 'Our team reviews all submitted ID documents manually. Typically, your KYC status will update within 24 to 48 hours.',
          'category': 'KYC',
          'tags': ['time', 'status', 'pending'],
          'order': 7,
          'isActive': true,
        },
        'faq8': {
          'question': 'Why are my profile changes not saving?',
          'answer': 'Please ensure you have an active internet connection. All profile updates are securely synced with our servers. If an error persists, try restarting the app or submitting a Bug Report.',
          'category': 'Technical',
          'tags': ['bug', 'profile', 'save', 'network'],
          'order': 8,
          'isActive': true,
        },
        'faq9': {
          'question': 'Do I have to log in every time?',
          'answer': 'No! As long as you don\'t explicitly tap Logout in the Settings menu, your session is securely persisted and you will remain logged in even if you close the app.',
          'category': 'General',
          'tags': ['login', 'session', 'logout'],
          'order': 9,
          'isActive': true,
        },
        'faq10': {
          'question': 'How do I report a missing payment?',
          'answer': 'If you notice an anomaly with your wallet balance after an approval, go to Settings > Help & Support > Contact Us, select Payment Problem as the Issue Type, and submit your request. Our team usually responds within 24 hours.',
          'category': 'Payments',
          'tags': ['support', 'missing', 'issue'],
          'order': 10,
          'isActive': true,
        }
      };

      for (var entry in faqs.entries) {
        final docRef = _firestore.collection('faqs').doc(entry.key);
        final data = entry.value;
        data['createdAt'] = FieldValue.serverTimestamp();
        data['updatedAt'] = FieldValue.serverTimestamp();
        batch.set(docRef, data);
      }

      await batch.commit();
      debugPrint('Successfully seeded FAQs!');
    } catch (e) {
      debugPrint('Failed to seed FAQs: \$e');
    }
  }

  List<FaqModel> _allFaqs = [];
  bool _faqsLoaded = false;

  /// Fetches FAQs, caching them locally
  Future<List<FaqModel>> getFaqs({bool forceRefresh = false}) async {
    // Only use the cache when it actually has data — this avoids getting
    // stuck on a previously-cached empty result.
    if (_faqsLoaded && _allFaqs.isNotEmpty && !forceRefresh) return _allFaqs;

    try {
      final snapshot = await _firestore
          .collection('faqs')
          .where('isActive', isEqualTo: true)
          .get();

      _allFaqs = snapshot.docs
          .map((doc) => FaqModel.fromJson(doc.data(), doc.id))
          .toList();
      _allFaqs.sort((a, b) => a.order.compareTo(b.order));

      // Fall back to built-in FAQs if Firestore has none yet.
      if (_allFaqs.isEmpty) {
        _allFaqs = _defaultFaqs();
      }

      _faqsLoaded = true;
      return _allFaqs;
    } catch (e) {
      debugPrint('Error fetching FAQs: $e');
      // Offline / permission error → still show built-in FAQs.
      _allFaqs = _defaultFaqs();
      _faqsLoaded = true;
      return _allFaqs;
    }
  }

  /// Built-in FAQs shown when the Firestore `faqs` collection is empty
  /// or unreachable, so the Help Center is never blank.
  List<FaqModel> _defaultFaqs() {
    final now = DateTime.now();
    final data = <Map<String, dynamic>>[
      {
        'question': 'What is Sherize?',
        'answer':
            'Sherize is a trusted platform that connects skilled professionals with businesses needing efficient BPO tasks. By completing assigned tasks, you earn real money directly into your wallet.',
        'category': 'General',
        'tags': ['about', 'bpo', 'platform'],
      },
      {
        'question': 'How do I accept a task?',
        'answer':
            'Go to your Dashboard, browse the Available Tasks list, tap a task that interests you, and press Accept Task. It will immediately move to My Tasks so you can begin working.',
        'category': 'Tasks',
        'tags': ['accept', 'tasks', 'dashboard'],
      },
      {
        'question': 'Why does it say "No leads available"?',
        'answer':
            'Every task is backed by a finite number of leads (e.g. phone numbers to call). If all leads have already been assigned to or completed by other users, you won\'t be able to accept the task.',
        'category': 'Tasks',
        'tags': ['leads', 'empty', 'error'],
      },
      {
        'question': 'When and how do I get paid?',
        'answer':
            'Once you submit a completed task, your earnings go to Pending. After an admin reviews and approves your submission, the funds are added to your Wallet. You can request a withdrawal once you reach the minimum balance.',
        'category': 'Payments',
        'tags': ['salary', 'payment', 'withdraw', 'wallet'],
      },
      {
        'question': 'How do I update my bank details?',
        'answer':
            'To receive payouts, go to Profile > Bank / UPI Details. Enter your Account Number and IFSC Code. Ensure the name matches your KYC exactly.',
        'category': 'Payments',
        'tags': ['bank', 'account', 'ifsc'],
      },
      {
        'question': 'Why do I need to complete KYC?',
        'answer':
            'KYC (Know Your Customer) verification is required by law to process your payouts. It helps us prevent fraud and ensures a safe environment for all employees.',
        'category': 'KYC',
        'tags': ['kyc', 'verification', 'auth'],
      },
      {
        'question': 'How long does KYC verification take?',
        'answer':
            'Our team reviews all submitted ID documents manually. Typically, your KYC status will update within 24 to 48 hours.',
        'category': 'KYC',
        'tags': ['time', 'status', 'pending'],
      },
      {
        'question': 'Why are my profile changes not saving?',
        'answer':
            'Please ensure you have an active internet connection. All profile updates are securely synced with our servers. If the problem persists, restart the app or submit a Bug Report from Help & Support.',
        'category': 'Technical',
        'tags': ['bug', 'profile', 'save', 'network'],
      },
      {
        'question': 'Do I have to log in every time?',
        'answer':
            'No. As long as you don\'t tap Logout, your session is securely saved and you stay logged in even after closing the app.',
        'category': 'General',
        'tags': ['login', 'session', 'logout'],
      },
      {
        'question': 'How do I report a missing payment?',
        'answer':
            'Go to Help & Support > Contact Us, select Payment Problem as the Issue Type, and submit your request. Our team usually responds within 24 hours.',
        'category': 'Payments',
        'tags': ['support', 'missing', 'issue'],
      },
    ];

    return List<FaqModel>.generate(data.length, (i) {
      final f = data[i];
      return FaqModel(
        id: 'default_${i + 1}',
        question: f['question'] as String,
        answer: f['answer'] as String,
        category: f['category'] as String,
        tags: List<String>.from(f['tags'] as List),
        order: i + 1,
        isActive: true,
        createdAt: now,
      );
    });
  }

  /// Finds 3-5 related FAQs using category or tags
  List<FaqModel> getRelatedFaqs(FaqModel currentFaq) {
    if (!_faqsLoaded || _allFaqs.isEmpty) return [];

    return _allFaqs
        .where((faq) {
          if (faq.id == currentFaq.id) return false;

          // 1. Same Category?
          if (faq.category == currentFaq.category) return true;

          // 2. Overlapping Tags?
          final currentTags =
              currentFaq.tags.map((t) => t.toLowerCase()).toSet();
          final targetTags = faq.tags.map((t) => t.toLowerCase()).toSet();
          final intersection = currentTags.intersection(targetTags);

          return intersection.isNotEmpty;
        })
        .toList()
        .take(5)
        .toList();
  }

  /// Submits a support request or bug report.
  ///
  /// Uses [XFile] instead of [dart:io File] so it works on Flutter Web too.
  Future<String?> submitSupportRequest({
    required String name,
    required String email,
    required String phone,
    required String subject,
    required String message,
    String? issueType,
    XFile? screenshot,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 'User not authenticated';

    try {
      String? screenshotUrl;

      if (screenshot != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final ref = _storage
            .ref()
            .child('support_screenshots')
            .child(user.uid)
            .child('$timestamp.png');

        // Use readAsBytes() — works on both web and native (no dart:io needed)
        final bytes = await screenshot.readAsBytes();
        final uploadTask = await ref.putData(
          bytes,
          SettableMetadata(contentType: 'image/png'),
        );
        screenshotUrl = await uploadTask.ref.getDownloadURL();
      }

      final docRef = _firestore.collection('support_requests').doc();

      final request = SupportRequestModel(
        id: docRef.id,
        userId: user.uid,
        name: name,
        email: email,
        phone: phone,
        subject: subject,
        message: message,
        issueType: issueType,
        screenshotUrl: screenshotUrl,
        createdAt: DateTime.now(),
      );

      await docRef.set(request.toJson());

      return null; // Success
    } catch (e) {
      debugPrint('Error submitting support request: $e');
      return 'Failed to submit request: ${e.toString()}';
    }
  }
}
