import 'dart:io';

import 'package:driver/constant/constant.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/utils/driver_verification_gate.dart';
import 'package:flutter_test/flutter_test.dart';

String sourceOf(String path) {
  final String raw = File(path).readAsStringSync();
  final String withoutBlocks = raw.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return withoutBlocks
      .split('\n')
      .map((String line) => line.trimLeft().startsWith('//') ? '' : line)
      .join('\n');
}

/// A driver exactly as `UserModel.fromJson` builds one, so the defaults that
/// matter (`isDocumentVerify ?? false`, `vendorID ?? ''`, and `isAutoVerify`
/// with **no** default) are the real ones.
UserModel driverFrom(Map<String, dynamic> json) => UserModel.fromJson(<String, dynamic>{
      'id': 'd1',
      'role': 'driver',
      ...json,
    });

void main() {
  setUp(() {
    // Restored per test; these are the live values unless a test says otherwise.
    Constant.isDriverVerification = false;
    Constant.isOwnerVerification = false;
  });

  group('the driver home map is not hidden by a stale signup flag', () {
    // This is the shape 23 of the 40 live driver accounts are in: created while
    // document verification was switched on, so `isAutoVerify` was frozen to
    // false, and never touched again after the admin switched it off.
    final Map<String, dynamic> staleDriver = <String, dynamic>{
      'isDocumentVerify': false,
      'isAutoVerify': false,
    };

    test('a driver with the stale flag sees the map once verification is off', () {
      Constant.isDriverVerification = false;
      expect(
        driverAwaitsDocumentVerification(driverFrom(staleDriver)),
        isFalse,
        reason: 'the admin has verification switched off; nothing should be gated',
      );
    });

    test('and is still gated when the admin actually requires verification', () {
      Constant.isDriverVerification = true;
      expect(
        driverAwaitsDocumentVerification(driverFrom(staleDriver)),
        isTrue,
        reason: 'turning verification on must behave exactly as it did before',
      );
    });

    test('an owner is judged by the owner switch, not the driver one', () {
      Constant.isDriverVerification = true;
      Constant.isOwnerVerification = false;
      final UserModel owner = driverFrom(<String, dynamic>{
        ...staleDriver,
        'isOwner': true,
      });
      expect(driverAwaitsDocumentVerification(owner), isFalse);

      Constant.isOwnerVerification = true;
      expect(driverAwaitsDocumentVerification(owner), isTrue);
    });

    test('a verified driver is never gated, whatever the switch says', () {
      Constant.isDriverVerification = true;
      expect(
        driverAwaitsDocumentVerification(
            driverFrom(<String, dynamic>{'isDocumentVerify': true, 'isAutoVerify': false})),
        isFalse,
      );
      expect(
        driverAwaitsDocumentVerification(
            driverFrom(<String, dynamic>{'isDocumentVerify': false, 'isAutoVerify': true})),
        isFalse,
      );
    });

    test('a profile that has not loaded yet is not gated', () {
      // `UserModel()` leaves both fields null, and the screens relied on
      // `null == false` being false to avoid flashing the documents screen
      // before the driver's profile arrives. That must not change.
      Constant.isDriverVerification = true;
      expect(driverAwaitsDocumentVerification(UserModel()), isFalse);
      expect(driverAwaitsDocumentVerification(null), isFalse);
    });

    test('an account with isAutoVerify absent behaves as it did before', () {
      // 6 of the 40 live accounts have no `isAutoVerify` field at all, and
      // `fromJson` gives them null rather than false. They were never gated and
      // must stay that way.
      Constant.isDriverVerification = true;
      expect(
        driverAwaitsDocumentVerification(driverFrom(<String, dynamic>{'isDocumentVerify': false})),
        isFalse,
      );
    });
  });

  group('every home screen with a map uses the shared rule', () {
    const List<String> screens = <String>[
      'lib/app/home_screen/home_screen.dart',
      'lib/app/home_screen/home_screen_multiple_order.dart',
      'lib/app/cab_screen/cab_home_screen.dart',
    ];

    test('none of them re-implements the check inline', () {
      for (final String path in screens) {
        final String screen = sourceOf(path);
        expect(screen.contains('driverAwaitsDocumentVerification'), isTrue,
            reason: '$path is not using the shared rule');
        expect(
          screen.contains('isAutoVerify == false'),
          isFalse,
          reason: '$path is reading the frozen signup flag directly again, which is '
              'what hid the map from 23 of 40 live drivers',
        );
      }
    });

    test('the delivery home still exempts a vendor-attached driver', () {
      // That clause was part of the original condition and is not mine to drop.
      final String screen = sourceOf('lib/app/home_screen/home_screen.dart');
      expect(screen.contains("vendorID?.isEmpty == true"), isTrue);
    });
  });
}
