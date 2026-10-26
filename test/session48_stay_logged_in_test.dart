// Session 48 - a driver stays signed in until they press Logout.
//
// The client: "when driver login then should be remain login whenever its logout
// button click or logout yourself, like session out". The app signed drivers out
// by itself because every failure on the launch path ended at signOut():
//
//   * userExistOrNot() returns false when the read FAILS, so isLogin() said "not
//     signed in" for a dropped connection;
//   * getUserProfile() returns null for both "no document" and "read failed",
//     and the splash signed out on null;
//   * _boot()'s catch signed out on any thrown error.
//
// None of those is the driver being refused. A real refusal - a deleted account,
// a disabled one, the wrong role - is decided by a read that SUCCEEDED, and must
// still sign out exactly as before.
//
// Source-level assertions, in the style of the other splash tests here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  /// Source with comment lines dropped, so a comment quoting old code is not
  /// mistaken for the code itself.
  String code(String source) => source
      .split('\n')
      .where((String line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  final String splash = code(read('lib/controllers/splash_controller.dart'));
  final String utils = code(read('lib/utils/fire_store_utils.dart'));

  group('a failed read never ends the session', () {
    test('the splash no longer signs out when something on the way throws', () {
      final int boot = splash.indexOf('Future<void> _boot() async {');
      final int end = splash.indexOf('Future<void> _carryOnSignedIn()');
      expect(boot, greaterThan(-1));
      expect(end, greaterThan(boot));
      final String body = splash.substring(boot, end);
      expect(body, contains('await _carryOnSignedIn();'));
      expect(body.contains('_signOutTo'), isFalse,
          reason: 'a thrown read is not the driver being refused');
    });

    test('carrying on signed in never calls signOut', () {
      final int start = splash.indexOf('Future<void> _carryOnSignedIn() async {');
      expect(start, greaterThan(-1));
      final String body = splash.substring(start, splash.indexOf('\n  }\n', start));
      expect(body.contains('signOut'), isFalse);
      expect(body.contains('_signOutTo'), isFalse);
      expect(body, contains('Get.offAll'));
    });

    test('"read failed" is a different answer from "no such driver"', () {
      expect(utils, contains('static Future<bool?> isLoginOrUnknown() async {'));
      final int start = utils.indexOf('static Future<bool?> isLoginOrUnknown() async {');
      final String body = utils.substring(start, utils.indexOf('\n  }\n', start));
      expect(body, contains('return null;'), reason: 'null means the read failed');
      expect(body, contains('return true;'));
      expect(body, contains('return false;'));
    });

    test('a profile read that failed throws instead of reading as "no profile"', () {
      expect(utils, contains('static Future<UserModel?> getUserProfileOrThrow(String uuid) async {'));
      final int start = utils.indexOf('static Future<UserModel?> getUserProfileOrThrow(String uuid) async {');
      final String body = utils.substring(start, utils.indexOf('\n  }\n', start));
      expect(body.contains('catchError'), isFalse);
      expect(body, contains('if (!doc.exists) return null;'));
    });
  });

  group('a real refusal still signs out, exactly as before', () {
    test('a deleted driver is still signed out', () {
      final int start = utils.indexOf('static void _endDeletedDriverSession(String uid)');
      expect(start, greaterThan(-1));
      final String body = utils.substring(start, utils.indexOf('\n  }\n', start));
      expect(body, contains('FirebaseAuth.instance.signOut()'));
      expect(body, contains('Get.offAll(const LoginScreen())'));
    });

    test('the disabled and wrong-role branches still sign out', () {
      expect(splash, contains('await _signOutTo(const LoginScreen());'));
      expect(splash, contains('Future<void> _signOutTo(Widget screen) async {'));
    });

    test('userExistOrNot keeps its bool for the login and OTP screens', () {
      expect(utils, contains('static Future<bool> userExistOrNot(String uid) async {'));
      expect(read('lib/controllers/login_controller.dart'), contains('FireStoreUtils.userExistOrNot('));
    });
  });

  group('the launch shape the earlier sessions pinned is unchanged', () {
    test('both reads still start before the settings wait', () {
      final int boot = splash.indexOf('Future<void> _boot() async {');
      final int maintenance = splash.indexOf('_maintenanceRead = FireStoreUtils.isMaintenanceMode();', boot);
      final int settingsWait = splash.indexOf('GlobalSettingController.settingsReady', boot);
      expect(maintenance, greaterThan(boot));
      expect(maintenance, lessThan(settingsWait));
    });

    test('the signed-in driver still reaches memory on the read', () {
      final int assign = splash.indexOf('Constant.userModel = userModel;');
      final int write = splash.indexOf('unawaited(FireStoreUtils.updateUser(userModel));');
      expect(assign, greaterThan(-1));
      expect(assign, lessThan(write));
    });
  });
}
