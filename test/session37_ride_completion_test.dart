import 'dart:io';

import 'package:driver/utils/active_ride_selection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Session 37 - "the driver stays stuck after finishing a ride ... if the app
/// is closed and opened again the state becomes correct."
///
/// Three things kept a finished ride alive on the driver's side:
///
///  1. the cab home screen stopped drawing an ended ride but kept following it,
///     so when the ride's id was written back onto the driver's document -
///     which a write built from a profile read before the ride ended does -
///     the "already following this ride" guard ignored it for good. The driver
///     looked free, the document said busy, no dispatcher offered them
///     anything, and a new request on the same document was never shown;
///  2. nothing stopped a second tap on Complete Ride from running the whole
///     completion again once the loader's 30 s watchdog had taken it down;
///  3. the Bid section decided "on a ride" once per inbox snapshot and never
///     looked at the driver's profile again, and a won ride that had already
///     ended could still be handed back to the ride flow.
///
/// The selection tests are behavioural. The source checks are the house
/// pattern for code that lives behind Firebase listeners; set
/// SESSION37_SOURCE_ROOT to another copy of the app (the pre-change backup) to
/// see them fail there.
void main() {
  final String root = Platform.environment['SESSION37_SOURCE_ROOT'] ?? '.';

  String read(String path) {
    final File file = File('$root/$path');
    expect(file.existsSync(), isTrue, reason: '$path is missing - this test is stale');
    return file.readAsStringSync();
  }

  String methodBody(String source, String signature) {
    final int start = source.indexOf(signature);
    expect(start, greaterThan(-1), reason: 'cannot find `$signature`');
    final int end = source.indexOf('\n  }', start);
    expect(end, greaterThan(start), reason: 'cannot find the end of `$signature`');
    return source.substring(start, end);
  }

  String codeOnly(String body) =>
      body.split('\n').where((String line) => !line.trimLeft().startsWith('//') && !line.trimLeft().startsWith('///')).join('\n');

  /// The rule `getCurrentOrder` used before this session, verbatim.
  String? legacySelect(List<dynamic>? inProgress, String? pendingRequestId) {
    if (inProgress != null && inProgress.isNotEmpty) return inProgress.first.toString();
    if (pendingRequestId != null && pendingRequestId.isNotEmpty) return pendingRequestId;
    return null;
  }

  group('which ride the cab home screen follows', () {
    test('the ride in progress', () {
      final ActiveRideSelection s = ActiveRideSelection.select(inProgress: <dynamic>['r1'], pendingRequestId: null);
      expect(s.rideId, 'r1');
      expect(s.endedStillListed, isEmpty);
    });

    test('with no ride in progress, the request waiting on the driver', () {
      final ActiveRideSelection s = ActiveRideSelection.select(inProgress: <dynamic>[], pendingRequestId: 'req');
      expect(s.rideId, 'req');
    });

    test('nothing, when there is nothing', () {
      expect(ActiveRideSelection.select(inProgress: null, pendingRequestId: null).rideId, isNull);
      expect(ActiveRideSelection.select(inProgress: <dynamic>[null, ''], pendingRequestId: '').rideId, isNull);
    });

    test('a ride the screen saw end is not followed when it is written back', () {
      final ActiveRideSelection s = ActiveRideSelection.select(
        inProgress: <dynamic>['done'],
        pendingRequestId: null,
        endedRideIds: <String>{'done'},
      );
      expect(s.rideId, isNull);
      expect(s.endedStillListed, <String>['done'], reason: 'the caller takes it back off the document');
      expect(legacySelect(<dynamic>['done'], null), 'done', reason: 'the old rule followed it again - the stuck state');
    });

    test('a new request reaches the screen while an ended ride is still listed', () {
      final ActiveRideSelection s = ActiveRideSelection.select(
        inProgress: <dynamic>['done'],
        pendingRequestId: 'new-request',
        endedRideIds: <String>{'done'},
      );
      expect(s.rideId, 'new-request');
      expect(s.endedStillListed, <String>['done']);
      expect(legacySelect(<dynamic>['done'], 'new-request'), 'done',
          reason: 'the old rule never showed the request, so the dispatcher took it back as unanswered');
    });

    test('a leftover request for a ride already seen ending is not followed', () {
      final ActiveRideSelection s = ActiveRideSelection.select(
        inProgress: <dynamic>[],
        pendingRequestId: 'done',
        endedRideIds: <String>{'done'},
      );
      expect(s.rideId, isNull);
      expect(s.endedStillListed, isEmpty, reason: 'only in-progress entries are taken off the document');
    });

    test('a live ride listed behind an ended one is followed', () {
      final ActiveRideSelection s = ActiveRideSelection.select(
        inProgress: <dynamic>['done', 'live'],
        pendingRequestId: null,
        endedRideIds: <String>{'done'},
      );
      expect(s.rideId, 'live');
      expect(s.endedStillListed, <String>['done']);
    });

    test('completed, cancelled and rejected rides have ended; nothing else has', () {
      for (final String status in <String>['Order Completed', 'Order Cancelled', 'Order Rejected']) {
        expect(ActiveRideSelection.hasEnded(status), isTrue, reason: status);
      }
      for (final String? status in <String?>[null, '', 'Order Placed', 'Order Accepted', 'Driver Pending', 'Driver Accepted', 'Driver Rejected', 'Order Shipped', 'In Transit']) {
        expect(ActiveRideSelection.hasEnded(status), isFalse, reason: '$status');
      }
    });
  });

  group('the cab home screen lets go of an ended ride', () {
    test('both ended-ride branches of the ride listener forget the ride', () {
      final String body = codeOnly(methodBody(read('lib/controllers/cab_home_controller.dart'), 'Future<void> _handleOrderDoc('));
      expect('_forgetEndedRide(id);'.allMatches(body).length, 2);
    });

    test('so does the query fallback', () {
      final String body = codeOnly(methodBody(read('lib/controllers/cab_home_controller.dart'), 'Future<void> _handleOrderQuery('));
      expect(body, contains('_forgetEndedRide(id);'));
    });

    test('forgetting a ride closes its listener and clears the "already following" guard', () {
      final String body = codeOnly(methodBody(read('lib/controllers/cab_home_controller.dart'), 'void _forgetEndedRide(String id) {'));
      expect(body, contains('_endedRideIds.add(id);'));
      expect(body, contains('_watchedRideId = null;'));
      expect(body, contains('_orderDocSub = null;'));
      expect(body, contains('doc?.cancel()'));
    });

    test('getCurrentOrder chooses through ActiveRideSelection and takes ended rides back off', () {
      final String body = codeOnly(methodBody(read('lib/controllers/cab_home_controller.dart'), 'Future<void> getCurrentOrder() async {'));
      expect(body, contains('ActiveRideSelection.select('));
      expect(body, contains('endedRideIds: _endedRideIds'));
      expect(body, contains('_dropEndedRides(selection.endedStillListed)'));
      expect(body.contains('inProgress.first'), isFalse, reason: 'the unconditional first in-progress ride was the defect');
      // Session 31's guard stays: it is right once ended rides can no longer reach it.
      expect(body, contains('if (id != null && id == _watchedRideId && _orderDocSub != null) return;'));
    });
  });

  group('completing a ride', () {
    test('a second tap cannot start the completion again', () {
      final String body = codeOnly(methodBody(read('lib/controllers/cab_home_controller.dart'), 'Future<void> completeRide() async {'));
      final int guard = body.indexOf('if (_completingRideId == rideId)');
      expect(guard, greaterThan(-1));
      expect(guard, lessThan(body.indexOf('await ')), reason: 'the guard must run before anything is awaited');
      expect(body, contains('_completingRideId = rideId;'));
      expect(body, contains('finally'));
      expect(body, contains('_completingRideId = null;'));
    });

    test('money is still booked first, once, and in the same order', () {
      final String body = codeOnly(methodBody(read('lib/controllers/cab_home_controller.dart'), 'Future<void> completeRide() async {'));
      const List<String> order = <String>[
        'await updateCabWalletAmount(',
        'FireStoreUtils.getFirestOrderOrNOtCabService(',
        'FireStoreUtils.updateReferralAmountCabService(',
        'FireStoreUtils.setCabOrder(',
        '_endRideOnScreen(rideId);',
        'await FireStoreUtils.updateUser(',
      ];
      int previous = -1;
      for (final String step in order) {
        final int at = body.indexOf(step);
        expect(at, greaterThan(previous), reason: '`$step` is missing or out of order');
        previous = at;
      }
      expect('updateCabWalletAmount('.allMatches(body).length, 1);
      expect('updateReferralAmountCabService('.allMatches(body).length, 1);
    });

    test('the screen lets go of the ride the moment its completion is written', () {
      final String body = codeOnly(methodBody(read('lib/controllers/cab_home_controller.dart'), 'void _endRideOnScreen(String id) {'));
      expect(body, contains('_forgetEndedRide(id);'));
      expect(body, contains('currentOrder.value = CabOrderModel();'));
      expect(body, contains('update();'));
    });
  });

  group('the Bid section follows the driver', () {
    test('"on a ride" is re-applied when the driver document changes', () {
      final String source = read('lib/controllers/bidding_request_controller.dart');
      expect(codeOnly(methodBody(source, 'void start() {')), contains('_watchProfile();'));
      final String watch = codeOnly(methodBody(source, 'void _watchProfile() {'));
      expect(watch, contains('ever<UserModel>(Get.find<CabDashBoardController>().userModel'));
      expect(watch, contains('_onRequests(requests, me);'));
      expect(codeOnly(methodBody(source, 'void _onRequests(')), contains('profile ?? Constant.userModel'));
      expect(codeOnly(methodBody(source, 'void _stopAll() {')), contains('_profileWorker?.dispose();'));
    });

    test('a won ride that has already ended is never handed to the ride flow', () {
      final String controller = codeOnly(methodBody(read('lib/controllers/bidding_request_controller.dart'), 'Future<void> _onRideOutcome('));
      expect(controller, contains('!ActiveRideSelection.hasEnded('));
      final String service = codeOnly(methodBody(read('lib/services/bidding_service.dart'), 'static Stream<List<String>> wonRequestsStream('));
      expect(service, contains('!ActiveRideSelection.hasEnded('));
    });
  });
}
