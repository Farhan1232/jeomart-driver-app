import 'dart:io';

import 'package:driver/utils/driver_online_write.dart';
import 'package:flutter_test/flutter_test.dart';

/// Session 49 - the Available Status the driver picks in the app is the one the
/// Admin Panel shows, and nothing else in the app changes it.
///
/// The switch used to save the whole profile, and so did the launch, push-token
/// and order paths; whichever wrote last decided the status, so a save carrying
/// an older copy put a driver who had just gone online back offline. The writes
/// live behind Firebase, so their shape is pinned from source, with comment
/// lines dropped so a comment quoting old code is never mistaken for the code.
void main() {
  String read(String path) => File(path).readAsStringSync();

  String code(String source) => source.split('\n').where((String line) => !line.trimLeft().startsWith('//')).join('\n');

  String bodyOf(String source, String signature) {
    final int start = source.indexOf(signature);
    expect(start, greaterThan(-1), reason: '$signature is missing');
    final int end = source.indexOf('\n  }\n', start);
    return source.substring(start, end == -1 ? source.length : end);
  }

  /// The four dashboards that carry an Available Status switch.
  const List<String> dashboards = <String>[
    'lib/app/dash_board_screen/dash_board_screen.dart',
    'lib/app/cab_screen/cab_dashboard_screen.dart',
    'lib/app/parcel_screen/parcel_dashboard_screen.dart',
    'lib/app/rental_service/rental_dashboard_screen.dart',
  ];

  String switchBody(String path) {
    final String source = code(read(path));
    final int start = source.indexOf('onChanged: (value) async {');
    expect(start, greaterThan(-1), reason: '$path has no Available Status switch');
    final int end = source.indexOf('},', source.indexOf('setDriverOnlineStatus', start));
    return source.substring(start, end == -1 ? source.length : end);
  }

  group('the status is one field', () {
    test('a status change writes isActive and nothing else', () {
      expect(DriverOnlineWrite.fields(isOnline: true), <String, Object>{'isActive': true});
      expect(DriverOnlineWrite.fields(isOnline: false), <String, Object>{'isActive': false});
      expect(DriverOnlineWrite.fields(isOnline: true).length, 1, reason: 'the Admin Panel updates this one field, and so does the app');
    });

    test('the field is the one the Admin Panel writes', () {
      expect(DriverOnlineWrite.field, 'isActive');
    });

    test('setDriverOnlineStatus is one update, behind the deleted-driver guard', () {
      final String body = bodyOf(code(read('lib/utils/fire_store_utils.dart')), 'static Future<bool> setDriverOnlineStatus(bool isOnline) async {');

      expect(body, contains('.update(DriverOnlineWrite.fields(isOnline: isOnline))'));
      expect(body.contains('.set('), isFalse, reason: 'a set(merge) would write fields from a copy again');
      expect(body.contains('updateUser('), isFalse);
      expect(body.indexOf('DeletedDriverGuard.isDeleted(uid)'), lessThan(body.indexOf('.update(')));
      expect(body, contains('return false;'), reason: 'the switch is told when the change did not reach the server');
    });
  });

  group('a profile save never carries a status', () {
    test('updateUser drops isActive unless the caller is creating the account', () {
      final String body = bodyOf(code(read('lib/utils/fire_store_utils.dart')), 'static Future<bool> updateUser(UserModel userModel, {bool includeOnlineStatus = false}) async {');
      final int strip = body.indexOf('data.remove(DriverOnlineWrite.field);');
      final int set = body.indexOf('await docRef.set(data, SetOptions(merge: true));');

      expect(strip, greaterThan(-1), reason: 'the status must be taken out of every ordinary profile save');
      expect(strip, lessThan(set), reason: 'and taken out before the write, not after it');
      expect(body, contains('if (!includeOnlineStatus) {'));
      expect(body, contains('userModel.isActive = Constant.userModel?.isActive ?? userModel.isActive;'),
          reason: 'the in-memory copy must not be rolled back either');
    });

    test('only the two account-creation paths write a starting status', () {
      final Map<String, int> creators = <String, int>{
        'lib/controllers/signup_controller.dart': 2,
        'lib/controllers/driver_create_controller.dart': 1,
      };
      creators.forEach((String path, int expected) {
        expect('includeOnlineStatus: true'.allMatches(code(read(path))).length, expected, reason: path);
      });

      // Every other save in the app leaves the status alone.
      final Directory lib = Directory('lib');
      for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (creators.containsKey(entity.path)) continue;
        expect(code(read(entity.path)).contains('includeOnlineStatus: true'), isFalse, reason: entity.path);
      }
    });
  });

  group('every Available Status switch behaves the same', () {
    test('each one writes the single field and no longer saves the profile', () {
      for (final String path in dashboards) {
        final String body = switchBody(path);
        expect(body, contains('FireStoreUtils.setDriverOnlineStatus(value)'), reason: path);
        expect(body.contains('updateUser('), isFalse, reason: '$path: the switch must not save the whole profile');
        expect(body.contains('Constant.userModel!'), isFalse, reason: '$path: a null profile used to throw before the save ran');
      }
    });

    test('each one keeps the verification rule and starts location only when going available', () {
      for (final String path in dashboards) {
        final String body = switchBody(path);
        expect(body, contains('isDocumentVerify != true'), reason: path);
        expect(body, contains('Document verification is pending'), reason: path);
        expect(body, contains('if (value == true) {'), reason: path);
        expect(body, contains('controller.updateCurrentLocation();'), reason: path);
      }
    });

    test('each one tells the driver when the change did not save, and only then', () {
      for (final String path in dashboards) {
        final String body = switchBody(path);
        expect(body, contains('final bool saved = await FireStoreUtils.setDriverOnlineStatus(value);'), reason: path);
        expect(body, contains('if (saved) {'), reason: path);
        expect(body, contains('controller.userModel.value.isActive = value;'), reason: path);
        expect(body, contains('controller.userModel.refresh();'), reason: path);
        expect(body, contains('Status not changed. Please check your internet connection and try again.'), reason: path);
      }
    });
  });
}
