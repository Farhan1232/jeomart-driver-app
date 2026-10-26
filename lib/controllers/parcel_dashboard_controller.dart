import 'dart:async';
import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/preferences.dart';
import 'package:get/get.dart';
import 'package:location/location.dart';

import '../constant/constant.dart' show Constant;
import '../themes/theme_controller.dart';

class ParcelDashboardController extends GetxController {
  /// Firestore listeners opened by this controller.
  ///
  /// They used to run for the rest of the session because nothing cancelled
  /// them when the screen closed, and re-entering the screen opened another
  /// set on top.
  final List<StreamSubscription<dynamic>> _subscriptions = <StreamSubscription<dynamic>>[];

  @override
  void onClose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.onClose();
  }

  RxInt drawerIndex = 0.obs;

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
    // Started, not awaited.
    //
    // `updateCurrentLocation()` asks the platform for the permission state,
    // turns on background location and can put a system permission dialog in
    // front of the driver. None of that is anything the `users` listener below
    // needs — and until that listener delivers, the dashboard has no name, no
    // wallet balance, no verification state and no order data. Awaiting it put
    // every one of those behind a dialog the driver might not answer for
    // several seconds, or at all.
    //
    // Both still happen, and in the same order; they simply no longer wait for
    // each other.
    unawaited(updateCurrentLocation());
    _subscriptions.add(
      FireStoreUtils.fireStore.collection(CollectionName.users).doc(FireStoreUtils.getCurrentUid()).snapshots().listen((event) async {
        if (event.exists) {
          userModel.value = UserModel.fromJson(event.data()!);
          Constant.userModel = UserModel.fromJson(event.data()!);
          // Preload all registered sections into cache
          for (final sid in userModel.value.sectionIds ?? <String>[]) {
            if (!Constant.sectionModels.containsKey(sid)) {
              FireStoreUtils.getSectionBySectionId(sid).then((sectionValue) {
                if (sectionValue != null) Constant.sectionModels[sid] = sectionValue;
              });
            }
          }
        }
      }),
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

  Location location = Location();

  /// The location listener this controller currently keeps.
  ///
  /// `updateCurrentLocation()` runs again every time the driver switches to
  /// Available, and each run used to add another `onLocationChanged` listener
  /// beside the ones already running. After five switches every position
  /// update did five profile reads and five profile writes of the same data,
  /// and the dashboard rebuilt for each of them. The newest listener now
  /// replaces the previous one; what it does on each update is unchanged.
  StreamSubscription<dynamic>? _locationSubscription;

  void _keepOnlyNewestLocationSubscription() {
    final StreamSubscription<dynamic> newest = _subscriptions.last;
    final StreamSubscription<dynamic>? previous = _locationSubscription;
    _locationSubscription = newest;
    if (previous != null && !identical(previous, newest)) {
      _subscriptions.remove(previous);
      previous.cancel();
    }
  }

  Future<void> updateCurrentLocation() async {
    try {
      PermissionStatus permissionStatus = await location.hasPermission();
      if (permissionStatus == PermissionStatus.granted) {
        try { await location.enableBackgroundMode(enable: true); } catch (_) {}
        location.changeSettings(accuracy: LocationAccuracy.high, distanceFilter: double.parse(Constant.driverLocationUpdate));

        _subscriptions.add(location.onLocationChanged.listen((locationData) async {
          Constant.locationDataFinal = locationData;
          // The position and nothing else; see DriverLocationWrite.
          await FireStoreUtils.updateDriverLocation(
            live: userModel.value,
            onlyWhenActive: true,
            latitude: locationData.latitude,
            longitude: locationData.longitude,
            heading: locationData.heading,
          );
        }));
        _keepOnlyNewestLocationSubscription();
      } else {
        location.requestPermission().then((permissionStatus) async {
          if (permissionStatus == PermissionStatus.granted) {
            try { await location.enableBackgroundMode(enable: true); } catch (_) {}
            location.changeSettings(accuracy: LocationAccuracy.high, distanceFilter: double.parse(Constant.driverLocationUpdate));
            _subscriptions.add(location.onLocationChanged.listen((locationData) async {
              Constant.locationDataFinal = locationData;
              final UserModel? profile = await FireStoreUtils.updateDriverLocation(
                live: userModel.value,
                onlyWhenActive: true,
                latitude: locationData.latitude,
                longitude: locationData.longitude,
                heading: locationData.heading,
              );
              if (profile != null) ShowToastDialog.closeLoader();
            }));
            _keepOnlyNewestLocationSubscription();
          } else {
            ShowToastDialog.closeLoader();
          }
        });
      }
    } catch (e) {
      print(e);
    }
  }
}
