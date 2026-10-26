import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/send_notification.dart';
import 'package:driver/models/cab_order_model.dart';
import 'package:driver/models/ride_bid_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/utils/active_ride_selection.dart';
import 'package:driver/utils/bidding_fare_rules.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/ride_bid_ledger.dart';
import 'package:driver/utils/ride_bidding_state.dart';

/// One open bidding request as the driver sees it: the ride itself, plus the
/// bidding fields that live alongside it on the same document.
class BiddingRequest {
  const BiddingRequest({required this.ride, required this.state});

  final CabOrderModel ride;
  final RideBiddingState state;

  String get id => ride.id ?? '';

  /// The trip length in **kilometres**.
  ///
  /// `biddingDistanceKm` is the normalised copy the customer writes with the
  /// request; `ride.distance` is a string in whatever unit the install
  /// displays, so it is only the fallback for a request written before that
  /// field existed.
  double get distanceKm {
    final double normalised = state.distanceKm.toDouble();
    if (normalised > 0) return normalised;
    return double.tryParse(ride.distance ?? '') ?? 0.0;
  }

  /// The requested vehicle type's own minimum fare per km, when it has one.
  ///
  /// The floor itself is still recomputed from the admin settings; this only
  /// says *which* configured rate applies, so a motorcycle is not held to a
  /// car's minimum. It comes from the request because the driver's own settings
  /// do not know which vehicle the customer asked for.
  num? get vehicleRatePerKm => state.vehicleRatePerKm;

  num get offeredFare => state.offeredFare ?? 0;
}

/// The driver side of the bidding / counter-offer feature.
///
/// Inert while `settings/biddingSettings.enabled` is false: no listener is
/// opened, no query runs, and the driver's ride flow is exactly what it was.
class BiddingService {
  static FirebaseFirestore get _fireStore => FireStoreUtils.fireStore;

  static RideBidLedger get ledger => RideBidLedger(FirestoreBidTransactionRunner(_fireStore), ridesCollection: CollectionName.ridesBooking);

  static int get currencyDecimals => Constant.currencyModel?.decimalDigits ?? 2;

  /// The note the driver can attach to an offer. Stored as this key, not as
  /// translated text, so the customer reads it in their own language.
  static const String driverNoteKey = 'Come fast or take that ruote';

  /// Bidding requests this driver is eligible for.
  ///
  /// Eligibility is decided by the dispatcher using the platform's existing
  /// availability / vehicle / section / zone / radius / wallet filters, and
  /// written to the ride as `biddingEligibleDriverIds`. A driver who would not
  /// normally be sent this ride is not in that array and therefore cannot see
  /// or bid on the request - the query itself excludes them.
  static Stream<List<BiddingRequest>> openRequestsStream({int limit = 20}) {
    final String uid = FireStoreUtils.getCurrentUid();
    return _fireStore
        .collection(CollectionName.ridesBooking)
        .where(RideBiddingFields.eligibleDriverIds, arrayContains: uid)
        .where(RideBiddingFields.status, isEqualTo: RideBiddingStatus.open)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
            .map((doc) => BiddingRequest(ride: CabOrderModel.fromJson(doc.data()), state: RideBiddingState.fromJson(doc.data())))
            .toList());
  }

  /// Requests this driver has **won** and not yet taken over.
  ///
  /// Without this the only thing that ever told a driver their offer had been
  /// accepted was a listener opened, in memory, at the moment they submitted
  /// that offer. Leave the Bid section, or close the app, and that listener
  /// goes with it - so the acceptance reached the driver's phone only when the
  /// dispatcher next swept, which is a cron a minute wide. That is the "the
  /// driver app updates after more than a minute" report.
  ///
  /// Accepting an offer sets the ride's `biddingEligibleDriverIds` to the
  /// winner alone and its `biddingStatus` to `accepted`, so this is the same
  /// query shape as [openRequestsStream] with a different status value - the
  /// same composite index serves both, and nothing new has to be deployed for
  /// it. It is a live listener, so the hand-off now happens in the time one
  /// Firestore snapshot takes.
  static Stream<List<String>> wonRequestsStream({int limit = 5}) {
    final String uid = FireStoreUtils.getCurrentUid();
    return _fireStore
        .collection(CollectionName.ridesBooking)
        .where(RideBiddingFields.eligibleDriverIds, arrayContains: uid)
        .where(RideBiddingFields.status, isEqualTo: RideBiddingStatus.accepted)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
            // An award on a ride that has since ended is history, not a ride
            // to take over - see ActiveRideSelection.
            .where((doc) => RideBiddingState.fromJson(doc.data()).winningBidId == uid && !ActiveRideSelection.hasEnded(doc.data()['status']))
            .map((doc) => doc.id)
            .toList());
  }

  /// The raw bidding fields of one ride, so the driver's card can show the
  /// asked fare and the request's deadline.
  static Stream<Map<String, dynamic>?> rideStream(String rideId) {
    return _fireStore
        .collection(CollectionName.ridesBooking)
        .doc(rideId)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> doc) => doc.data());
  }

  /// This driver's own offer on one ride.
  static Stream<RideBidModel?> myBidStream(String rideId) {
    final String uid = FireStoreUtils.getCurrentUid();
    return _fireStore
        .collection(CollectionName.ridesBooking)
        .doc(rideId)
        .collection(RideBidModel.collectionName)
        .doc(uid)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> doc) => doc.exists ? RideBidModel.fromJson(doc.data()!) : null);
  }

  /// Client-side check, for immediate feedback while the driver types a
  /// counter-offer. Re-checked inside the submit transaction, and in the
  /// security rules once they are deployed.
  ///
  /// [vehicleRatePerKm] is the requested vehicle type's own rate, off the ride.
  /// The floor is still recomputed from this app's copy of the admin settings -
  /// the vehicle only selects which configured rate applies, so a motorcycle is
  /// not held to a car's minimum.
  static FareCheckResult checkFare({
    required double? amount,
    required double distanceKm,
    num? vehicleRatePerKm,
  }) =>
      BiddingFareRules.check(
        amount: amount,
        settings: Constant.biddingSettings,
        distanceKm: distanceKm,
        currencyDecimals: currencyDecimals,
        vehicleRatePerKm: vehicleRatePerKm,
      );

  static double minimumAllowedFare(double distanceKm, {num? vehicleRatePerKm}) =>
      BiddingFareRules.minimumAllowedFare(
        settings: Constant.biddingSettings,
        distanceKm: distanceKm,
        currencyDecimals: currencyDecimals,
        vehicleRatePerKm: vehicleRatePerKm,
      );

  /// How many rides this driver has completed, for the customer's offer card.
  ///
  /// Prefers the `orderCompleted` counter the admin panel already maintains on
  /// the user document, and only falls back to a server-side aggregate - one
  /// `count()`, not a document read per ride - when that field is missing.
  static Future<num> completedTrips(UserModel driver) async {
    // The stored counter is only as fresh as the last time an admin opened
    // the panel's Drivers page, and it was written as 0 for every taxi
    // driver - so customers saw "0 trips" from drivers with 21 completed
    // rides. The real count of completed rides is used now; the stored value
    // is only a floor, and the fallback when the count cannot be read.
    final Object? stored = driver.orderCompleted;
    final num storedCount = stored is num ? stored : (num.tryParse(stored?.toString() ?? '') ?? 0);
    num? counted;
    final Future<num?>? warm = _warmTrips;
    if (warm != null && _warmTripsFor == driver.id && _isWarmFresh(DateTime.now())) {
      counted = await warm;
    }
    counted ??= await tripCounter(driver);
    if (counted == null) return storedCount;
    return counted > storedCount ? counted : storedCount;
  }

  /// Starts [completedTrips]' count while the driver is still reading the
  /// request, instead of after they tap.
  ///
  /// For a profile without an `orderCompleted` counter that count is a
  /// round trip of its own, and it ran inside the "Please wait" of every offer,
  /// in front of the offer's transaction. The number is the same one: it is
  /// only reused for [warmTripsFor], and [forgetCompletedTrips] drops it while
  /// the driver is on a ride - the only time it can change.
  static void warmCompletedTrips(UserModel driver) {
    if (driver.id == null) return;
    final DateTime now = DateTime.now();
    if (_warmTrips != null && _warmTripsFor == driver.id && _isWarmFresh(now)) return;
    _warmTripsFor = driver.id;
    _warmTripsAt = now;
    _warmTrips = tripCounter(driver);
  }

  static void forgetCompletedTrips() {
    _warmTrips = null;
    _warmTripsFor = null;
    _warmTripsAt = null;
  }

  static const Duration warmTripsFor = Duration(seconds: 60);
  static Future<num?>? _warmTrips;
  static String? _warmTripsFor;
  static DateTime? _warmTripsAt;

  static bool _isWarmFresh(DateTime now) => _warmTripsAt != null && now.difference(_warmTripsAt!) < warmTripsFor;

  /// The count itself; null when it could not be made. Swappable for tests.
  static Future<num?> Function(UserModel driver) tripCounter = _countCompletedTrips;

  static Future<num?> _countCompletedTrips(UserModel driver) async {
    try {
      final AggregateQuerySnapshot snapshot = await _fireStore
          .collection(CollectionName.ridesBooking)
          .where('driverId', isEqualTo: driver.id)
          .where('status', isEqualTo: Constant.orderCompleted)
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      log('completedTrips count failed: $e');
      return null;
    }
  }

  /// Builds the offer document, denormalising the fields the customer's card
  /// shows so that list needs one subscription and no extra reads.
  static Future<RideBidModel> buildBid({
    required CabOrderModel ride,
    required UserModel driver,
    required double amount,
    required String type,
    String? note,
  }) async {
    final String sectionId = ride.sectionId ?? '';
    final Map<String, dynamic> vehicle = (driver.vehicleDetails?[sectionId] is Map)
        ? Map<String, dynamic>.from(driver.vehicleDetails![sectionId] as Map)
        : <String, dynamic>{};

    return RideBidModel(
      id: driver.id,
      rideId: ride.id,
      driverId: driver.id,
      customerId: ride.authorID,
      amount: amount,
      type: type,
      status: RideBidStatus.pending,
      note: note,
      driverName: driver.fullName().trim(),
      driverPhoto: driver.profilePictureURL,
      driverRating: driver.averageRating,
      driverReviewsCount: num.tryParse(driver.reviewsCount ?? '0') ?? 0,
      driverCompletedTrips: await completedTrips(driver),
      vehicleType: vehicle['vehicleType']?.toString(),
      vehicleBrand: vehicle['carBrand']?.toString(),
      vehicleModel: vehicle['carModel']?.toString(),
      vehiclePlate: vehicle['carPlateNumber']?.toString(),
      airConditioning: vehicle['airConditioning'] is bool ? vehicle['airConditioning'] as bool : null,
    );
  }

  /// Submits (or replaces) this driver's offer, inside a transaction that
  /// re-reads the ride: an offer on a request that has just been won,
  /// cancelled or expired is refused by the database, not only by the button
  /// being hidden.
  static Future<SubmitBidResult> submitBid({
    required CabOrderModel ride,
    required UserModel driver,
    required double amount,
    required String type,
    String? note,
  }) async {
    final RideBidModel bid = await buildBid(ride: ride, driver: driver, amount: amount, type: type, note: note);
    SubmitBidResult result;
    try {
      result = await ledger.submitBid(
        bid: bid,
        settings: Constant.biddingSettings,
        now: DateTime.now(),
        currencyDecimals: currencyDecimals,
      );
    } catch (e, s) {
      log('submitBid transaction failed: $e\n$s');
      return SubmitBidResult.notOpen;
    }

    if (result == SubmitBidResult.ok) {
      final String? token = ride.author?.fcmToken;
      if (token != null && token.isNotEmpty) {
        // Sent, not waited for. The offer is already on the ride when the
        // transaction returns - that is what the customer's screen listens to -
        // but the driver's "Please wait" used to stay up until Google had also
        // accepted the push, which on the first send of a launch includes
        // fetching the service account and exchanging it for a token.
        unawaited(
          SendNotification.sendOneNotification(
            token: token,
            title: type == RideBidType.counter ? 'New counter offer' : 'A driver accepted your fare',
            body: '${driver.fullName().trim()}: ${Constant.amountShow(amount: amount.toString())}',
            payload: <String, dynamic>{'rideId': ride.id ?? '', 'type': Constant.newBidRequestNotification},
          ).catchError((Object e) {
            log('counter-offer notification failed: $e');
            return false;
          }),
        );
      }
    }
    return result;
  }

  /// Takes an offer back off the table.
  static Future<bool> withdrawBid({required String rideId}) async {
    try {
      return await ledger.withdrawBid(rideId: rideId, driverId: FireStoreUtils.getCurrentUid(), now: DateTime.now());
    } catch (e) {
      log('withdrawBid failed: $e');
      return false;
    }
  }
}
