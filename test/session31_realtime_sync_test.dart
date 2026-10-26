import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Session 31 - "Accept takes twenty to thirty seconds, and sometimes the
/// driver app updates after more than a minute."
///
/// The driver half of that report. Four things were in the way, and each test
/// here names the one it stops coming back:
///
///  1. the ride listener was thrown away and rebuilt on every write to the
///     driver's own user document, which happens on every location update;
///  2. a call to a public routing server sat in front of the ride-request
///     alert, the jump to the home section and every screen refresh;
///  3. the acceptance wrote the driver's profile - two round trips - *before*
///     the ride the customer is watching, and then held the spinner open for a
///     push nobody was waiting for;
///  4. a won bid reached this app only through a listener opened at the moment
///     the offer was submitted, so leaving the section or restarting the app
///     left the dispatcher's once-a-minute sweep as the only way to find out.
void main() {
  String read(String path) {
    final File file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing - this test is stale');
    return file.readAsStringSync();
  }

  /// The body of `name`, from its signature to the closing brace at the same
  /// indentation. Good enough for these files, which are all two-space
  /// indented members of one class.
  String methodBody(String source, String signature) {
    final int start = source.indexOf(signature);
    expect(start, greaterThan(-1), reason: 'cannot find `$signature` - this test is stale');
    final int end = source.indexOf('\n  }', start);
    expect(end, greaterThan(start), reason: 'cannot find the end of `$signature`');
    return source.substring(start, end);
  }

  /// The same, with the comment lines taken out - several of these methods
  /// describe in prose the very call they no longer make.
  String codeOnly(String body) =>
      body.split('\n').where((String line) => !line.trimLeft().startsWith('//')).join('\n');

  group('the ride listener survives an unrelated write', () {
    test('getCurrentOrder only rebuilds when the ride has actually changed', () {
      final String source = read('lib/controllers/cab_home_controller.dart');
      final String body = methodBody(source, 'Future<void> getCurrentOrder() async {');

      // The guard itself. Without it, every snapshot of the driver's own
      // document - one per location update - cancelled a listener that was
      // already delivering and waited on a fresh round trip for its
      // replacement's first snapshot.
      expect(body, contains('if (id != null && id == _watchedRideId && _orderDocSub != null) return;'),
          reason: 'a re-subscription must be skipped when it would follow the same ride');
      expect(body, contains('_watchedRideId = id;'));
    });

    test('the driver-document listener no longer fetches the route a second time', () {
      final String source = read('lib/controllers/cab_home_controller.dart');
      final String body = codeOnly(methodBody(source, 'Future<void> _onDriverSnapshot('));

      // The ride listener calls changeData() on every snapshot of its own. The
      // unconditional `await changeData()` that used to be here therefore only
      // ever fetched the route again - on every location update - and held the
      // callback open while it did.
      expect(body.contains('await changeData()'), isFalse,
          reason: 'the driver-document listener must not await the route fetch');
      expect(body, contains('unawaited(_refreshRoute())'));
    });
  });

  group('nothing on screen waits for a routing server', () {
    test('changeData rings, announces and draws markers without a single await', () {
      final String source = read('lib/controllers/cab_home_controller.dart');
      final String body = codeOnly(methodBody(source, 'Future<void> changeData() async {'));

      expect(body.contains('await '), isFalse,
          reason: 'changeData is on the path a new ride request takes to the screen; '
              'an await in it is a request the driver sees late');
      expect(body, contains('_showRequestToDriver();'));
      expect(body, contains('unawaited(AudioPlayerService.playSound(isRequest));'));
      expect(body, contains('unawaited(_refreshRoute());'));
    });

    test('the alert is raised before the route is asked for, not after', () {
      final String source = read('lib/controllers/cab_home_controller.dart');
      final String body = methodBody(source, 'Future<void> changeData() async {');

      expect(body.indexOf('_showRequestToDriver();'), lessThan(body.indexOf('unawaited(_refreshRoute());')),
          reason: 'the driver must be told about the ride first and shown the line afterwards');
    });

    test('a route is only fetched when it would be a different route', () {
      final String source = read('lib/controllers/cab_home_controller.dart');
      final String body = methodBody(source, 'Future<void> _refreshRoute({bool force = false}) async {');

      expect(body, contains('if (!force && key == _routeKey && _routeAt != null && now.difference(_routeAt!) < _routeMinInterval)'),
          reason: 'the same route must not be re-fetched on every snapshot');
      // Which ride, which leg, roughly where the driver is.
      expect(source, contains("return '\${currentOrder.value.id}|\${currentOrder.value.status}|\$at';"));
    });
  });

  group('accepting a ride writes the ride first', () {
    test('the profile write goes out alongside the ride, not in front of it', () {
      final String source = read('lib/controllers/cab_home_controller.dart');
      final String body = methodBody(source, 'Future<void> acceptOrder() async {');

      final int profile = body.indexOf('final Future<bool> profileWrite = FireStoreUtils.updateUser(driverModel.value);');
      final int ride = body.indexOf('final bool written = await FireStoreUtils.setCabOrder(order);');
      expect(profile, greaterThan(-1), reason: 'the profile write must be started, not awaited');
      expect(ride, greaterThan(profile), reason: 'both writes must be in flight together');

      // The ride document is the one the customer's screen is listening to.
      final int loaderClosed = body.indexOf('ShowToastDialog.closeLoader();');
      expect(loaderClosed, greaterThan(ride), reason: 'the spinner ends when the ride lands');
    });

    test('the push notification no longer holds the spinner open', () {
      final String source = read('lib/controllers/cab_home_controller.dart');
      final String body = methodBody(source, 'Future<void> acceptOrder() async {');

      expect(body.contains('await SendNotification.sendFcmMessage'), isFalse,
          reason: 'an FCM send is an OAuth exchange plus a round trip; nothing on screen waits for it');
      expect(body, contains('unawaited(SendNotification.sendFcmMessage('));
    });

    test('rejecting closes the sheet without waiting for two writes', () {
      final String source = read('lib/controllers/cab_home_controller.dart');
      final String body = methodBody(source, 'Future<void> rejectOrder() async {');

      expect(body.contains('await FireStoreUtils.updateUser'), isFalse);
      expect(body, contains('unawaited(FireStoreUtils.setCabOrder(currentOrder.value));'));
      expect(body, contains('unawaited(FireStoreUtils.updateUser(driverModel.value));'));

      // The ride carries `rejectedByDrivers`, which is what lets the
      // dispatcher offer it straight on to the next driver.
      expect(body.indexOf('unawaited(FireStoreUtils.setCabOrder(currentOrder.value));'),
          lessThan(body.indexOf('Get.back();')));
    });
  });

  group('a won offer reaches this driver without the dispatcher', () {
    test('there is a live query for the rides this driver has been awarded', () {
      final String source = read('lib/services/bidding_service.dart');

      expect(source, contains('static Stream<List<String>> wonRequestsStream({int limit = 5})'));
      // Deliberately the same field combination as openRequestsStream, with a
      // different status value: one composite index serves both, so this needs
      // nothing deployed before it works.
      final String won = methodBody(source, 'static Stream<List<String>> wonRequestsStream({int limit = 5})');
      expect(won, contains('.where(RideBiddingFields.eligibleDriverIds, arrayContains: uid)'));
      expect(won, contains('.where(RideBiddingFields.status, isEqualTo: RideBiddingStatus.accepted)'));
      expect(won, contains(".orderBy('createdAt', descending: true)"));

      final String open = methodBody(source, 'static Stream<List<BiddingRequest>> openRequestsStream({int limit = 20})');
      expect(open, contains('.where(RideBiddingFields.eligibleDriverIds, arrayContains: uid)'));
      expect(open, contains(".orderBy('createdAt', descending: true)"));
    });

    test('the inbox opens that listener when it starts, not when an offer is sent', () {
      final String source = read('lib/controllers/bidding_request_controller.dart');
      final String start = methodBody(source, 'void start() {');

      expect(start, contains('_watchWins();'),
          reason: 'the win listener must exist for the whole life of the controller');
      expect(source, contains('_wonSub = BiddingService.wonRequestsStream().listen('));
      expect(source, contains('_wonSub?.cancel();'), reason: 'and be cancelled with everything else');
    });

    test('an offer still on the table is followed for its outcome', () {
      final String source = read('lib/controllers/bidding_request_controller.dart');

      // _watchRide used to be reached only from _submit, so an offer made
      // before the section was last left was no longer being followed.
      expect(source, contains('if (bid.isLive) _watchRide(rideId);'));
    });

    test('a ride is only claimed once, however many listeners report it', () {
      final String source = read('lib/controllers/bidding_request_controller.dart');

      expect(source, contains('if (rideId.isEmpty || _claimed.contains(rideId)) continue;'));
      expect(source, contains('_claimed.add(rideId);'));
    });
  });

  group('a push costs one token exchange, not one per notification', () {
    test('the access token is cached until it is nearly expired', () {
      final String source = read('lib/constant/send_notification.dart');

      expect(source, contains('static String? _accessToken;'));
      expect(source, contains('static DateTime? _accessTokenExpiry;'));
      expect(source, contains('if (cached != null && expiry != null && DateTime.now().isBefore(expiry)) {'));
      expect(source, contains('_accessTokenExpiry = token.expiry.toLocal().subtract(const Duration(minutes: 1));'));
    });

    test('clearing the cache clears the token too', () {
      final String source = read('lib/constant/send_notification.dart');
      final String body = methodBody(source, 'static void clearServiceAccountCache() {');

      expect(body, contains('_serviceAccount = null;'));
      expect(body, contains('_accessToken = null;'));
      expect(body, contains('_accessTokenExpiry = null;'));
    });
  });

  group('an open booking follows its own ride', () {
    test('the details screen listens instead of drawing what it was handed', () {
      final String source = read('lib/controllers/cab_order_details_controller.dart');

      expect(source, contains('_orderSub = FireStoreUtils.fireStore.collection(CollectionName.ridesBooking).doc(id).snapshots().listen('));
      expect(source, contains('_orderSub?.cancel();'), reason: 'and lets go of it with the screen');
    });
  });
}
