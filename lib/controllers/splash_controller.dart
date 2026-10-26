import 'dart:async';
import 'dart:developer';

import 'package:driver/app/auth_screen/login_screen.dart';
import 'package:driver/app/maintenance_mode_screen/maintenance_mode_screen.dart';
import 'package:driver/app/on_boarding_screen.dart';
import 'package:driver/app/owner_screen/owner_dashboard_screen.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/controllers/global_setting_controller.dart';
import 'package:driver/controllers/signup_controller.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/notification_service.dart';
import 'package:driver/utils/preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SplashController extends GetxController {
  /// The shortest time the splash art stays up, so a warm start does not flash
  /// past it.
  static const Duration _minimumSplash = Duration(milliseconds: 800);

  /// Hard cap on waiting for `settings/*`. Past this the app carries on rather
  /// than sitting on the logo: every settings document that matters after
  /// startup is behind a live listener, so a late arrival still lands.
  static const Duration _settingsWait = Duration(seconds: 6);

  @override
  void onInit() {
    super.onInit();
    unawaited(_boot());
  }

  /// Replaces `Timer(const Duration(seconds: 3), redirectScreen)`.
  ///
  /// Three problems with that timer, all of them things the client saw:
  ///
  ///  * it was three seconds of doing nothing, spent *before* `redirectScreen`
  ///    started its own chain of network round trips, so startup cost three
  ///    seconds **plus** the work rather than the longer of the two;
  ///  * it was a guess at how long `getSettings()` takes. On a slow connection
  ///    the app left the splash before the settings arrived and built its first
  ///    screen against compile-time defaults;
  ///  * nothing below it was guarded, so a single failed read left the app on
  ///    the splash art with no error and no way forward.
  ///
  /// The minimum splash time and the settings load now run together, every wait
  /// is bounded, and [redirectScreen] can no longer fail silently.
  Future<void> _boot() async {
    final Future<void> minimumSplash = Future<void>.delayed(_minimumSplash);
    _maintenanceRead = FireStoreUtils.isMaintenanceMode();
    _loginRead = FireStoreUtils.isLoginOrUnknown();
    try {
      await GlobalSettingController.settingsReady.timeout(_settingsWait);
    } catch (e) {
      log('splash: carrying on without settings :: $e');
    }
    await minimumSplash;
    try {
      await redirectScreen();
    } catch (e) {
      // Something on the way failed - almost always a read that could not reach
      // Firestore. That is not the driver being refused, so the session is kept
      // and they carry on into the app; the screens they land on re-read what
      // they need anyway. Only a definite answer signs anybody out.
      log('splash: redirect failed, keeping the session :: $e');
      await _carryOnSignedIn();
    }
  }

  /// Stay signed in after a failed read, and go where a signed-in driver goes.
  ///
  /// The client's report: "when driver login then should remain login until he
  /// clicks logout". Every failure on the launch path used to end at
  /// [_signOutTo], so one unlucky read on a weak connection logged the driver
  /// out for good. Nothing here decides the driver is allowed - that was decided
  /// when they signed in - it simply refuses to throw away a session over a
  /// question that was never answered.
  Future<void> _carryOnSignedIn() async {
    final UserModel? known = Constant.userModel;
    try {
      if (known != null && known.role == Constant.userRoleDriver) {
        if (known.isOwner == true) {
          Get.offAll(OwnerDashboardScreen());
        } else {
          await SignupController.navigateByUserModel(known);
        }
        return;
      }
    } catch (e) {
      log('splash: could not route the signed-in driver :: $e');
    }
    // No profile in memory to route with: leave them on the login screen, but
    // WITHOUT signing out, so the session is still there on the next launch.
    Get.offAll(const LoginScreen());
  }

  /// The one exit used whenever the stored session cannot be trusted - a
  /// profile that no longer exists, a wrong role, an inactive account, or an
  /// error on the way. Previously each of those either repeated the same two
  /// lines or, in the case of a missing profile, did nothing at all and left
  /// the user looking at the splash screen.
  Future<void> _signOutTo(Widget screen) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      log('splash: sign-out failed :: $e');
    }
    Get.offAll(() => screen);
  }

  /// The two reads [redirectScreen] opens with, started by [_boot] the moment
  /// the splash appears rather than after the settings wait and the minimum
  /// splash time.
  ///
  /// Both are plain reads that decide nothing by themselves: [redirectScreen]
  /// still asks "maintenance?" first, then checks onboarding, then "signed
  /// in?", and acts on the answers in that order. Starting them early only
  /// means the answers are usually already here when it asks. Before, every
  /// launch paid the settings wait, then a round trip for
  /// `maintenance_settings`, then another for the driver's `users` document,
  /// one after the other.
  Future<bool>? _maintenanceRead;
  Future<bool?>? _loginRead;

  Future<void> redirectScreen() async {
    final Future<bool> maintenanceRead = _maintenanceRead ?? FireStoreUtils.isMaintenanceMode();
    final Future<bool?>? loginRead = _loginRead;
    _maintenanceRead = null;
    _loginRead = null;

    if (await maintenanceRead == true) {
      Get.offAll(() => MaintenanceModeScreen());
      return;
    } else {
      if (Preferences.getBoolean(Preferences.isFinishOnBoardingKey) == false) {
        Get.offAll(const OnboardingScreen());
      } else {
        // null - the `users` read could not be made at all. That is not the
        // driver being refused, so the session stands and they carry on; the
        // screens they land on re-read what they need. Only `false` - a read
        // that succeeded and found no such driver - signs anybody out.
        bool? isLogin = await (loginRead ?? FireStoreUtils.isLoginOrUnknown());
        if (isLogin == null) {
          await _carryOnSignedIn();
        } else if (isLogin == true) {
          UserModel? profile;
          try {
            profile = await FireStoreUtils.getUserProfileOrThrow(
              FireStoreUtils.getCurrentUid(),
            );
          } catch (e) {
            // Same rule one step further in: the profile could not be read, so
            // nothing has been decided about this driver. Keep them signed in.
            log('splash: the profile could not be read, keeping the session :: $e');
            await _carryOnSignedIn();
            return;
          }
          await Future<UserModel?>.value(profile).then((value) async {
            if (value != null) {
              UserModel userModel = value;
              log(userModel.toJson().toString());
              if (userModel.role == Constant.userRoleDriver) {
                if (userModel.active == true) {
                  // The signed-in driver, published the moment it is read.
                  //
                  // It used to reach `Constant.userModel` only as a side effect
                  // of the `updateUser` write below, which is no longer awaited
                  // - saving the push token was costing every launch a round
                  // trip. A slow write therefore left the session with no
                  // signed-in driver in memory, and everything gated on that
                  // quietly did nothing: sending a bid, for one, returns
                  // without a word when `Constant.userModel` is null.
                  Constant.userModel = userModel;

                  // Which services this driver is in, settled *before* the save
                  // below rather than after it, so a document whose
                  // `serviceTypes` had gone wrong is corrected on disk instead
                  // of having the wrong value written back to it every launch.
                  // Started alongside the token fetch, not after it, so the two
                  // round trips overlap and the launch is no slower than it was.
                  final Future<List<String>> services =
                      SignupController.resolveServiceTypes(userModel);
                  final Future<String?> token = NotificationService.getToken();
                  await services;
                  final fcmToken = await token;
                  if (fcmToken != null) userModel.fcmToken = fcmToken;
                  // Not awaited: saving the push token is a write the driver
                  // never sees, and holding the splash screen open for it added
                  // a whole round trip to every launch. It still happens, just
                  // not in front of the user.
                  unawaited(FireStoreUtils.updateUser(userModel));
                  if (userModel.isOwner == true) {
                    Get.offAll(OwnerDashboardScreen());
                  } else {
                    await SignupController.navigateByUserModel(userModel);
                  }
                } else {
                  await _signOutTo(const LoginScreen());
                }
              } else {
                await _signOutTo(const LoginScreen());
              }
            } else {
              // A signed-in uid whose `users` document has gone. Nothing used
              // to handle this at all, so the app stayed on the splash screen.
              await _signOutTo(const LoginScreen());
            }
          });
        } else {
          await _signOutTo(const LoginScreen());
        }
      }
    }
  }
}
