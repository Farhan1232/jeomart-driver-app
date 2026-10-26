import 'dart:async';
import 'dart:io';

import 'package:driver/utils/deleted_driver_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Session 38 - "a driver deleted from the Admin Panel ... can still appear in
/// Live Tracking and can still receive orders", and "the app cannot recreate
/// the deleted driver record".
///
/// `FireStoreUtils.updateUser` saves the whole profile with
/// `set(merge: true)`, which re-creates a deleted `users` document. An app left
/// open after the admin deleted the driver kept doing that from its location
/// stream and online switch. The guard follows the driver's
/// `deleted_drivers/{uid}` record and stops those saves.
///
/// The guard tests are behavioural. The source checks are the house pattern for
/// code behind Firebase; set SESSION38_SOURCE_ROOT to another copy of the app
/// (the pre-change backup) to see them fail there.
void main() {
  final String root = Platform.environment['SESSION38_SOURCE_ROOT'] ?? '.';

  String read(String path) => File('$root/$path').readAsStringSync();

  group('DeletedDriverGuard', () {
    late StreamController<bool> record;
    late int opened;
    late List<String> ended;

    Stream<bool> recordExists(String uid) {
      opened++;
      return record.stream;
    }

    void follow(String uid) => DeletedDriverGuard.follow(uid, recordExists: recordExists, onDeleted: ended.add);

    setUp(() async {
      await DeletedDriverGuard.reset();
      record = StreamController<bool>.broadcast();
      opened = 0;
      ended = <String>[];
    });

    tearDown(() async {
      await DeletedDriverGuard.reset();
      await record.close();
    });

    test('a driver with no deletion record saves as before', () async {
      follow('d1');
      record.add(false);
      await pumpEventQueue();
      expect(DeletedDriverGuard.isDeleted('d1'), isFalse);
      expect(ended, isEmpty);
    });

    test('before the record has been read, saves are not held up (fails open)', () {
      follow('d1');
      expect(DeletedDriverGuard.isDeleted('d1'), isFalse);
    });

    test('once the admin deletes the driver, their saves are refused and the session ends once', () async {
      follow('d1');
      record.add(false);
      record.add(true);
      await pumpEventQueue();
      expect(DeletedDriverGuard.isDeleted('d1'), isTrue);
      expect(ended, <String>['d1']);

      record.add(true); // another snapshot of the same record
      await pumpEventQueue();
      expect(ended, <String>['d1'], reason: 'the session is ended once, not per snapshot');
    });

    test('following the same driver before every save opens one listener, not one per save', () {
      for (int i = 0; i < 50; i++) {
        follow('d1');
      }
      expect(opened, 1);
    });

    test('a driver restored by the admin (record removed) can save again', () async {
      follow('d1');
      record.add(true);
      await pumpEventQueue();
      record.add(false);
      await pumpEventQueue();
      expect(DeletedDriverGuard.isDeleted('d1'), isFalse);
    });

    test('a record that cannot be read does not block the driver', () async {
      follow('d1');
      record.addError(StateError('offline'));
      await pumpEventQueue();
      expect(DeletedDriverGuard.isDeleted('d1'), isFalse);
      expect(ended, isEmpty);
    });

    test('a deleted driver stays blocked after someone else signs in on the same phone', () async {
      follow('d1');
      record.add(true);
      await pumpEventQueue();

      final StreamController<bool> other = StreamController<bool>.broadcast();
      DeletedDriverGuard.follow('d2', recordExists: (_) => other.stream, onDeleted: ended.add);
      other.add(false);
      await pumpEventQueue();

      expect(DeletedDriverGuard.isDeleted('d1'), isTrue, reason: 'a stream still holding d1 must not write d1 back');
      expect(DeletedDriverGuard.isDeleted('d2'), isFalse);
      await other.close();
    });

    test('nobody is blocked without a uid', () {
      expect(DeletedDriverGuard.isDeleted(null), isFalse);
      follow('');
      expect(opened, 0);
    });

    test('the record collection is the one the Admin Panel writes', () {
      expect(DeletedDriverGuard.collection, 'deleted_drivers');
      final File panel = File(
        '$root/../../emaart/eMart_V6.8_Source_Code/Landing Page - Admin Panel - Store Panel - Website Panel/Admin Panel/public/js/driver-deletion.js',
      );
      if (panel.existsSync()) {
        expect(panel.readAsStringSync(), contains("var TOMBSTONES = 'deleted_drivers';"));
      }
    });
  });

  group('FireStoreUtils.updateUser consults the guard (source)', () {
    late String utils;
    late String updateUser;

    setUpAll(() {
      utils = read('lib/utils/fire_store_utils.dart');
      final int start = utils.indexOf('static Future<bool> updateUser(UserModel userModel, {bool includeOnlineStatus = false}) async {');
      expect(start, isNot(-1), reason: 'updateUser must still exist');
      updateUser = utils.substring(start, utils.indexOf('static Future<List<OnBoardingModel>> getOnBoardingList', start));
    });

    test('a deleted driver\'s profile is refused BEFORE the set(merge) that would re-create it', () {
      final int guard = updateUser.indexOf('DeletedDriverGuard.isDeleted(userModel.id)');
      final int write = updateUser.indexOf('docRef.set(data, SetOptions(merge: true))');
      expect(guard, isNot(-1));
      expect(write, isNot(-1));
      expect(guard, lessThan(write));
      expect(updateUser.substring(guard, write), contains('return false;'));
    });

    test('the signed-in driver\'s own record is followed, read without forcing a signed-in user', () {
      expect(updateUser, contains('FirebaseAuth.instance.currentUser?.uid'));
      expect(updateUser, contains('DeletedDriverGuard.follow('));
      expect(utils, contains('.collection(DeletedDriverGuard.collection)'));
      expect(utils, contains('.snapshots()'));
    });

    test('a deleted driver is signed out and sent to the login screen', () {
      final int start = utils.indexOf('static void _endDeletedDriverSession(String uid)');
      expect(start, isNot(-1));
      final String body = utils.substring(start, utils.indexOf('\n  }\n', start));
      expect(body, contains('FirebaseAuth.instance.signOut()'));
      expect(body, contains('Get.offAll(const LoginScreen())'));
      expect(body, contains('UserCache.invalidate(uid)'));
    });

    test('the rest of the save is unchanged: merge write, legacy mirror, wallet untouched', () {
      expect(updateUser, contains('removeNulls(userModel.toJson())'));
      expect(updateUser, contains("legacyFields['serviceType'] = savedServiceTypes.first;"));
      expect(updateUser, contains('await docRef.update(legacyFields);'));
      expect(updateUser, isNot(contains('wallet_amount')));
    });
  });
}
