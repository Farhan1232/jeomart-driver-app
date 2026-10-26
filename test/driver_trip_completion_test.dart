import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/models/driver_trip_model.dart';
import 'package:driver/utils/driver_trip_ledger.dart';
import 'package:driver/utils/driver_trip_state.dart';
import 'package:driver/utils/upcoming_trip.dart';

import 'driver_trips_test.dart' show FakeTripStore;

/// The client's second report: "For driver-created trips, there is currently
/// only a Cancel button. Add a Complete Ride option. When the ride is completed,
/// it must be saved correctly in the database and appear in completed ride
/// history for both Driver and Customer apps. Also make sure the scheduled trip
/// appears correctly on the driver's main screen at the trip time."
void main() {
  const String driver = 'driverA';
  const String tripId = 'trip1';
  final String path = 'driver_trips/$tripId';

  String read(String relative) => File(relative).readAsStringSync();

  Map<String, dynamic> bookedTrip({String status = DriverTripStatus.booked}) => <String, dynamic>{
        DriverTripFields.id: tripId,
        DriverTripFields.driverId: driver,
        DriverTripFields.status: status,
        DriverTripFields.fromAddress: 'Lahore',
        DriverTripFields.toAddress: 'Islamabad',
        DriverTripFields.reservedBy: 'customerA',
        DriverTripFields.tripDateTime: Timestamp.fromDate(DateTime(2026, 9, 11, 6)),
      };

  group('the driver can complete their own booked trip', () {
    test('a booked trip becomes completed, with the same fields the sweep writes', () async {
      final FakeTripStore store = FakeTripStore();
      store.seed(path, bookedTrip());
      final DriverTripLedger ledger = DriverTripLedger(store);

      final DateTime now = DateTime(2026, 9, 11, 9, 30);
      expect(await ledger.completeTrip(tripId: tripId, driverId: driver, now: now), CompleteTripResult.ok);

      final Map<String, dynamic> saved = store.read(path)!;
      expect(saved[DriverTripFields.status], DriverTripStatus.completed);
      expect(saved[DriverTripFields.completedAt], Timestamp.fromDate(now));
      expect(saved[DriverTripFields.updatedAt], Timestamp.fromDate(now));
      expect(saved[DriverTripFields.completedBy], DriverTripCancelledBy.driver,
          reason: 'so a trip the driver finished can be told from one the grace period closed');

      // The reservation is untouched: the customer who took the vehicle is
      // still on the trip, which is what puts it in *their* completed history.
      expect(saved[DriverTripFields.reservedBy], 'customerA');
    });

    test('an unreserved trip cannot be completed - there was no journey', () async {
      final FakeTripStore store = FakeTripStore();
      store.seed(path, bookedTrip(status: DriverTripStatus.active));
      final DriverTripLedger ledger = DriverTripLedger(store);

      expect(
        await ledger.completeTrip(tripId: tripId, driverId: driver, now: DateTime(2026, 9, 11, 9)),
        CompleteTripResult.notBooked,
      );
      expect(store.read(path)![DriverTripFields.status], DriverTripStatus.active,
          reason: 'a refused completion must change nothing');
    });

    test('another driver cannot complete it', () async {
      final FakeTripStore store = FakeTripStore();
      store.seed(path, bookedTrip());
      final DriverTripLedger ledger = DriverTripLedger(store);

      expect(
        await ledger.completeTrip(tripId: tripId, driverId: 'driverB', now: DateTime(2026, 9, 11, 9)),
        CompleteTripResult.notOwner,
      );
      expect(store.read(path)![DriverTripFields.status], DriverTripStatus.booked);
    });

    test('a trip the sweep already completed reports that, and is not rewritten', () async {
      final FakeTripStore store = FakeTripStore();
      final Timestamp sweepStamp = Timestamp.fromDate(DateTime(2026, 9, 11, 12));
      store.seed(path, <String, dynamic>{
        ...bookedTrip(status: DriverTripStatus.completed),
        DriverTripFields.completedAt: sweepStamp,
      });
      final DriverTripLedger ledger = DriverTripLedger(store);

      expect(
        await ledger.completeTrip(tripId: tripId, driverId: driver, now: DateTime(2026, 9, 11, 13)),
        CompleteTripResult.alreadyFinished,
      );
      expect(store.read(path)![DriverTripFields.completedAt], sweepStamp,
          reason: 'whoever got there first decides; the second writer must not move the timestamp');
      expect(store.read(path)!.containsKey(DriverTripFields.completedBy), isFalse);
    });

    test('a cancelled trip cannot be resurrected as completed', () async {
      final FakeTripStore store = FakeTripStore();
      store.seed(path, bookedTrip(status: DriverTripStatus.cancelled));
      final DriverTripLedger ledger = DriverTripLedger(store);

      expect(
        await ledger.completeTrip(tripId: tripId, driverId: driver, now: DateTime(2026, 9, 11, 9)),
        CompleteTripResult.alreadyFinished,
      );
      expect(store.read(path)![DriverTripFields.status], DriverTripStatus.cancelled);
    });

    test('a missing trip is reported, not created', () async {
      final FakeTripStore store = FakeTripStore();
      final DriverTripLedger ledger = DriverTripLedger(store);

      expect(
        await ledger.completeTrip(tripId: tripId, driverId: driver, now: DateTime(2026, 9, 11, 9)),
        CompleteTripResult.tripGone,
      );
      expect(store.read(path), isNull);
    });

    test('two taps produce one completion', () async {
      final FakeTripStore store = FakeTripStore();
      store.seed(path, bookedTrip());
      final DriverTripLedger ledger = DriverTripLedger(store);

      final List<CompleteTripResult> results = await Future.wait(<Future<CompleteTripResult>>[
        ledger.completeTrip(tripId: tripId, driverId: driver, now: DateTime(2026, 9, 11, 9)),
        ledger.completeTrip(tripId: tripId, driverId: driver, now: DateTime(2026, 9, 11, 9)),
      ]);

      expect(results.where((CompleteTripResult r) => r == CompleteTripResult.ok).length, 1);
      expect(results.where((CompleteTripResult r) => r == CompleteTripResult.alreadyFinished).length, 1);
    });
  });

  group('a completed trip is history in both apps', () {
    test('the status both apps already understand is the one that is written', () {
      // `completed` was added to both apps byte-identically in Session 14, and
      // the customer app maps it to its Completed tab. Writing that exact
      // status is what makes the client's "appear in completed ride history for
      // both Driver and Customer apps" true without touching the customer app.
      expect(DriverTripStatus.completed, 'completed');
      expect(DriverTripStatus.isFinished(DriverTripStatus.completed), isTrue);
      expect(DriverTripStatus.all, contains(DriverTripStatus.completed));

      final File customerTab = File('../../customer/customer/lib/models/booking_entry.dart');
      if (customerTab.existsSync()) {
        final String source = customerTab.readAsStringSync();
        expect(source, contains('case DriverTripStatus.completed:'),
            reason: "the customer's Completed tab must claim this status");
      }
    });

    test('only a booked trip is offered the button, in the screen and in the ledger', () {
      expect(DriverTripStatus.acceptsCompletion(DriverTripStatus.booked), isTrue);
      for (final String other in <String>[
        DriverTripStatus.active,
        DriverTripStatus.expired,
        DriverTripStatus.cancelled,
        DriverTripStatus.completed,
      ]) {
        expect(DriverTripStatus.acceptsCompletion(other), isFalse);
      }

      // The screen asks the same question the transaction does, so the button
      // cannot appear on a card whose write would be refused.
      final String screen = read('lib/app/cab_screen/my_trips_screen.dart');
      expect(screen, contains('DriverTripStatus.acceptsCompletion(status)'));
      expect(screen, contains('"Complete Ride".tr'));
      expect(screen, contains('controller.completeTrip(trip)'));
      expect(screen, contains('_confirmComplete(controller, trip, isDark)'),
          reason: 'a final status is confirmed, not written on the tap');
    });

    test('Complete Ride and Cancel Trip cannot both be in flight for one trip', () {
      final String controller = read('lib/controllers/my_trips_controller.dart');
      expect(controller, contains('RxString completeInFlight'));
      expect(controller, contains('return cancelInFlight.value == id || completeInFlight.value == id;'));
      // Both entry points take the shared guard.
      expect(RegExp(r'if \(tripId\.isEmpty \|\| isBusy\(trip\)\) return;').allMatches(controller).length, 2);
    });

    test('the customer is told after the state is settled, not before', () {
      final String controller = read('lib/controllers/my_trips_controller.dart');
      final int ok = controller.indexOf('case CompleteTripResult.ok:');
      final int notify = controller.indexOf('DriverTripService.notifyReservationCompleted(trip)');
      expect(ok, greaterThan(-1));
      expect(notify, greaterThan(ok),
          reason: 'the notification points at history, so it must follow the write');
    });
  });

  group('the scheduled trip reaches the main screen at the trip time', () {
    DriverTripModel tripAt(DateTime when, {String status = DriverTripStatus.booked}) =>
        DriverTripModel.fromJson(<String, dynamic>{
          DriverTripFields.id: 'trip-${when.millisecondsSinceEpoch}-$status',
          DriverTripFields.driverId: driver,
          DriverTripFields.status: status,
          DriverTripFields.fromAddress: 'Lahore',
          DriverTripFields.toAddress: 'Islamabad',
          DriverTripFields.tripDateTime: Timestamp.fromDate(when),
          // Far enough out that `effectiveStatusAt` never calls these expired.
          DriverTripFields.visibilityExpiresAt: Timestamp.fromDate(when.add(const Duration(days: 30))),
        });

    final DateTime departure = DateTime(2026, 9, 11, 6);

    test('it appears when the window opens and not before', () {
      final DriverTripModel trip = tripAt(departure);

      expect(UpcomingTrip.isCurrent(trip, departure.subtract(const Duration(hours: 3))), isFalse,
          reason: 'a trip three hours out belongs in My Trips, not over the map');
      expect(UpcomingTrip.isCurrent(trip, departure.subtract(UpcomingTrip.leadIn)), isTrue,
          reason: 'exactly at the lead-in it is shown');
      expect(UpcomingTrip.isCurrent(trip, departure), isTrue, reason: 'at the trip time - the client\'s words');
      expect(UpcomingTrip.isCurrent(trip, departure.add(const Duration(hours: 5))), isTrue);
      expect(UpcomingTrip.isCurrent(trip, departure.add(UpcomingTrip.holdOver)), isTrue);
      expect(UpcomingTrip.isCurrent(trip, departure.add(const Duration(hours: 7))), isFalse,
          reason: 'past the completion grace it is no longer the trip in hand');
    });

    test('the hold-over matches the server sweep, so the banner outlives the button by nothing', () {
      expect(UpcomingTrip.holdOver, const Duration(hours: 6),
          reason: 'DEFAULT_COMPLETION_GRACE_HOURS in driverTripsMaintenance.js');
    });

    test('a finished trip never appears, whatever its time says', () {
      for (final String status in <String>[
        DriverTripStatus.completed,
        DriverTripStatus.cancelled,
        DriverTripStatus.expired,
      ]) {
        expect(UpcomingTrip.isCurrent(tripAt(departure, status: status), departure), isFalse, reason: status);
      }
    });

    test('a trip with no departure time has no window', () {
      final DriverTripModel undated = DriverTripModel.fromJson(<String, dynamic>{
        DriverTripFields.id: 'undated',
        DriverTripFields.driverId: driver,
        DriverTripFields.status: DriverTripStatus.booked,
      });
      expect(UpcomingTrip.isCurrent(undated, departure), isFalse);
    });

    test('the earliest departure in the window is the one shown', () {
      final DriverTripModel soon = tripAt(departure);
      final DriverTripModel later = tripAt(departure.add(const Duration(hours: 1)));
      final DriverTripModel yesterday = tripAt(departure.subtract(const Duration(days: 1)));

      expect(UpcomingTrip.pick(<DriverTripModel>[later, soon, yesterday], departure)?.id, soon.id);
      expect(UpcomingTrip.pick(<DriverTripModel>[], departure), isNull);
      expect(UpcomingTrip.pick(<DriverTripModel>[yesterday], departure), isNull,
          reason: 'nothing in the window means nothing on the map');
    });

    test('a booked trip wins a tie against an unreserved one', () {
      final DriverTripModel open = tripAt(departure, status: DriverTripStatus.active);
      final DriverTripModel taken = tripAt(departure, status: DriverTripStatus.booked);

      expect(UpcomingTrip.pick(<DriverTripModel>[open, taken], departure)?.status, DriverTripStatus.booked);
      expect(UpcomingTrip.pick(<DriverTripModel>[taken, open], departure)?.status, DriverTripStatus.booked,
          reason: 'the order the query returned them in must not decide it');
    });

    test('the timing line says the right thing at each point in the window', () {
      final DriverTripModel trip = tripAt(departure);

      expect(UpcomingTrip.timingFor(trip, departure.subtract(const Duration(minutes: 25))).when,
          UpcomingTripWhen.inMinutes);
      expect(UpcomingTrip.timingFor(trip, departure.subtract(const Duration(minutes: 25))).value, 25);
      expect(UpcomingTrip.timingFor(trip, departure.subtract(const Duration(minutes: 90))).when,
          UpcomingTripWhen.inHours);
      expect(UpcomingTrip.timingFor(trip, departure).when, UpcomingTripWhen.due);
      expect(UpcomingTrip.timingFor(trip, departure.add(const Duration(minutes: 40))).when,
          UpcomingTripWhen.underway);
      expect(UpcomingTrip.timingFor(trip, departure.add(const Duration(minutes: 40))).value, 40);
    });

    test('the banner costs a driver who cannot post trips nothing at all', () {
      final String source = read('lib/widget/upcoming_trip_banner.dart');
      final int gate = source.indexOf('Constant.hasMyTripsAccess');
      final int listen = source.indexOf('.snapshots()');
      expect(gate, greaterThan(-1));
      expect(gate, lessThan(listen), reason: 'the grant is checked before the listener is opened');
      expect(source, contains('DriverTripService.myTripsQuery(uid)'),
          reason: 'reusing My Trips\' own query is what keeps this off a new composite index');
    });

    test('the home screen keeps every Stack child positioned', () {
      // Session 26: the cab home `Stack` collapsed to 0x0 because its only
      // non-positioned child was an empty box, and the map filled nothing. The
      // banner is inside the existing top `Positioned`, not a new sibling of
      // the map.
      final String source = read('lib/app/cab_screen/cab_home_screen.dart');
      expect(source, contains('UpcomingTripBanner(isDark: isDark)'));
      final int positioned = source.indexOf('// The two top notices');
      final int banner = source.indexOf('UpcomingTripBanner(isDark: isDark)');
      expect(positioned, greaterThan(-1));
      expect(positioned, lessThan(banner));
      expect(RegExp(r'Positioned\(\s*top: 0,').allMatches(source).length, 1,
          reason: 'two top-anchored overlays would draw on top of each other');
    });
  });
}
