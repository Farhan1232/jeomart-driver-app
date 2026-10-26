import 'dart:convert';
import 'dart:developer';
import 'package:driver/app/chat_screens/chat_screen.dart';
import 'package:driver/app/dash_board_screen/dash_board_screen.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/controllers/dash_board_controller.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

Future<void> firebaseMessageBackgroundHandle(RemoteMessage message) async {
  log("BackGround Message :: ${message.messageId}");
}

class NotificationService {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initInfo() async {
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    var request = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (request.authorizationStatus == AuthorizationStatus.authorized ||
        request.authorizationStatus == AuthorizationStatus.provisional) {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosInitializationSettings =
          DarwinInitializationSettings();

      final InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: iosInitializationSettings,
          );

      await flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (response.payload != null) {
            final data = jsonDecode(response.payload!);
            final String type = data['type'] ?? '';
            final String role = data['chatType'] ?? '';
            final String orderId = data['orderId'] ?? '';
            final String senderId = data['senderId'] ?? '';
            handleMessageClick(
              type: type,
              role: role,
              orderId: orderId,
              senderId: senderId,
            );
          }
        },
      );

      await setupInteractedMessage();
    }
  }

  Future<void> setupInteractedMessage() async {
    // App opened from terminated state
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      final String type = initialMessage.data['type'] ?? '';
      final String role = initialMessage.data['chatType'] ?? '';
      final String orderId = initialMessage.data['orderId'] ?? '';
      final String senderId = initialMessage.data['senderId'] ?? '';
      handleMessageClick(
        type: type,
        role: role,
        orderId: orderId,
        senderId: senderId,
      );
    }

    // App in background and notification tapped
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage? message) {
      if (message != null) {
        final String type = message.data['type'] ?? '';
        final String role = message.data['chatType'] ?? '';
        final String orderId = message.data['orderId'] ?? '';
        final String senderId = message.data['senderId'] ?? '';
        handleMessageClick(
          type: type,
          role: role,
          orderId: orderId,
          senderId: senderId,
        );
      }
    });

    // App in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        display(message);
      }
    });

    if (await _isAppleMessagingReady()) {
      try {
        await FirebaseMessaging.instance.subscribeToTopic("driver");
      } on FirebaseException catch (error) {
        log("Unable to subscribe to driver notifications: $error");
      }
    } else {
      log("Skipping notification topic subscription until APNs is ready.");
    }
  }

  static Future<String?> getToken() async {
    if (!await _isAppleMessagingReady()) {
      log("FCM token is not available because APNs is not ready.");
      return null;
    }

    try {
      return await FirebaseMessaging.instance.getToken();
    } on FirebaseException catch (error) {
      log("Unable to retrieve FCM token: $error");
      return null;
    }
  }

  static Future<bool> _isAppleMessagingReady() async {
    final isApplePlatform =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (!isApplePlatform) {
      return true;
    }

    for (var attempt = 0; attempt < 10; attempt++) {
      if (await FirebaseMessaging.instance.getAPNSToken() != null) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  void display(RemoteMessage message) async {
    try {
      const AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
            'driver_notifications_channel',
            'Driver Notifications',
            channelDescription: 'App Notifications',
            importance: Importance.high,
            priority: Priority.high,
            ticker: 'ticker',
          );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: iosDetails,
      );

      await flutterLocalNotificationsPlugin.show(
        id: 0,
        title: message.notification?.title,
        body: message.notification?.body,
        notificationDetails: notificationDetails,
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      log("Notification display error: $e");
    }
  }

  Future<void> handleMessageClick({
    required String type,
    String? senderId,
    String? orderId,
    required String role,
  }) async {
    final String uid = FireStoreUtils.getCurrentUid();
    if (type == 'admin_chat' && uid.isNotEmpty) {
      DashBoardController controller = Get.put(DashBoardController());
      controller.drawerIndex.value = 7;
      Get.offAll(DashBoardScreen());
    } else if (type == 'orderChat') {
      ShowToastDialog.showLoader("Please wait".tr);
      log(
        "Customer Notification :: $senderId :: ${FireStoreUtils.getCurrentUid()}",
      );
      final List<UserModel?> people = await Future.wait(<Future<UserModel?>>[
        FireStoreUtils.getUserProfile(senderId.toString()),
        FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid()),
      ]);
      final UserModel? customer = people[0];
      final UserModel? driver = people[1];
      ShowToastDialog.closeLoader();
      if (customer == null || driver == null) {
        ShowToastDialog.showToast("User not found".tr);
        return;
      }
      // The chat opens over the screen the driver is on. This used to run
      // `Get.offAll(DashBoardScreen())` first - the delivery dashboard, for
      // every driver - which for a cab, parcel or rental driver closed their
      // own dashboard and with it the listener that puts ride requests and
      // the ride in progress on screen. A customer's message tapped mid-ride
      // left the driver on the wrong dashboard with no ride.
      await _openOnTop(
        const ChatScreen(),
        arguments: {
          "senderName": driver.fullName(),
          "senderId": driver.id,
          "senderProfileUrl": driver.profilePictureURL ?? "",
          "receivedName": customer.fullName(),
          "receivedId": customer.id,
          "receivedProfileUrl": customer.profilePictureURL ?? "",
          "orderId": orderId,
          "token": customer.fcmToken,
          "chatType": Constant.userRoleDriver,
        },
      );
    }
  }

  /// Pushes [screen] over whatever the driver is looking at.
  ///
  /// A notification that starts the app lands while the splash screen is
  /// still deciding where the session goes, and the splash ends in its own
  /// `Get.offAll(...)`, which would take this screen with it. So a push that
  /// arrives on the splash waits for it to hand over - bounded, because a wait
  /// that never ends is worse than a notification that opens nothing.
  static Future<void> _openOnTop(Widget screen, {Map<String, dynamic>? arguments}) async {
    for (int attempt = 0; attempt < _splashWaitAttempts; attempt++) {
      final String route = Get.currentRoute;
      if (route.isNotEmpty && route != '/' && !route.contains('SplashScreen')) break;
      await Future<void>.delayed(_splashWaitInterval);
    }
    try {
      await Get.to(() => screen, arguments: arguments);
    } catch (error) {
      log('opening a notification screen failed :: $error');
    }
  }

  static const int _splashWaitAttempts = 40;
  static const Duration _splashWaitInterval = Duration(milliseconds: 250);
}
