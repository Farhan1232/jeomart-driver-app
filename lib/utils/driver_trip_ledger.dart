import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_trip_model.dart';
import 'driver_trip_state.dart';
import 'trip_transaction.dart';

/// Why a reservation did not go through.
enum ReserveTripResult {
  ok,

  /// The trip document is gone.
  tripGone,

  /// The driver withdrew it, or the sweep closed it.
  notActive,

  /// Somebody else took the vehicle. This is the state a second, racing
  /// reservation ends in, and it is why a full vehicle can never be booked
  /// twice.
  alreadyReserved,

  /// The visibility window closed, or the departure time has passed.
  expired,

  /// A driver cannot reserve their own trip.
  ownTrip,
}

/// Why a cancellation did not go through.
enum CancelTripResult {
  ok,
  tripGone,

  /// Somebody other than the trip's own driver tried to cancel it.
  notOwner,

  /// Already expired or already cancelled.
  alreadyFinished,
}

/// Why marking a trip finished did not go through.
enum CompleteTripResult {
  ok,
  tripGone,

  /// Somebody other than the trip's own driver tried to complete it.
  notOwner,

  /// Already completed, cancelled or expired - including the case where the
  /// server sweep got there first, which is not an error worth alarming the
  /// driver about.
  alreadyFinished,

  /// Nobody reserved the vehicle, so there was no journey to finish. Such a
  /// trip expires; it is never completed.
  notBooked,
}

/// Every write that decides a driver-created trip, in one place and inside a
/// transaction.
///
/// The requirement this exists for is the full-vehicle one: when two customers
/// tap Book at the same instant, exactly one of them gets the vehicle, and the
/// loser is told why - decided at the database, not in the UI. That is
/// [reserveTrip]: it re-reads the trip inside the transaction and refuses
/// unless it is still active, unreserved and inside its window, so Firestore's
/// own replay is what serialises the two taps.
///
/// There is deliberately no seat count anywhere in this class. A trip is one
/// vehicle and one reservation.
class DriverTripLedger {
  DriverTripLedger(this.runner, {this.tripsCollection = DriverTripCollections.trips});

  final TripTransactionRunner runner;
  final String tripsCollection;

  String tripPath(String tripId) => '$tripsCollection/$tripId';

  String reservationPath(String tripId, String customerId) =>
      '$tripsCollection/$tripId/${DriverTripCollections.reservation}/$customerId';

  /// Takes the whole vehicle for one customer.
  ///
  /// [reservation] carries the customer's contact details. They are written to
  /// the reservation subcollection in the same commit, so the driver gets them
  /// at the moment the trip becomes theirs and no earlier - the trip document
  /// every other customer can read never holds them.
  Future<ReserveTripResult> reserveTrip({
    required String tripId,
    required String customerId,
    required String customerName,
    required String customerPhoto,
    required TripReservationModel reservation,
    required DateTime now,
  }) {
    if (tripId.isEmpty || customerId.isEmpty) {
      return Future<ReserveTripResult>.value(ReserveTripResult.tripGone);
    }

    return runner.run<ReserveTripResult>((TripTransactionContext ctx) async {
      final TripDocument tripDoc = await ctx.get(tripPath(tripId));
      if (!tripDoc.exists) return ReserveTripResult.tripGone;

      final DriverTripModel trip = DriverTripModel.fromJson(tripDoc.data ?? <String, dynamic>{});

      // Read the reservation first: a trip that already has one must report
      // that, not the generic "not active", so the losing tap can say why.
      if (trip.hasReservation) {
        return trip.reservedBy == customerId ? ReserveTripResult.ok : ReserveTripResult.alreadyReserved;
      }
      if (trip.driverId == customerId) return ReserveTripResult.ownTrip;
      if (!DriverTripStatus.acceptsReservation(trip.status)) return ReserveTripResult.notActive;
      if (!DriverTripVisibility.isVisibleAt(now,
          visibilityExpiresAt: trip.visibilityExpiresAt, tripDateTime: trip.tripDateTime)) {
        return ReserveTripResult.expired;
      }

      final Timestamp nowStamp = Timestamp.fromDate(now);

      ctx.update(tripPath(tripId), <String, dynamic>{
        DriverTripFields.status: DriverTripStatus.booked,
        DriverTripFields.reservedBy: customerId,
        DriverTripFields.reservedByName: customerName,
        DriverTripFields.reservedByPhoto: customerPhoto,
        DriverTripFields.reservedAt: nowStamp,
        DriverTripFields.updatedAt: nowStamp,
      });

      final Map<String, dynamic> payload = reservation.toJson()
        ..['id'] = customerId
        ..['tripId'] = tripId
        ..['customerId'] = customerId
        ..['createdAt'] = nowStamp;
      ctx.set(reservationPath(tripId, customerId), payload);

      return ReserveTripResult.ok;
    });
  }

  /// The driver withdraws their own trip.
  ///
  /// Allowed while the trip is active and while it is booked - a driver whose
  /// vehicle breaks down has to be able to tell the customer. The customer is
  /// notified by the caller; this only decides the state.
  Future<CancelTripResult> cancelTrip({
    required String tripId,
    required String driverId,
    required DateTime now,
  }) {
    if (tripId.isEmpty || driverId.isEmpty) {
      return Future<CancelTripResult>.value(CancelTripResult.tripGone);
    }

    return runner.run<CancelTripResult>((TripTransactionContext ctx) async {
      final TripDocument tripDoc = await ctx.get(tripPath(tripId));
      if (!tripDoc.exists) return CancelTripResult.tripGone;

      final DriverTripModel trip = DriverTripModel.fromJson(tripDoc.data ?? <String, dynamic>{});

      // A driver can only ever act on their own trip. The driver app never
      // shows another driver's trips, and this is the check that makes that
      // true rather than merely apparent.
      if ((trip.driverId ?? '') != driverId) return CancelTripResult.notOwner;
      if (DriverTripStatus.isFinished(trip.status)) return CancelTripResult.alreadyFinished;

      final Timestamp nowStamp = Timestamp.fromDate(now);
      ctx.update(tripPath(tripId), <String, dynamic>{
        DriverTripFields.status: DriverTripStatus.cancelled,
        DriverTripFields.cancelledAt: nowStamp,
        DriverTripFields.cancelledBy: DriverTripCancelledBy.driver,
        DriverTripFields.updatedAt: nowStamp,
      });
      return CancelTripResult.ok;
    });
  }

  /// The driver marks their own booked trip as finished.
  ///
  /// The one write that turns a driver-created trip into completed history, and
  /// it is the same status and the same field the server sweep writes - so the
  /// trip lands in the driver's Completed tab and in the customer's Completed
  /// tab (`BookingTab.forTripStatus` already maps it) with no second shape to
  /// interpret anywhere.
  ///
  /// Inside a transaction for the same reason [cancelTrip] is: the state is
  /// re-read before it is changed, so a trip the customer cancelled or the
  /// sweep closed a moment earlier is reported as already finished rather than
  /// silently overwritten. Ownership is checked here rather than in the UI,
  /// which is what makes "a driver can only finish their own trip" true instead
  /// of merely apparent.
  Future<CompleteTripResult> completeTrip({
    required String tripId,
    required String driverId,
    required DateTime now,
  }) {
    if (tripId.isEmpty || driverId.isEmpty) {
      return Future<CompleteTripResult>.value(CompleteTripResult.tripGone);
    }

    return runner.run<CompleteTripResult>((TripTransactionContext ctx) async {
      final TripDocument tripDoc = await ctx.get(tripPath(tripId));
      if (!tripDoc.exists) return CompleteTripResult.tripGone;

      final DriverTripModel trip = DriverTripModel.fromJson(tripDoc.data ?? <String, dynamic>{});

      if ((trip.driverId ?? '') != driverId) return CompleteTripResult.notOwner;
      if (DriverTripStatus.isFinished(trip.status)) return CompleteTripResult.alreadyFinished;
      if (!DriverTripStatus.acceptsCompletion(trip.status)) return CompleteTripResult.notBooked;

      final Timestamp nowStamp = Timestamp.fromDate(now);
      ctx.update(tripPath(tripId), <String, dynamic>{
        DriverTripFields.status: DriverTripStatus.completed,
        DriverTripFields.completedAt: nowStamp,
        DriverTripFields.completedBy: DriverTripCancelledBy.driver,
        DriverTripFields.updatedAt: nowStamp,
      });
      return CompleteTripResult.ok;
    });
  }
}
