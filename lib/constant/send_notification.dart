// ignore_for_file: non_constant_identifier_names

import 'dart:convert';
import 'package:driver/constant/constant.dart';
import 'package:driver/models/notification_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:driver/utils/network_timeout.dart';

class SendNotification {
  static final _scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

  static Future getCharacters() {
    return http.get(Uri.parse(Constant.jsonNotificationFileURL.toString())).timeout(NetworkTimeout.notification);
  }

  /// The service-account document, kept for the life of the process.
  ///
  /// It was downloaded again for **every single notification** the app sends —
  /// and the driver app sends one on every order acceptance, pickup, delivery
  /// and cancellation, each time behind an `await` the driver is watching a
  /// spinner for. The file is a fixed credential at a fixed URL; it does not
  /// change between two taps. Held per launch rather than persisted, so
  /// rotating it still takes effect on the next start.
  static Map<String, dynamic>? _serviceAccount;

  /// The OAuth token that document buys, and the moment it stops being valid.
  ///
  /// Caching the *file* removed one download per notification, but
  /// `clientViaServiceAccount` was still called every time - and that is not a
  /// lookup: it signs a JWT on this isolate and exchanges it with Google over
  /// the network. So every accept, pickup, completion and cancellation still
  /// paid for a full round trip plus an RSA signature before its push could
  /// leave. Google issues these for an hour; they are reused until a minute
  /// before they lapse.
  static String? _accessToken;
  static DateTime? _accessTokenExpiry;

  /// Test seam, and the way to force a re-read after a rotation.
  static void clearServiceAccountCache() {
    _serviceAccount = null;
    _accessToken = null;
    _accessTokenExpiry = null;
  }

  static Future<String> getAccessToken() async {
    final String? cached = _accessToken;
    final DateTime? expiry = _accessTokenExpiry;
    if (cached != null && expiry != null && DateTime.now().isBefore(expiry)) {
      return cached;
    }

    Map<String, dynamic> jsonData = _serviceAccount ?? {};

    if (jsonData.isEmpty) {
      await getCharacters().then((response) {
        jsonData = json.decode(response.body);
      });
      _serviceAccount = jsonData;
    }
    final serviceAccountCredentials = ServiceAccountCredentials.fromJson(jsonData);

    final client = await clientViaServiceAccount(serviceAccountCredentials, _scopes);
    final AccessToken token = client.credentials.accessToken;
    _accessToken = token.data;
    // A minute of slack, so a token that is about to lapse is not the one a
    // send goes out with.
    _accessTokenExpiry = token.expiry.toLocal().subtract(const Duration(minutes: 1));
    return token.data;
  }

  static Future<bool> sendFcmMessage(String type, String token, Map<String, dynamic>? payload) async {
    print(type);
    try {
      final String accessToken = await getAccessToken();
      // The OAuth bearer token, written to the device log on every send.
      // Debug builds only.
      if (kDebugMode) {
        debugPrint("accessToken=======>");
        debugPrint(accessToken);
      }
      NotificationModel? notificationModel = await FireStoreUtils.getNotificationContent(type);

      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/${Constant.senderId}/messages:send'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(
          <String, dynamic>{
            'message': {
              'token': token,
              'notification': {'body': notificationModel!.message ?? '', 'title': notificationModel.subject ?? ''},
              'data': payload,
            }
          },
        ),
      ).timeout(NetworkTimeout.notification);

      debugPrint("Notification=======>");
      debugPrint(response.statusCode.toString());
      debugPrint(response.body);
      return true;
    } catch (e) {
      debugPrint("Notification error :::::::::: ${e.toString()}");
      return false;
    }
  }

  static Future<bool> sendOneNotification({required String token, required String title, required String body, required Map<String, dynamic> payload}) async {
    try {
      final String accessToken = await getAccessToken();
      // The OAuth bearer token, written to the device log on every send.
      // Debug builds only.
      if (kDebugMode) {
        debugPrint("accessToken=======>");
        debugPrint(accessToken);
      }

      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/${Constant.senderId}/messages:send'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(
          <String, dynamic>{
            'message': {
              'token': token,
              'notification': {'body': body, 'title': title},
              'data': payload,
            }
          },
        ),
      ).timeout(NetworkTimeout.notification);

      debugPrint("Notification=======>");
      debugPrint(response.statusCode.toString());
      debugPrint(response.body);
      return true;
    } catch (e) {
      debugPrint(e.toString());
      return false;
    }
  }

  static Future<bool> sendChatFcmMessage(String title, String message, String token, Map<String, dynamic>? payload) async {
    try {
      final String accessToken = await getAccessToken();
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/${Constant.senderId}/messages:send'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(
          <String, dynamic>{
            'message': {
              'token': token,
              'notification': {'body': message, 'title': title},
              'data': payload,
            }
          },
        ),
      ).timeout(NetworkTimeout.notification);
      debugPrint("Notification=======>");
      debugPrint(response.statusCode.toString());
      debugPrint(response.body);
      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }
}
