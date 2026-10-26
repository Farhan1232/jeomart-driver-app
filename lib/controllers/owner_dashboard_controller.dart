import 'dart:async';

import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/preferences.dart';
import 'package:get/get.dart';

import '../themes/theme_controller.dart';

class OwnerDashboardController extends GetxController{
  RxInt drawerIndex = 0.obs;

  /// Firestore listeners opened by this controller.
  ///
  /// The owner dashboard is entered and left repeatedly, and its `users`
  /// listener was neither held nor cancelled: every visit left another
  /// permanent listener on the same document behind it, and every one of them
  /// re-parsed and re-published the profile on every change. Same fix the cab
  /// dashboard already carries.
  final List<StreamSubscription<dynamic>> _subscriptions = <StreamSubscription<dynamic>>[];

  @override
  void onClose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.onClose();
  }

  @override
  void onInit() {
    getUser();
    getTheme();
    super.onInit();
  }

  Rx<UserModel> userModel = UserModel().obs;

  DateTime? currentBackPressTime;
  RxBool canPopNow = false.obs;

  Future<void> getUser() async {
    _subscriptions.add(
      FireStoreUtils.fireStore.collection(CollectionName.users).doc(FireStoreUtils.getCurrentUid()).snapshots().listen(
            (event) {
          if (event.exists) {
            // Two separate models on purpose, matching every other dashboard
            // controller in this app: the observable copy and Constant.userModel
            // are mutated independently in places, so they must not alias.
            userModel.value = UserModel.fromJson(event.data()!);
            Constant.userModel = UserModel.fromJson(event.data()!);
          }
        },
      ),
    );
  }

  RxString isDarkMode = "Light".obs;
  RxBool isDarkModeSwitch = false.obs;

  void getTheme() {
    bool isDark = Preferences.getBoolean(Preferences.themKey);
    isDarkMode.value = isDark ? "Dark" : "Light";
    isDarkModeSwitch.value = isDark;
  }

  void toggleDarkMode(bool value) {
    isDarkModeSwitch.value = value;
    isDarkMode.value = value ? "Dark" : "Light";
    Preferences.setBoolean(Preferences.themKey, value);
    // Update ThemeController for instant app theme change
    if (Get.isRegistered<ThemeController>()) {
      final themeController = Get.find<ThemeController>();
      themeController.isDark.value = value;
    }
  }

}