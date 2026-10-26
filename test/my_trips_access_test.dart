import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/models/driver_trip_model.dart';
import 'package:driver/utils/driver_trip_state.dart';
import 'package:driver/utils/my_trips_access.dart';

/// The admin-granted, time-limited My Trips permission.
///
/// Everything here is the real predicate the app calls: the drawer, the
/// dashboard's bounce-out and the publish path all go through [MyTripsGate],
/// which goes through [MyTripsAccess.isValidAt].
void main() {
  /// A local clock: `Timestamp.toDate()` returns a local `DateTime`, and Dart's
  /// `DateTime ==` compares the UTC flag as well as the instant.
  final DateTime now = DateTime(2026, 9, 5, 10, 0);

  MyTripsAccess grantOf({
    required int days,
    DateTime? grantedAt,
    bool granted = true,
    DateTime? revokedAt,
  }) {
    final DateTime start = grantedAt ?? now;
    return MyTripsAccess.fromJson(<String, dynamic>{
      'granted': granted,
      'durationDays': days,
      'grantedAt': Timestamp.fromDate(start),
      'expiresAt': MyTripsAccess.expiryFor(grantedAt: start, durationDays: days),
      'revokedAt': revokedAt == null ? null : Timestamp.fromDate(revokedAt),
      'grantedBy': 'admin1',
    });
  }

  group('grant duration', () {
    test('one day is a valid duration', () {
      expect(MyTripsAccess.isValidDuration(1), isTrue);
    });

    test('two and ten days are valid durations', () {
      expect(MyTripsAccess.isValidDuration(2), isTrue);
      expect(MyTripsAccess.isValidDuration(10), isTrue);
    });

    test('thirty days is a valid duration', () {
      expect(MyTripsAccess.isValidDuration(30), isTrue);
    });

    test('zero days is refused', () {
      expect(MyTripsAccess.isValidDuration(0), isFalse);
    });

    test('a negative duration is refused', () {
      expect(MyTripsAccess.isValidDuration(-5), isFalse);
    });

    test('more than thirty days is refused', () {
      expect(MyTripsAccess.isValidDuration(31), isFalse);
      expect(MyTripsAccess.isValidDuration(365), isFalse);
    });

    test('a fractional duration is refused - the expiry arithmetic is in whole days', () {
      expect(MyTripsAccess.isValidDuration(1.5), isFalse);
    });

    test('a non-numeric duration is refused', () {
      expect(MyTripsAccess.isValidDuration(null), isFalse);
      expect(MyTripsAccess.isValidDuration('a week'), isFalse);
    });

    test('a whole number written as a string is accepted, as elsewhere in this project', () {
      expect(MyTripsAccess.isValidDuration('7'), isTrue);
    });
  });

  group('expiry arithmetic', () {
    test('a one-day grant ends exactly one day after the server granted it', () {
      final Timestamp end = MyTripsAccess.expiryFor(grantedAt: now, durationDays: 1);
      expect(end.toDate(), now.add(const Duration(days: 1)));
    });

    test('a thirty-day grant ends thirty days after the server granted it', () {
      final Timestamp end = MyTripsAccess.expiryFor(grantedAt: now, durationDays: 30);
      expect(end.toDate(), now.add(const Duration(days: 30)));
    });
  });

  group('validity', () {
    test('a fresh one-day grant is active', () {
      final MyTripsAccess access = grantOf(days: 1);
      expect(access.isValidAt(now), isTrue);
      expect(access.isValidAt(now.add(const Duration(hours: 23))), isTrue);
    });

    test('a ten-day grant is active on day nine and gone on day eleven', () {
      final MyTripsAccess access = grantOf(days: 10);
      expect(access.isValidAt(now.add(const Duration(days: 9))), isTrue);
      expect(access.isValidAt(now.add(const Duration(days: 11))), isFalse);
    });

    test('a thirty-day grant is active on day twenty-nine', () {
      expect(grantOf(days: 30).isValidAt(now.add(const Duration(days: 29))), isTrue);
    });

    test('an expired grant is rejected', () {
      final MyTripsAccess access = grantOf(days: 1);
      final DateTime later = now.add(const Duration(days: 1, minutes: 1));
      expect(access.isValidAt(later), isFalse);
      expect(access.isExpiredAt(later), isTrue);
    });

    test('the moment of expiry is already too late', () {
      final MyTripsAccess access = grantOf(days: 1);
      expect(access.isValidAt(now.add(const Duration(days: 1))), isFalse);
    });

    test('a manually revoked grant is rejected even though its window is still open', () {
      final MyTripsAccess access = grantOf(days: 30, revokedAt: now.add(const Duration(days: 2)));
      expect(access.isValidAt(now.add(const Duration(days: 3))), isFalse);
      expect(access.isRevoked, isTrue);
    });

    test('a grant switched off by the sweep is rejected', () {
      final MyTripsAccess access = grantOf(days: 30, granted: false);
      expect(access.isValidAt(now), isFalse);
    });

    test('a grant with no end instant fails closed', () {
      // This is the state between the admin panel's two writes. It must never
      // read as unlimited access.
      final MyTripsAccess access = MyTripsAccess.fromJson(<String, dynamic>{
        'granted': true,
        'durationDays': 7,
        'grantedAt': Timestamp.fromDate(now),
        'expiresAt': null,
      });
      expect(access.isValidAt(now), isFalse);
    });

    test('a driver with no grant at all has no access', () {
      expect(MyTripsAccess.fromUserJson(<String, dynamic>{'id': 'd1'}).isValidAt(now), isFalse);
      expect(MyTripsAccess.fromUserJson(null).isValidAt(now), isFalse);
      expect(MyTripsAccess.none.isValidAt(now), isFalse);
    });

    test('a malformed grant map has no access', () {
      expect(MyTripsAccess.fromJson('yes').isValidAt(now), isFalse);
      expect(MyTripsAccess.fromJson(42).isValidAt(now), isFalse);
    });

    test('days remaining counts down and bottoms out at zero', () {
      final MyTripsAccess access = grantOf(days: 10);
      expect(access.daysRemainingAt(now), 10);
      expect(access.daysRemainingAt(now.add(const Duration(days: 9, hours: 12))), 1);
      expect(access.daysRemainingAt(now.add(const Duration(days: 20))), 0);
    });
  });

  group('navigation', () {
    test('My Trips is shown in navigation with a valid permission', () {
      expect(MyTripsGate.showsInNavigation(grantOf(days: 2), now), isTrue);
    });

    test('My Trips is hidden without a permission', () {
      expect(MyTripsGate.showsInNavigation(MyTripsAccess.none, now), isFalse);
    });

    test('My Trips is hidden once the permission expires', () {
      expect(MyTripsGate.showsInNavigation(grantOf(days: 1), now.add(const Duration(days: 2))), isFalse);
    });

    test('My Trips is hidden as soon as a permission is revoked', () {
      expect(
        MyTripsGate.showsInNavigation(grantOf(days: 30, revokedAt: now), now.add(const Duration(minutes: 1))),
        isFalse,
      );
    });

    test('the screen closes itself when the permission ends while it is open', () {
      final MyTripsAccess access = grantOf(days: 1);
      expect(MyTripsGate.canOpenMyTrips(access, now), isTrue);
      expect(MyTripsGate.canOpenMyTrips(access, now.add(const Duration(days: 2))), isFalse);
    });
  });

  group('publishing', () {
    final DriverTripModel validTrip = DriverTripModel.fromJson(<String, dynamic>{
      DriverTripFields.id: 'trip1',
      DriverTripFields.driverId: 'driver1',
      DriverTripFields.fromAddress: 'Karachi',
      DriverTripFields.fromLocation: <String, dynamic>{'latitude': 24.8607, 'longitude': 67.0011},
      DriverTripFields.toAddress: 'Hyderabad',
      DriverTripFields.toLocation: <String, dynamic>{'latitude': 25.3960, 'longitude': 68.3578},
      DriverTripFields.tripDateTime: Timestamp.fromDate(now.add(const Duration(hours: 6))),
      DriverTripFields.note: 'Main bus stand',
      DriverTripFields.fullVehiclePrice: 4500,
    });

    test('an authorised driver may publish a valid trip', () {
      expect(
        MyTripsGate.canPublishTrip(
          access: grantOf(days: 3),
          now: now,
          validationErrors: validTrip.validationErrorsAt(now),
        ),
        isTrue,
      );
    });

    test('an unauthorised driver cannot publish, even with a perfectly valid trip', () {
      expect(
        MyTripsGate.canPublishTrip(
          access: MyTripsAccess.none,
          now: now,
          validationErrors: validTrip.validationErrorsAt(now),
        ),
        isFalse,
      );
    });

    test('a driver whose grant expired cannot publish', () {
      expect(
        MyTripsGate.canPublishTrip(
          access: grantOf(days: 1),
          now: now.add(const Duration(days: 2)),
          validationErrors: validTrip.validationErrorsAt(now.add(const Duration(days: 2))),
        ),
        isFalse,
      );
    });

    test('a driver whose grant was revoked cannot publish', () {
      expect(
        MyTripsGate.canPublishTrip(
          access: grantOf(days: 30, revokedAt: now),
          now: now.add(const Duration(minutes: 1)),
          validationErrors: validTrip.validationErrorsAt(now),
        ),
        isFalse,
      );
    });

    test('an authorised driver still cannot publish an invalid trip', () {
      final DriverTripModel bad = DriverTripModel.fromJson(<String, dynamic>{
        ...validTrip.toJson(),
        DriverTripFields.fullVehiclePrice: 0,
      });
      expect(
        MyTripsGate.canPublishTrip(
          access: grantOf(days: 3),
          now: now,
          validationErrors: bad.validationErrorsAt(now),
        ),
        isFalse,
      );
    });
  });
}
