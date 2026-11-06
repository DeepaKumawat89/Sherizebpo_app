import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/notification_model.dart';
import '../routes.dart';

/// Top-level background message handler for FCM
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Just log it or show a local notification if required.
  debugPrint('Handling a background message: ${message.messageId}');
}

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _initialized = false;

  Future<void> initialize(
      {required GlobalKey<NavigatorState> navigatorKey}) async {
    if (_initialized) return;

    // 1. Request permissions
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint(
        'User granted notification permission: ${settings.authorizationStatus}');

    // 2. Set background handler
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }

    // 4. Create Android channel for foreground notifications (needed for reference below)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // id
      'High Importance Notifications', // title
      description:
          'This channel is used for important notifications.', // description
      importance: Importance.high,
    );

    // 3. Initialize Local Notifications (Mobile Only)
    if (!kIsWeb) {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings();
      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _localNotifications.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          _handleLocalNotificationTap(response, navigatorKey);
        },
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    // 5. Update FCM token to Firestore on login
    await updateToken();

    // 6. Listen for token refreshes
    _fcm.onTokenRefresh.listen((token) {
      _saveTokenToFirestore(token);
    }).onError((err) {
      debugPrint('FCM Token Refresh Error: $err');
    });

    // 7. Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        debugPrint(
            'Message also contained a notification: ${message.notification}');
        if (!kIsWeb) {
          _showLocalNotification(message, channel);
        }
      }
    });

    // 8. Handle background/terminated message taps
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('A new onMessageOpenedApp event was published!');
      _handleRemoteMessageInteraction(message, navigatorKey);
    });

    // Handle initial message if app was terminated and opened by tap
    RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App opened via initial FCM message!');
      _handleRemoteMessageInteraction(initialMessage, navigatorKey);
    }

    _initialized = true;
  }

  Future<void> updateToken() async {
    try {
      // Web FCM requires a VAPID key — skip silently if unavailable
      String? token;
      if (kIsWeb) {
        // Silently skip on web to avoid crashes when VAPID key is not configured
        debugPrint('FCM token update skipped on web (no VAPID key configured)');
        return;
      } else {
        token = await _fcm.getToken();
      }
      if (token != null) {
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      debugPrint('Error fetching FCM token: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'lastTokenUpdated': FieldValue.serverTimestamp(),
      });
      debugPrint('FCM token updated in Firestore');
    } catch (e) {
      debugPrint('Error saving FCM token to Firestore: $e');
    }
  }

  void _showLocalNotification(
      RemoteMessage message, AndroidNotificationChannel channel) {
    if (kIsWeb) return;

    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  void _handleLocalNotificationTap(
      NotificationResponse response, GlobalKey<NavigatorState> navigatorKey) {
    if (response.payload != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(response.payload!);
        _navigateToScreen(data, navigatorKey);
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
      }
    }
  }

  void _handleRemoteMessageInteraction(
      RemoteMessage message, GlobalKey<NavigatorState> navigatorKey) {
    _navigateToScreen(message.data, navigatorKey);
  }

  void _navigateToScreen(
      Map<String, dynamic> data, GlobalKey<NavigatorState> navigatorKey) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final String? relatedTaskId = data['relatedTaskId'];
    final String? relatedSubmissionId = data['relatedSubmissionId'];

    if (relatedSubmissionId != null && relatedSubmissionId.isNotEmpty) {
      // Admin navigating to submission details
      Navigator.pushNamed(
        context,
        AppRoutes.submissionDetail,
        arguments: relatedSubmissionId,
      );
    } else if (relatedTaskId != null && relatedTaskId.isNotEmpty) {
      // Worker navigating to task details
      Navigator.pushNamed(
        context,
        AppRoutes.taskList,
        arguments: relatedTaskId,
      );
    } else {
      // Default to notifications screen
      Navigator.pushNamed(context, AppRoutes.notifications);
    }
  }

  Stream<List<NotificationModel>> getUserNotifications() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotificationModel.fromJson(doc.data(), doc.id))
            .toList());
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final batch = _firestore.batch();
      final querySnapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('read', isEqualTo: false)
          .get();

      for (var doc in querySnapshot.docs) {
        batch.update(doc.reference, {'read': true});
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }
}
