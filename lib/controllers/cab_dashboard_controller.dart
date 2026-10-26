import 'dart:async';
import 'dart:developer';
import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/app/multi_service/multi_service_dashboard_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/utils/cab_bottom_navigation.dart';
import 'package:driver/utils/cab_nav_badges.dart';
import 'package:driver/utils/driver_ride_counts.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/preferences.dart';
import 'package:get/get.dart';
import 'package:location/location.dart';

import '../themes/theme_controller.dart';

class CabDashBoardController extends GetxController {
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

  /// The drawer slots this driver has already opened, for the bar's NEW ribbon.
  ///
  /// Reactive rather than read straight from `SharedPreferences` at paint time
  /// so the ribbon disappears the moment the section is opened, without the bar
  /// having to be rebuilt by something else first.
  final RxSet<int> seenSections = <int>{}.obs;

  /// Whether the NEW ribbon has already been cleared for [drawerIndex].
  bool hasSeenSection(int index) => seenSections.contains(index);

  /// Remembers that the driver opened [index], so its NEW ribbon never returns.
  ///
  /// Only the ribboned sections are written, so ordinary navigation does not
  /// turn every drawer tap into a preferences write. The write is fire and
  /// forget: the in-memory set is what the bar reads, and a ribbon that comes
  /// back after a failed disk write is not worth blocking navigation for.
  void markSectionSeen(int index) {
    if (!CabNavBadges.marksSeen(index)) return;
    if (!seenSections.add(index)) return;
    Preferences.setBoolean(CabNavBadges.seenKeyFor(index), true);
  }

  void _loadSeenSections() {
    for (final int index in CabNavBadges.ribbonSections) {
      if (Preferences.getBoolean(CabNavBadges.seenKeyFor(index))) seenSections.add(index);
    }
    // A tap on the bar or the drawer is just a write to `drawerIndex`, from a
    // dozen places. Watching it here is the one hook that catches all of them.
    ever<int>(drawerIndex, markSectionSeen);
    markSectionSeen(drawerIndex.value);
  }

  /// How many rides the driver still has open, live.
  ///
  /// Backed by one listener over `rides where driverId == uid AND status IN
  /// [ongoing]`, capped at [DriverRideCounts.ongoingWatchLimit]. Firestore
  /// serves that shape from its automatic single-field indexes - checked
  /// against the live project - so it costs no new composite index and nothing
  /// to deploy. It is a genuinely live figure: the badge moves the moment a
  /// ride is accepted, started or finished.
  final RxInt ongoingRides = 0.obs;

  /// How many rides the driver has finished.
  ///
  /// A `count()` aggregate rather than a listener, because a busy driver's
  /// completed history is unbounded and streaming it to draw one number would
  /// be exactly the kind of read this app is being cleaned up to avoid. The
  /// aggregate is one operation, and it is re-run whenever the ongoing set
  /// changes - which is precisely when a ride has just been completed - so the
  /// pair stays in step without polling.
  final RxInt completedRides = 0.obs;

  /// Whether the counts have been read at least once. Until then the bar shows
  /// no figures rather than a confident, wrong zero.
  final RxBool rideCountsLoaded = false.obs;

  bool _isCountingCompleted = false;

  /// Drawer slot that renders My Trips. Appended after the existing entries so
  /// no other item's index changes.
  static const int myTripsDrawerIndex = CabBottomNavigation.myTripsDrawerIndex;

  @override
  void onInit() {
    getUser();
    getTheme();
    watchRideCounts();
    _loadSeenSections();
    super.onInit();
  }

  /// Opens the live ongoing-rides listener that feeds the bottom bar.
  ///
  /// Registered in [_subscriptions] like every other listener this controller
  /// opens, so leaving the dashboard closes it.
  void watchRideCounts() {
    final String uid = FireStoreUtils.getCurrentUid();
    if (uid.isEmpty) return;
    _subscriptions.add(
      FireStoreUtils.fireStore
          .collection(CollectionName.ridesBooking)
          .where('driverId', isEqualTo: uid)
          .where('status', whereIn: DriverRideCounts.ongoingStatuses)
          .limit(DriverRideCounts.ongoingWatchLimit)
          .snapshots()
          .listen(
            (snapshot) {
              ongoingRides.value = snapshot.docs.length;
              rideCountsLoaded.value = true;
              // A ride leaving the ongoing set is usually a ride that has just
              // been completed, so this is the right moment - and the only
              // moment - to re-read the completed total.
              refreshCompletedCount(uid);
            },
            onError: (Object error) {
              // A count is decoration. It must never be the reason the
              // dashboard shows an error or stops working.
              log('ongoing ride count listener failed :: $error');
            },
          ),
    );
  }

  /// Re-reads the completed total. Overlapping calls collapse into one.
  Future<void> refreshCompletedCount(String uid) async {
    if (_isCountingCompleted) return;
    _isCountingCompleted = true;
    try {
      final AggregateQuerySnapshot snapshot = await FireStoreUtils.fireStore
          .collection(CollectionName.ridesBooking)
          .where('driverId', isEqualTo: uid)
          .where('status', whereIn: DriverRideCounts.completedStatuses)
          .count()
          .get();
      completedRides.value = snapshot.count ?? 0;
      rideCountsLoaded.value = true;
    } catch (error) {
      log('completed ride count failed :: $error');
    } finally {
      _isCountingCompleted = false;
    }
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
          // My Trips is admin-granted for a fixed number of days. If the grant
          // ends (or is revoked) while the driver is sitting on that screen,
          // send them back to Home rather than leaving them on a page whose
          // buttons no longer do anything.
          if (drawerIndex.value == myTripsDrawerIndex && !Constant.hasMyTripsAccess) {
            drawerIndex.value = CabBottomNavigation.homeDrawerIndex;
            ShowToastDialog.showToast("Your My Trips access has ended".tr);
          }
          // Keep the multi-service bottom bar - which owns the My Trips tab
          // for drivers registered to more than one service - in step, without
          // opening a second listener for it.
          if (Get.isRegistered<MultiServiceDashboardController>()) {
            Get.find<MultiServiceDashboardController>().myTripsEnabled.value = Constant.hasMyTripsAccess;
          }
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
        try {
          await location.enableBackgroundMode(enable: true);
        } catch (_) {}
        location.changeSettings(accuracy: LocationAccuracy.high, distanceFilter: double.parse(Constant.driverLocationUpdate));

        _subscriptions.add(location.onLocationChanged.listen((locationData) async {
          Constant.locationDataFinal = locationData;
          // The position and nothing else, decided on this controller's live
          // profile. See DriverLocationWrite for what saving the whole profile
          // here used to overwrite.
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
            try {
              await location.enableBackgroundMode(enable: true);
            } catch (_) {}
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
