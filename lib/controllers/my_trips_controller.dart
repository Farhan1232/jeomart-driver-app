import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/models/driver_trip_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/services/driver_trip_service.dart';
import 'package:driver/utils/driver_trip_ledger.dart';
import 'package:driver/utils/driver_trip_state.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/firestore_paginator.dart';
import 'package:get/get.dart';

/// The driver's own posted trips.
///
/// Paginated with Session 1's `FirestorePaginator`, exactly like the ride,
/// parcel and rental history screens: the first page stays live so a trip the
/// driver has just published appears immediately, older pages load on scroll,
/// and the status tabs filter what is already loaded rather than changing the
/// query.
class MyTripsController extends GetxController {
  RxBool isLoading = true.obs;

  /// Tabs, in the order the screen shows them.
  ///
  /// [DriverTripStatus.all], rather than a copy of it, so a status can never
  /// exist without a tab to land in: `tripsForTab` matches on equality, and a
  /// trip whose status no tab claims is simply not drawn anywhere. That is what
  /// would happen to a `completed` trip against a hand-written four-entry list.
  final List<String> tabKeys = DriverTripStatus.all;

  RxString selectedTab = DriverTripStatus.active.obs;

  FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, DriverTripModel>? tripsPaginator;

  /// Whether the driver may still use this screen. Watched by the screen so a
  /// grant that runs out while it is open closes it instead of leaving the
  /// driver on a page that cannot do anything.
  RxBool hasAccess = false.obs;

  List<DriverTripModel> get trips => tripsPaginator?.items ?? <DriverTripModel>[];

  bool get isLoadingMore => tripsPaginator?.isLoadingMore.value ?? false;

  bool get hasMoreTrips => tripsPaginator?.hasMore.value ?? false;

  /// Whether the paginator is still topping the list up to its target.
  ///
  /// The list can be empty *and* still filling — the first page has landed but
  /// none of its rows match the selected tab. Screens use this so an empty tab
  /// shows a loader rather than "No orders found" over rows that are on the way.
  bool get isToppingUp => tripsPaginator?.isToppingUp.value ?? false;


  /// Guards a cancel while its transaction is in flight, so a double tap
  /// cannot fire two.
  RxString cancelInFlight = ''.obs;

  /// The same guard for Complete Ride. Separate from [cancelInFlight] so a trip
  /// being completed does not also disable Cancel on every other card.
  RxString completeInFlight = ''.obs;

  /// Whether either write is in flight for this trip, which is what both of its
  /// buttons check - completing and cancelling the same trip at once is the one
  /// combination that must not be offered.
  bool isBusy(DriverTripModel trip) {
    final String id = trip.id ?? '';
    if (id.isEmpty) return false;
    return cancelInFlight.value == id || completeInFlight.value == id;
  }

  /// The reserving customer's contact block, keyed by trip id.
  ///
  /// The details live in `driver_trips/{tripId}/reservation/{customerId}`, not
  /// on the trip document every browsing customer reads. They were being
  /// written all along and never read back, which is why a booked trip showed
  /// the customer's name and nothing to reach them with.
  final RxMap<String, TripReservationModel> reservations = <String, TripReservationModel>{}.obs;

  /// Trip ids already fetched or in flight, so the live first page rebuilding
  /// cannot queue the same read again.
  final Set<String> _reservationsRequested = <String>{};

  Worker? _itemsWorker;

  TripReservationModel? reservationFor(DriverTripModel trip) => reservations[trip.id ?? ''];

  @override
  void onInit() {
    super.onInit();
    refreshAccess();
    load();
  }

  @override
  void onClose() {
    _itemsWorker?.dispose();
    tripsPaginator?.dispose();
    super.onClose();
  }

  /// Fetches the contact block for every booked trip that does not have one.
  ///
  /// One read per booked trip, once. A trip nobody has taken has nothing to
  /// read, so an inbox full of active trips costs nothing extra.
  Future<void> loadReservations() async {
    final List<DriverTripModel> pending = trips
        .where((DriverTripModel trip) =>
            trip.hasReservation &&
            (trip.id ?? '').isNotEmpty &&
            !_reservationsRequested.contains(trip.id))
        .toList();
    if (pending.isEmpty) return;

    for (final DriverTripModel trip in pending) {
      _reservationsRequested.add(trip.id!);
    }

    final List<TripReservationModel?> loaded = await Future.wait(
      pending.map((DriverTripModel trip) => DriverTripService.reservationFor(trip)),
    );

    final Map<String, TripReservationModel> found = <String, TripReservationModel>{};
    for (int i = 0; i < pending.length; i++) {
      final TripReservationModel? reservation = loaded[i];
      if (reservation != null) found[pending[i].id!] = reservation;
      // A read that came back empty is left out of `_reservationsRequested`'s
      // effect deliberately: it stays marked, so a permanently missing
      // document is not retried on every rebuild.
    }
    if (found.isNotEmpty) reservations.addAll(found);
  }

  /// The signed-in driver, for the chat header and the sender id.
  ///
  /// `Constant.userModel` is kept current by the dashboard's live listener, so
  /// this almost always answers from memory; the profile read is the fallback
  /// for a screen opened before that listener has delivered.
  Future<UserModel?> currentUser() async {
    final UserModel? cached = Constant.userModel;
    if (cached != null && (cached.id ?? '').isNotEmpty) return cached;
    final String uid = FireStoreUtils.getCurrentUid();
    if (uid.isEmpty) return null;
    return FireStoreUtils.getUserProfile(uid);
  }

  /// Re-reads the grant from the driver's own user document.
  bool refreshAccess() {
    hasAccess.value = Constant.hasMyTripsAccess;
    return hasAccess.value;
  }

  /// The trips of the selected tab.
  ///
  /// A trip whose window closed but whose status the maintenance sweep has not
  /// flipped yet is shown under Expired, not under Active, so the driver never
  /// sees a trip advertised as live that customers can no longer find.
  List<DriverTripModel> tripsForTab(String tab) {
    final DateTime now = DateTime.now();
    return trips.where((DriverTripModel trip) => trip.effectiveStatusAt(now) == tab).toList();
  }

  bool Function(DriverTripModel) _filterFor(String tab) {
    return (DriverTripModel trip) => trip.effectiveStatusAt(DateTime.now()) == tab;
  }

  Future<void> selectTab(String tab) async {
    selectedTab.value = tab;
    await tripsPaginator?.applyFilter(_filterFor(tab));
  }

  Future<void> loadMoreTrips() async => tripsPaginator?.loadMore();

  Future<void> refreshTrips() async {
    refreshAccess();
    await tripsPaginator?.refresh();
    await loadReservations();
  }

  Future<void> load() async {
    isLoading.value = true;
    final String uid = FireStoreUtils.getCurrentUid();
    // No grant, no query. The screen renders an explanation instead, so there
    // is nothing for a page of trips to be shown in.
    if (uid.isEmpty || !refreshAccess()) {
      isLoading.value = false;
      return;
    }

    tripsPaginator?.dispose();
    final FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, DriverTripModel> paginator =
        FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, DriverTripModel>(
      source: FirestorePageSource(DriverTripService.myTripsQuery(uid), live: true),
      mapper: (DocumentSnapshot<Map<String, dynamic>> doc) {
        final Map<String, dynamic>? data = doc.data();
        if (data == null) return null;
        try {
          return DriverTripModel.fromJson(data);
        } catch (error) {
          log('MyTripsController: skipping trip ${doc.id} :: $error');
          return null;
        }
      },
      pageSize: 20,
      autoFillTarget: 10,
      filter: _filterFor(selectedTab.value),
    );
    tripsPaginator = paginator;
    _itemsWorker?.dispose();
    // The first page stays live, so a booking that arrives while the driver is
    // looking at the screen has to pull its contact block in too.
    _itemsWorker = ever<List<DriverTripModel>>(paginator.items, (_) => loadReservations());
    // The first page paints as soon as it lands; the top-up to
    // `autoFillTarget` continues behind the list instead of holding this
    // screen on a spinner through up to five more sequential reads.
    await paginator.refresh(awaitAutoFill: false);
    await loadReservations();

    isLoading.value = false;
  }

  /// Marks one of the driver's own booked trips as finished.
  ///
  /// The write is the same status and field the server sweep writes, so the
  /// trip moves to the Completed tab here and to the customer's Completed tab
  /// with nothing new for either app to interpret. The refresh afterwards is
  /// what moves the card out of Booked without the driver reopening the screen.
  Future<void> completeTrip(DriverTripModel trip) async {
    final String tripId = trip.id ?? '';
    if (tripId.isEmpty || isBusy(trip)) return;
    completeInFlight.value = tripId;
    ShowToastDialog.showLoader("Please wait".tr);
    try {
      final CompleteTripResult result = await DriverTripService.completeTrip(trip);
      ShowToastDialog.closeLoader();
      switch (result) {
        case CompleteTripResult.ok:
          // Told after the state is settled, never before: the customer's
          // history is what the notification points at.
          await DriverTripService.notifyReservationCompleted(trip);
          ShowToastDialog.showToast("Ride completed".tr);
          await tripsPaginator?.refresh();
          break;
        case CompleteTripResult.tripGone:
          ShowToastDialog.showToast("This trip is no longer available".tr);
          await tripsPaginator?.refresh();
          break;
        case CompleteTripResult.notOwner:
          ShowToastDialog.showToast("This trip belongs to another driver".tr);
          break;
        case CompleteTripResult.alreadyFinished:
          // Includes the sweep having got there first, which is not the
          // driver's problem - refreshing shows them the trip already done.
          ShowToastDialog.showToast("This trip has already ended".tr);
          await tripsPaginator?.refresh();
          break;
        case CompleteTripResult.notBooked:
          ShowToastDialog.showToast("Only a booked trip can be completed".tr);
          await tripsPaginator?.refresh();
          break;
      }
    } catch (error) {
      ShowToastDialog.closeLoader();
      log('MyTripsController.completeTrip failed :: $error');
      ShowToastDialog.showToast("Something went wrong. Please try again.".tr);
    } finally {
      completeInFlight.value = '';
    }
  }

  /// Withdraws one of the driver's own trips.
  Future<void> cancelTrip(DriverTripModel trip) async {
    final String tripId = trip.id ?? '';
    if (tripId.isEmpty || isBusy(trip)) return;
    cancelInFlight.value = tripId;
    ShowToastDialog.showLoader("Please wait".tr);
    try {
      final bool hadReservation = trip.hasReservation;
      final CancelTripResult result = await DriverTripService.cancelTrip(trip);
      ShowToastDialog.closeLoader();
      switch (result) {
        case CancelTripResult.ok:
          if (hadReservation) {
            await DriverTripService.notifyReservationCancelled(trip);
          }
          ShowToastDialog.showToast("Trip cancelled".tr);
          await tripsPaginator?.refresh();
          break;
        case CancelTripResult.tripGone:
          ShowToastDialog.showToast("This trip is no longer available".tr);
          await tripsPaginator?.refresh();
          break;
        case CancelTripResult.notOwner:
          ShowToastDialog.showToast("This trip belongs to another driver".tr);
          break;
        case CancelTripResult.alreadyFinished:
          ShowToastDialog.showToast("This trip has already ended".tr);
          await tripsPaginator?.refresh();
          break;
      }
    } catch (error) {
      ShowToastDialog.closeLoader();
      log('MyTripsController.cancelTrip failed :: $error');
      ShowToastDialog.showToast("Something went wrong. Please try again.".tr);
    } finally {
      cancelInFlight.value = '';
    }
  }
}
