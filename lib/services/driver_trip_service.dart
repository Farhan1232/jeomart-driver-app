import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/send_notification.dart';
import 'package:driver/models/driver_trip_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/utils/driver_trip_ledger.dart';
import 'package:driver/utils/driver_trip_state.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/my_trips_access.dart';
import 'package:driver/utils/trip_transaction.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// The driver side of the My Trips feature.
///
/// Inert for a driver without a valid admin grant: [canPublish] is false, the
/// drawer entry is not built, and [publishTrip] refuses before it writes
/// anything.
class DriverTripService {
  static FirebaseFirestore get _fireStore => FireStoreUtils.fireStore;

  static DriverTripLedger get ledger =>
      DriverTripLedger(FirestoreTripTransactionRunner(_fireStore), tripsCollection: CollectionName.driverTrips);

  /// Whether this driver may publish a trip right now.
  ///
  /// The same predicate the navigation uses, so a driver who loses access mid
  /// session cannot reach the form through a stale route either.
  static bool get canPublish => MyTripsGate.canOpenMyTrips(
        Constant.myTripsAccess,
        DateTime.now(),
        openToAllDrivers: Constant.driverTripSettings.openToAllDrivers,
      );

  /// The driver's own trips, newest first.
  ///
  /// One equality filter plus the sort, which is the shape Session 1's
  /// paginator pages with `limit()` + `startAfterDocument()`. Status tabs stay
  /// client-side, exactly as the ride, parcel and rental history screens do,
  /// so no extra composite index is needed for them.
  static Query<Map<String, dynamic>> myTripsQuery(String driverId) {
    return _fireStore
        .collection(CollectionName.driverTrips)
        .where(DriverTripFields.driverId, isEqualTo: driverId)
        .orderBy(DriverTripFields.createdAt, descending: true);
  }

  /// The reserving customer's contact block, once a trip is booked.
  static Future<TripReservationModel?> reservationFor(DriverTripModel trip) async {
    final String tripId = trip.id ?? '';
    final String customerId = trip.reservedBy ?? '';
    if (tripId.isEmpty || customerId.isEmpty) return null;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await _fireStore
          .collection(CollectionName.driverTrips)
          .doc(tripId)
          .collection(DriverTripCollections.reservation)
          .doc(customerId)
          .get();
      if (!snapshot.exists) return null;
      return TripReservationModel.fromJson(snapshot.data()!);
    } catch (error) {
      log('DriverTripService.reservationFor failed :: $error');
      return null;
    }
  }

  /// Builds the trip document for [driver], including the small card snapshot
  /// the customer's list renders from.
  ///
  /// `createdAt` uses `Timestamp.now()` because that is what every other write
  /// in these apps does; the visibility window is measured from it with the
  /// admin's configured number of hours, snapshotted onto the trip so a later
  /// settings change cannot retroactively re-open or close trips already out
  /// there.
  static DriverTripModel buildTrip({
    required UserModel driver,
    required String sectionId,
    required String fromAddress,
    required TripLocation fromLocation,
    required String toAddress,
    required TripLocation toLocation,
    required DateTime departure,
    required String note,
    required double fullVehiclePrice,
    required DateTime now,
    String? vehicleTypeName,
    num? completedTrips,
  }) {
    final Map<String, dynamic> vehicle = _vehicleFor(driver, sectionId);
    final int hours = Constant.driverTripSettings.visibilityHours;

    return DriverTripModel(
      id: const Uuid().v4(),
      driverId: driver.id,
      sectionId: sectionId,
      status: DriverTripStatus.active,
      fromAddress: fromAddress.trim(),
      fromLocation: fromLocation,
      toAddress: toAddress.trim(),
      toLocation: toLocation,
      tripDateTime: Timestamp.fromDate(departure),
      note: note.trim(),
      fullVehiclePrice: fullVehiclePrice,
      createdAt: Timestamp.fromDate(now),
      updatedAt: Timestamp.fromDate(now),
      visibilityExpiresAt: DriverTripVisibility.expiryFor(createdAt: now, visibilityHours: hours),
      visibilityHours: hours,
      driverName: driver.fullName().trim(),
      driverPhoto: driver.profilePictureURL ?? '',
      driverRating: driver.averageRating,
      driverReviewsCount: num.tryParse(driver.reviewsCount ?? '0') ?? 0,
      driverCompletedTrips: completedTrips ?? driver.orderCompleted ?? 0,
      driverFcmToken: driver.fcmToken ?? '',
      vehicleType: vehicleTypeName ?? '',
      vehicleBrand: vehicle['carBrand']?.toString() ?? '',
      vehicleModel: vehicle['carModel']?.toString() ?? '',
      vehiclePlate: vehicle['carPlateNumber']?.toString() ?? '',
      airConditioning: vehicle['airConditioning'] is bool ? vehicle['airConditioning'] as bool : null,
      reservedBy: null,
      reservedByName: null,
      reservedByPhoto: null,
      reservedAt: null,
    );
  }

  /// Writes a new trip.
  ///
  /// Refuses a driver who may not post - no valid grant and the admin's global
  /// switch off - and refuses a trip that would not have passed the form. That
  /// is what makes "an unauthorised driver cannot create a trip through the
  /// application" true of the write path and not only of the button they can no
  /// longer see.
  static Future<bool> publishTrip(DriverTripModel trip, {DateTime? now}) async {
    final DateTime moment = now ?? DateTime.now();
    if (!MyTripsGate.canPublishTrip(
      access: Constant.myTripsAccess,
      now: moment,
      validationErrors: trip.validationErrorsAt(moment),
      openToAllDrivers: Constant.driverTripSettings.openToAllDrivers,
    )) {
      return false;
    }
    final String tripId = trip.id ?? '';
    if (tripId.isEmpty) return false;
    try {
      await _fireStore.collection(CollectionName.driverTrips).doc(tripId).set(trip.toJson());
      return true;
    } catch (error) {
      log('DriverTripService.publishTrip failed :: $error');
      return false;
    }
  }

  /// The driver withdraws one of their own trips.
  static Future<CancelTripResult> cancelTrip(DriverTripModel trip) async {
    return ledger.cancelTrip(
      tripId: trip.id ?? '',
      driverId: FireStoreUtils.getCurrentUid(),
      now: DateTime.now(),
    );
  }

  /// The driver marks one of their own booked trips as finished.
  static Future<CompleteTripResult> completeTrip(DriverTripModel trip) async {
    return ledger.completeTrip(
      tripId: trip.id ?? '',
      driverId: FireStoreUtils.getCurrentUid(),
      now: DateTime.now(),
    );
  }

  /// Tells the customer who reserved a trip that the driver has completed it.
  ///
  /// Same device-to-device path as [notifyReservationCancelled], for the same
  /// reason: the alternative is creating `notifications/{type}` documents in the
  /// client's production Firestore, which this work does not do.
  static Future<void> notifyReservationCompleted(DriverTripModel trip) async {
    final TripReservationModel? reservation = await reservationFor(trip);
    final String token = reservation?.fcmToken ?? '';
    if (token.isEmpty) return;
    try {
      await SendNotification.sendOneNotification(
        token: token,
        title: 'Trip completed'.tr,
        body: 'The driver marked your trip as completed.'.tr,
        payload: <String, dynamic>{'type': Constant.tripCompletedNotification, 'tripId': trip.id ?? ''},
      );
    } catch (error) {
      log('DriverTripService.notifyReservationCompleted failed :: $error');
    }
  }

  /// Tells the customer who had reserved a trip that the driver cancelled it.
  ///
  /// Uses the project's existing device-to-device path, the same call the
  /// bidding feature makes, with explicit text rather than a
  /// `notifications/{type}` document - creating those documents would mean
  /// writing to the client's production Firestore, which this work does not do.
  static Future<void> notifyReservationCancelled(DriverTripModel trip) async {
    final TripReservationModel? reservation = await reservationFor(trip);
    final String token = reservation?.fcmToken ?? '';
    if (token.isEmpty) return;
    try {
      await SendNotification.sendOneNotification(
        token: token,
        title: 'Trip cancelled'.tr,
        body: 'The driver cancelled the trip you reserved.'.tr,
        payload: <String, dynamic>{'type': Constant.tripCancelledNotification, 'tripId': trip.id ?? ''},
      );
    } catch (error) {
      log('DriverTripService.notifyReservationCancelled failed :: $error');
    }
  }

  static Map<String, dynamic> _vehicleFor(UserModel driver, String sectionId) {
    final Object? raw = driver.vehicleDetails?[sectionId];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }
}
