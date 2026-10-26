import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/services/audio_player_service.dart';
import 'package:driver/services/bidding_service.dart';
import 'package:driver/utils/cab_request_slot.dart';
import 'package:driver/utils/driver_location_write.dart';
import 'package:flutter_test/flutter_test.dart';

/// Session 43 - a ride request reaches the driver, rings and can be answered
/// without anything in the app getting in its way.
///
/// The rules are tested directly. The controllers and screens open Firebase
/// listeners, so their shape is pinned from source, with comment lines dropped
/// so a comment quoting old code is never mistaken for the code.
void main() {
  String read(String path) => File(path).readAsStringSync();

  String code(String source) => source.split('\n').where((String line) => !line.trimLeft().startsWith('//')).join('\n');

  String bodyOf(String source, String signature) {
    final int start = source.indexOf(signature);
    expect(start, greaterThan(-1), reason: '$signature is missing');
    final int end = source.indexOf('\n  }\n', start);
    return source.substring(start, end == -1 ? source.length : end);
  }

  group('the ride request on the driver\'s document belongs to the dispatcher', () {
    test('a saved copy clears it only when it held a request the caller let go of', () {
      expect(CabRequestSlot.shouldClear(current: null, loadedWithRequest: true), isTrue);
      expect(CabRequestSlot.shouldClear(current: null, loadedWithRequest: false), isFalse,
          reason: 'a copy read before the offer landed must not delete the offer');
      expect(CabRequestSlot.shouldClear(current: Object(), loadedWithRequest: true), isFalse);
      expect(CabRequestSlot.shouldClear(current: Object(), loadedWithRequest: false), isFalse);
    });

    test('a profile remembers whether it was read with a request, and never writes that down', () {
      final UserModel withRequest = UserModel.fromJson(<String, dynamic>{
        'id': 'driver1',
        'ordercabRequestData': <String, dynamic>{'id': 'ride1'},
      });
      final UserModel without = UserModel.fromJson(<String, dynamic>{'id': 'driver1'});

      expect(withRequest.loadedWithCabRequest, isTrue);
      expect(without.loadedWithCabRequest, isFalse);
      expect(UserModel().loadedWithCabRequest, isFalse);
      expect(withRequest.toJson().containsKey('loadedWithCabRequest'), isFalse);
    });

    test('updateUser never writes a request back, and clears one only by that rule', () {
      final String body = bodyOf(code(read('lib/utils/fire_store_utils.dart')), 'static Future<bool> updateUser(UserModel userModel, {bool includeOnlineStatus = false}) async {');
      final int strip = body.indexOf("data.remove('ordercabRequestData');");
      final int set = body.indexOf('await docRef.set(data, SetOptions(merge: true));');

      expect(strip, greaterThan(-1));
      expect(strip, lessThan(set), reason: 'a request from a copy must be out of the map before the set(merge)');
      expect(body, contains('CabRequestSlot.shouldClear(current: userModel.orderCabRequestData, loadedWithRequest: userModel.loadedWithCabRequest)'));
      expect(body.contains('if (userModel.orderCabRequestData == null)'), isFalse);
    });
  });

  group('a position update writes the position and nothing else', () {
    test('the coordinates and the heading, as the old save wrote them', () {
      expect(DriverLocationWrite.fields(latitude: 31.5, longitude: 74.3, heading: 90),
          <String, Object>{'location.latitude': 31.5, 'location.longitude': 74.3, 'rotation': 90});
      expect(DriverLocationWrite.fields(latitude: null, longitude: null),
          <String, Object>{'location.latitude': 0.0, 'location.longitude': 0.0});
    });

    test('the live profile decides once it has loaded; before that the profile is read', () async {
      int reads = 0;
      Future<UserModel?> readProfile() async {
        reads++;
        return UserModel()..id = 'fromRead';
      }

      final UserModel? live = await DriverLocationWrite.profileFor(UserModel()..id = 'live', readProfile);
      expect(live?.id, 'live');
      expect(reads, 0, reason: 'a GPS tick costs no read once the listener has delivered');

      final UserModel? early = await DriverLocationWrite.profileFor(UserModel(), readProfile);
      expect(early?.id, 'fromRead');
      expect(reads, 1, reason: 'the first position of a session is not skipped');
    });

    test('updateDriverLocation is one update, behind the deleted-driver guard', () {
      final String body = bodyOf(code(read('lib/utils/fire_store_utils.dart')), 'static Future<UserModel?> updateDriverLocation({');

      expect(body, contains('.update(DriverLocationWrite.fields('));
      expect(body.contains('.set('), isFalse, reason: 'a set(merge) re-creates a deleted driver and rewrites fields from a copy');
      expect(body.contains('updateUser('), isFalse);
      expect(body.indexOf('DeletedDriverGuard.isDeleted(uid)'), lessThan(body.indexOf('.update(')));
      expect(body, contains('if (onlyWhenActive && profile.isActive != true) return profile;'));
    });

    test('no dashboard saves the whole profile on a GPS tick any more', () {
      const Map<String, bool> dashboards = <String, bool>{
        'lib/controllers/cab_dashboard_controller.dart': true,
        'lib/controllers/parcel_dashboard_controller.dart': true,
        'lib/controllers/rental_dashboard_controller.dart': true,
        // The delivery dashboard always saved the position, available or not.
        'lib/controllers/dash_board_controller.dart': false,
      };
      dashboards.forEach((String path, bool onlyWhenActive) {
        final String body = bodyOf(code(read(path)), 'Future<void> updateCurrentLocation() async {');
        expect(body.contains('updateUser('), isFalse, reason: path);
        expect(body.contains('getUserProfile('), isFalse, reason: path);
        expect(body.contains('userModel.value = value'), isFalse,
            reason: '$path: a GPS tick must not replace the live profile with a read copy');
        expect('FireStoreUtils.updateDriverLocation('.allMatches(body).length, 2, reason: path);
        expect('onlyWhenActive: $onlyWhenActive,'.allMatches(body).length, 2, reason: path);
      });
    });
  });

  group('a ride request rings from the device', () {
    tearDown(AudioPlayerService.forgetRingtone);

    test('streamed until a copy exists, then played from the copy', () async {
      const String url = 'https://example.test/ringtone.mp3';
      expect(AudioPlayerService.ringtoneSource(url), isA<UrlSource>());

      int downloads = 0;
      Future<String> download(String _) async {
        downloads++;
        return '/data/ringtone.mp3';
      }

      await AudioPlayerService.prepareRingtone(url, download: download);
      final Source source = AudioPlayerService.ringtoneSource(url);
      expect(source, isA<DeviceFileSource>());
      expect((source as DeviceFileSource).path, '/data/ringtone.mp3');

      await AudioPlayerService.prepareRingtone(url, download: download);
      expect(downloads, 1, reason: 'one copy per ringtone');
      expect(AudioPlayerService.ringtoneSource('https://example.test/other.mp3'), isA<UrlSource>(),
          reason: 'a ringtone the admin changed is never played from the old copy');
    });

    test('a failed copy leaves the ringtone streamed, as it was', () async {
      const String url = 'https://example.test/ringtone.mp3';
      await AudioPlayerService.prepareRingtone(url, download: (String _) async => throw Exception('offline'));
      expect(AudioPlayerService.ringtoneSource(url), isA<UrlSource>());
    });

    test('the copy is made when the settings arrive, and the player uses it', () {
      expect(code(read('lib/utils/fire_store_utils.dart')), contains('unawaited(AudioPlayerService.prepareRingtone(Constant.orderRingtoneUrl));'));
      final String play = bodyOf(code(read('lib/services/audio_player_service.dart')), 'static Future<void> playSound(bool isPlay) async {');
      expect(play, contains('await _audioPlayer.setSource(ringtoneSource(url));'));
      expect(play.contains('UrlSource(Preferences'), isFalse);
      expect(play, contains('await _audioPlayer.setReleaseMode(ReleaseMode.loop);'));
    });
  });

  group('sending an offer does not wait for the trip count', () {
    late int counts;
    late Future<num?> Function(UserModel driver) realCounter;

    setUpAll(() => realCounter = BiddingService.tripCounter);
    tearDownAll(() => BiddingService.tripCounter = realCounter);

    setUp(() {
      counts = 0;
      BiddingService.forgetCompletedTrips();
      BiddingService.tripCounter = (UserModel driver) async {
        counts++;
        return 7;
      };
    });
    tearDown(BiddingService.forgetCompletedTrips);

    test('the count started while the request is read is the one the offer uses', () async {
      final UserModel me = UserModel()..id = 'driver1';
      BiddingService.warmCompletedTrips(me);
      BiddingService.warmCompletedTrips(me);
      expect(counts, 1, reason: 'repeated inbox snapshots start one count');

      expect(await BiddingService.completedTrips(me), 7);
      expect(counts, 1, reason: 'the tap reuses it instead of making another');
    });

    test('a stored counter of 0 no longer hides the real rides (the "0 trips" report)', () async {
      final UserModel me = UserModel()
        ..id = 'driver1'
        ..orderCompleted = 0;
      BiddingService.warmCompletedTrips(me);
      expect(await BiddingService.completedTrips(me), 7);
      expect(counts, 1, reason: 'the warmed count is reused by the tap');
    });

    test('a higher stored counter is kept as a floor', () async {
      final UserModel me = UserModel()
        ..id = 'driver1'
        ..orderCompleted = 12;
      BiddingService.warmCompletedTrips(me);
      expect(await BiddingService.completedTrips(me), 12);
      expect(counts, 1);
    });

    test('forgotten on a ride, never used for another driver, never used after a failure', () async {
      final UserModel me = UserModel()..id = 'driver1';

      BiddingService.warmCompletedTrips(me);
      BiddingService.forgetCompletedTrips();
      expect(await BiddingService.completedTrips(me), 7);
      expect(counts, 2);

      BiddingService.warmCompletedTrips(me);
      expect(await BiddingService.completedTrips(UserModel()..id = 'driver2'), 7);
      expect(counts, 4);

      BiddingService.forgetCompletedTrips();
      BiddingService.tripCounter = (UserModel driver) async {
        counts++;
        return counts == 5 ? null : 3;
      };
      BiddingService.warmCompletedTrips(me);
      expect(await BiddingService.completedTrips(me), 3);
      expect(counts, 6);
    });

    test('the inbox starts the count, and drops it while the driver is on a ride', () {
      final String body = bodyOf(code(read('lib/controllers/bidding_request_controller.dart')), 'void _onRequests(List<BiddingRequest> requests, [UserModel? profile]) {');
      expect(body, contains('BiddingService.forgetCompletedTrips();'));
      expect(body, contains('BiddingService.warmCompletedTrips(me);'));
    });
  });

  group('the buttons a driver presses on a ride', () {
    test('the request panel and the ride card cannot throw on a missing field', () {
      final String screen = code(read('lib/app/cab_screen/cab_home_screen.dart'));
      for (final String crash in <String>[
        'author!.fullName()',
        'author!.phoneNumber',
        'double.parse(controller.currentOrder.value.distance',
        'double.parse(controller.currentOrder.value.tipAmount',
        'paymentMethod!.toLowerCase()',
        'double.parse(Constant.minimumDepositToRideAccept)',
        'controller.driverModel.value.walletAmount!',
        'driver!.fullName()',
        'customer!.fullName()',
      ]) {
        expect(screen.contains(crash), isFalse, reason: crash);
      }
      expect('if (customer == null || driver == null) {'.allMatches(screen).length, 2, reason: 'both chat buttons');
    });

    test('Navigate works on the way to the pickup', () {
      // The same condition already guards the Complete Ride card, so only the
      // one that leads straight into the map redirect counts.
      final RegExp redirectOnAccepted = RegExp(
          r'Constant\.orderShipped \|\| controller\.currentOrder\.value\.status == Constant\.driverAccepted\) \{\s*Utils\.redirectMap\(');
      expect(redirectOnAccepted.hasMatch(code(read('lib/app/cab_screen/cab_home_screen.dart'))), isTrue);
      expect(redirectOnAccepted.hasMatch(code(read('lib/app/home_screen/home_screen.dart'))), isTrue);
    });

    test('Start Ride keeps the dialog up when the ride could not be started', () {
      final String body = bodyOf(code(read('lib/controllers/cab_home_controller.dart')), 'Future<void> onRideStatus() async {');
      final int failed = body.indexOf('if (!written) {');
      expect(failed, greaterThan(-1));
      expect(failed, lessThan(body.indexOf('Get.back();')));
      expect(body, contains('currentOrder.value.status = statusBefore;'));
    });

    test('the other services\' chat buttons say so instead of doing nothing', () {
      for (final String path in <String>[
        'lib/app/home_screen/home_screen.dart',
        'lib/app/parcel_screen/parcel_home_screen.dart',
        'lib/app/home_screen/deliver_order_screen.dart',
      ]) {
        final String source = code(read(path));
        expect(source, contains('if (customer == null || driver == null) {'), reason: path);
        expect(source.contains('driver!.fullName()'), isFalse, reason: path);
      }
    });

    test('a chat notification opens the chat over the driver\'s own dashboard', () {
      final String body = bodyOf(code(read('lib/utils/notification_service.dart')), 'Future<void> handleMessageClick({');
      final String chat = body.substring(body.indexOf("} else if (type == 'orderChat') {"));
      expect(chat.contains('Get.offAll('), isFalse,
          reason: 'offAll closed a cab driver\'s dashboard, and the ride request listener with it');
      expect(chat, contains('await _openOnTop('));
      expect(chat, contains('if (customer == null || driver == null) {'));
    });
  });
}
