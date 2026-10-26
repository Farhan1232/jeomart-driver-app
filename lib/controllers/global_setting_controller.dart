import 'dart:async';
import 'dart:developer';

import 'package:driver/constant/constant.dart';
import 'package:driver/models/currency_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../constant/collection_name.dart';

class GlobalSettingController extends GetxController {

  /// Completes when the first pass of [FireStoreUtils.getSettings] has finished.
  ///
  /// The splash screen waits on this instead of sleeping for a fixed three
  /// seconds. That timer was a guess at how long the settings reads take, and
  /// it was wrong in both directions: too long on a good connection, and on a
  /// slow one the app left the splash and started building screens against an
  /// unread `Constant` - the app colour, the currency, the distance unit and
  /// the OTP switches all still at their compile-time defaults.
  ///
  /// Static because the splash controller needs it without holding the
  /// instance, and because the first pass only ever happens once per launch.
  static final Completer<void> _settingsReady = Completer<void>();

  static Future<void> get settingsReady => _settingsReady.future;

  static void _markSettingsReady() {
    if (!_settingsReady.isCompleted) _settingsReady.complete();
  }
  @override
  void onInit() {
    notificationInit();
    getCurrentCurrency();

    super.onInit();
  }

  Future<void> getCurrentCurrency() async {
    FireStoreUtils.fireStore
        .collection(CollectionName.currencies)
        .where("isActive", isEqualTo: true)
        .snapshots()
        .listen((event) {
          if (event.docs.isNotEmpty) {
            Constant.currencyModel = CurrencyModel.fromJson(
              event.docs.first.data(),
            );
          } else {
            Constant.currencyModel = CurrencyModel(
              id: "",
              code: "USD",
              decimalDigits: 2,
              enable: true,
              name: "US Dollar",
              symbol: "\$",
              symbolAtRight: false,
            );
          }
        });
    try {
      await FireStoreUtils.getSettings();
    } finally {
      // In a `finally`: settings that could not be read must still release the
      // splash screen, or a failed read strands the app on the logo.
      _markSettingsReady();
    }
  }

  NotificationService notificationService = NotificationService();

  void notificationInit() {
    notificationService.initInfo().then((value) async {
      final token = await NotificationService.getToken();
      if (token == null) return;
      log(":::::::TOKEN:::::: $token");
      if (FirebaseAuth.instance.currentUser != null) {
        await FireStoreUtils.getUserProfile(
          FireStoreUtils.getCurrentUid(),
        ).then((value) {
          if (value != null) {
            UserModel driverUserModel = value;
            driverUserModel.fcmToken = token;
            FireStoreUtils.updateUser(driverUserModel);
          }
        });
      }
    });
  }
}
