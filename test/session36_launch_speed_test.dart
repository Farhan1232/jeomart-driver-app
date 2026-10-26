import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Session 36 - the launch.
///
/// A signed-in launch used to pay the settings wait, then a round trip for
/// `maintenance_settings`, then another for the driver's `users` document, one
/// after the other. These pin the shape that overlaps them without changing a
/// single decision the splash makes.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// Source with comment lines dropped, so a comment quoting old code is not
  /// mistaken for the code.
  String code(String source) => source
      .split('\n')
      .where((String line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('the splash starts its two reads before the settings wait, not after it', () {
    final String source = code(read('lib/controllers/splash_controller.dart'));
    final int boot = source.indexOf('Future<void> _boot() async {');
    final int maintenance = source.indexOf('_maintenanceRead = FireStoreUtils.isMaintenanceMode();', boot);
    // Session 48 renamed this read to isLoginOrUnknown(), which tells a failed
    // read apart from "no such driver". The order this test guards is the same.
    final int login = source.indexOf('_loginRead = FireStoreUtils.isLoginOrUnknown();', boot);
    final int settingsWait = source.indexOf('GlobalSettingController.settingsReady', boot);

    expect(boot, greaterThan(-1));
    expect(maintenance, greaterThan(boot));
    expect(login, greaterThan(boot));
    expect(maintenance, lessThan(settingsWait));
    expect(login, lessThan(settingsWait));
  });

  test('the splash still decides maintenance, then onboarding, then sign-in', () {
    final String source = code(read('lib/controllers/splash_controller.dart'));
    final int redirect = source.indexOf('Future<void> redirectScreen() async {');
    final int maintenance = source.indexOf('if (await maintenanceRead == true) {', redirect);
    final int onboarding = source.indexOf('Preferences.isFinishOnBoardingKey', redirect);
    final int login = source.indexOf('bool? isLogin = await (loginRead ?? FireStoreUtils.isLoginOrUnknown());', redirect);

    expect(redirect, greaterThan(-1));
    expect(maintenance, greaterThan(redirect));
    expect(onboarding, greaterThan(maintenance));
    expect(login, greaterThan(onboarding));
    // An early read answers one redirect only; a second call reads again.
    expect(source, contains('_maintenanceRead = null;'));
    expect(source, contains('_loginRead = null;'));
  });
}
