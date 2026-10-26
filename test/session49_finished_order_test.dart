import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/utils/finished_order.dart';
import 'package:flutter_test/flutter_test.dart';

/// Session 49 - a delivered or cancelled order no longer keeps a delivery
/// driver "busy" for good.
///
/// Live case: order 025c2087 was "Order Completed" but still in the driver's
/// `inProgressOrderID`; with "one order at a time" on, the dispatcher skipped
/// that driver for every order after it.
void main() {
  String read(String path) => File(path).readAsStringSync();

  String code(String source) => source.split('\n').where((String line) => !line.trimLeft().startsWith('//')).join('\n');

  String bodyOf(String source, String signature) {
    final int start = source.indexOf(signature);
    expect(start, greaterThan(-1), reason: '$signature is missing');
    final int end = source.indexOf('\n  }\n', start);
    return source.substring(start, end == -1 ? source.length : end);
  }

  group('when an order is over', () {
    test('delivered - taken off the lists', () {
      expect(FinishedOrder.isFinished(fromCache: false, found: true, status: Constant.orderCompleted), isTrue);
    });

    test('cancelled, rejected or gone - the Home query no longer finds it - taken off the lists', () {
      expect(FinishedOrder.isFinished(fromCache: false, found: false), isTrue);
    });

    test('every order still under way stays exactly where it is', () {
      for (final String status in <String>[
        Constant.orderPlaced,
        Constant.orderAccepted,
        Constant.driverPending,
        Constant.driverAccepted,
        Constant.orderShipped,
        Constant.orderInTransit,
      ]) {
        expect(FinishedOrder.isFinished(fromCache: false, found: true, status: status), isFalse, reason: status);
      }
    });

    test('nothing is decided from the device cache - a not-yet-downloaded live order looks like a missing one there', () {
      expect(FinishedOrder.isFinished(fromCache: true, found: false), isFalse);
      expect(FinishedOrder.isFinished(fromCache: true, found: true, status: Constant.orderCompleted), isFalse);
    });

    test('the write removes that one id from the two lists, and nothing else', () {
      final Map<String, Object> fields = FinishedOrder.releaseFields('order1');
      expect(fields.keys.toSet(), <String>{'inProgressOrderID', 'orderRequestData'});
      expect(fields['inProgressOrderID'], FieldValue.arrayRemove(<String>['order1']));
      expect(fields['orderRequestData'], FieldValue.arrayRemove(<String>['order1']));
    });
  });

  group('where it happens', () {
    test('releaseDriverOrder is one update on the driver\'s own document, behind the deleted-driver guard', () {
      final String body = bodyOf(code(read('lib/utils/fire_store_utils.dart')), 'static Future<bool> releaseDriverOrder(String orderId) async {');
      expect(body, contains('.update(FinishedOrder.releaseFields(orderId))'));
      expect(body.contains('.set('), isFalse, reason: 'no copy of the profile is written');
      expect(body.contains('updateUser('), isFalse);
      expect(body.indexOf('DeletedDriverGuard.isDeleted(uid)'), lessThan(body.indexOf('.update(')));
    });

    test('the delivery Home screen releases a finished order from the order it follows', () {
      final String home = code(read('lib/controllers/home_controller.dart'));
      final String listener = bodyOf(home, 'void _listenToOrder(String orderId, {bool checkInRequestData = false}) {');
      expect(listener, contains('fromCache: event.metadata.isFromCache,'));
      expect(listener, contains('found: event.docs.isNotEmpty,'));
      expect(listener, contains('await _releaseFinishedOrder(orderId, found: event.docs.isNotEmpty);'));
      expect(listener.indexOf('await _releaseFinishedOrder(orderId, found: event.docs.isNotEmpty);'), lessThan(listener.indexOf('await _handleOrderNotFound();')),
          reason: 'released before the card is cleared, as before');

      final String release = bodyOf(home, 'Future<void> _releaseFinishedOrder(String orderId, {required bool found}) async {');
      expect(release, contains('if (!held) return;'), reason: 'no write for an order the driver does not hold');
      expect(release.indexOf('driver.inProgressOrderID?.remove(orderId);'), lessThan(release.indexOf('FireStoreUtils.releaseDriverOrder(orderId)')),
          reason: 'the local copy is updated first, so a save in between cannot put the id back');
    });

    test('a cab, parcel or rental order the same driver holds is never released by the delivery screen', () {
      expect(FinishedOrder.otherServiceCollections, <String>['rides', 'parcel_orders', 'rental_orders']);

      final String home = code(read('lib/controllers/home_controller.dart'));
      final String release = bodyOf(home, 'Future<void> _releaseFinishedOrder(String orderId, {required bool found}) async {');
      expect(release, contains('if (!found && await _isOtherServiceOrder(orderId)) return;'));
      expect(release.indexOf('_isOtherServiceOrder(orderId)'), lessThan(release.indexOf('driver.inProgressOrderID?.remove(orderId);')),
          reason: 'checked before anything is removed');

      final String check = bodyOf(home, 'Future<bool> _isOtherServiceOrder(String orderId) async {');
      expect(check, contains('FinishedOrder.otherServiceCollections'));
      expect(check, contains('Source.server'), reason: 'never decided from the device cache');
      expect(check, contains('return true;'), reason: 'an unanswered check keeps the order');
    });
  });
}
