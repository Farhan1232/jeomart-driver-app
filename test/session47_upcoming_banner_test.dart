// Session 47 - the trip banner on the driver's main screen must wake up when
// the My Trips access appears, not only when the screen is created again.
//
// The client: "When a drivers initiated trip is accepted by a customer then in
// driver main screen there was a banner ... Now that is gone." The banner had
// not been removed: it read Constant.hasMyTripsAccess once, in initState, so a
// driver granted access with the app already open saw nothing at all - and on
// 16 September the access had been wiped from every driver by an older build of
// the driver app, which is what made it look deleted.
//
// Source-level assertions, in the style of the other trip tests here: they pin
// the wiring without a Firebase connection.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String banner = File('lib/widget/upcoming_trip_banner.dart').readAsStringSync();
  final String window = File('lib/utils/upcoming_trip.dart').readAsStringSync();
  final String home = File('lib/app/cab_screen/cab_home_screen.dart').readAsStringSync();

  group('the banner notices access that arrives later', () {
    test('the access is re-read as the screen draws, not once at creation', () {
      final int build = banner.indexOf('Widget build(BuildContext context)');
      final int follow = banner.indexOf('_followTrips();', build);
      final int useStream = banner.indexOf('_stream', build);
      expect(build, isNot(-1));
      expect(follow, isNot(-1), reason: 'build() must re-check before it reads the stream');
      expect(follow, lessThan(useStream));
    });

    test('the minute tick also re-checks it', () {
      expect(banner, contains('setState(_followTrips)'));
      expect(banner, contains('Timer.periodic(const Duration(minutes: 1)'));
    });

    test('the tick is started for every driver, so a late grant is noticed', () {
      final int initState = banner.indexOf('void initState()');
      final int dispose = banner.indexOf('void dispose()');
      final String body = banner.substring(initState, dispose);
      expect(body, contains('_tick = Timer.periodic'));
      // The old shape started the timer inside an access check.
      expect(body.contains('if (uid.isNotEmpty && Constant.hasMyTripsAccess) {'), isFalse);
    });
  });

  group('everything else about the banner is unchanged', () {
    test('the access rule is still the My Trips one, decided in one place', () {
      expect(banner, contains('Constant.hasMyTripsAccess'));
      // One gate in the code - the comments above it may name the rule too.
      expect('uid.isNotEmpty && Constant.hasMyTripsAccess'.allMatches(banner).length, 1);
    });

    test('a driver without access reads nothing from Firestore', () {
      final int follow = banner.indexOf('void _followTrips()');
      final int end = banner.indexOf('@override', follow);
      final String body = banner.substring(follow, end);
      expect(body, contains('final bool allowed = uid.isNotEmpty && Constant.hasMyTripsAccess;'));
      expect(body, contains('if (allowed && _stream == null)'));
      expect(body, contains('} else if (!allowed && _stream != null) {'));
    });

    test('the query and its limit are the ones My Trips already uses', () {
      expect(banner, contains('DriverTripService.myTripsQuery(uid).limit(UpcomingTripBanner.watchLimit).snapshots()'));
      expect('snapshots()'.allMatches(banner).length, 1, reason: 'one stream, never two');
      expect(banner, contains('static const int watchLimit = 20;'));
    });

    test('the window that decides which trip is shown is untouched', () {
      expect(window, contains('static const Duration leadIn = Duration(hours: 2);'));
      expect(window, contains('static const Duration holdOver = Duration(hours: 6);'));
    });

    test('a booked trip still reads as booked, and taps through to My Trips', () {
      expect(banner, contains("final bool booked = trip.status == DriverTripStatus.booked;"));
      expect(banner, contains('"Your booked trip".tr'));
      expect(banner, contains('onTap: () => Get.to(() => const MyTripsScreen())'));
    });

    test('it is still on the cab home screen, over the map', () {
      expect(home, contains('UpcomingTripBanner(isDark: isDark)'));
    });
  });
}
