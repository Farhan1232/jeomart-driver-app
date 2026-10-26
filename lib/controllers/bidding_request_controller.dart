import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/controllers/cab_dashboard_controller.dart';
import 'package:driver/models/ride_bid_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/services/bidding_service.dart';
import 'package:driver/utils/active_ride_selection.dart';
import 'package:driver/utils/bidding_fare_rules.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/ride_bid_ledger.dart';
import 'package:driver/utils/ride_bidding_state.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Drives the driver's bidding inbox: the requests they are eligible for, the
/// offer they have made on each, and what happens when one of those offers
/// wins.
///
/// Deliberately a separate controller from [CabHomeController]: while the
/// global bidding switch is off it opens no listener and holds no state, so
/// the existing ride flow is untouched.
class BiddingRequestController extends GetxController {
  final RxList<BiddingRequest> openRequests = <BiddingRequest>[].obs;

  /// This driver's own offer per ride id, so a card can show "your offer" and
  /// refuse a second submission.
  final RxMap<String, RideBidModel> myBids = <String, RideBidModel>{}.obs;

  /// Ride ids whose accept / counter / withdraw is in flight, so a duplicate
  /// tap cannot start a second transaction.
  final RxSet<String> inFlight = <String>{}.obs;

  final Rx<TextEditingController> counterOfferTextEditController = TextEditingController().obs;

  /// Whether the inbox is still waiting for its first snapshot.
  ///
  /// The compact view on the home screen never needed this - it draws nothing
  /// until there is something to draw. The Bid section does: without it the
  /// screen says "no ride offers" for the moment before the listener answers,
  /// which reads as *there is no work* rather than *we are still asking*.
  ///
  /// Written only from the snapshot callback, never from `start()`, because
  /// `start()` is called from a builder and writing an observable during build
  /// marks an already-built subtree dirty.
  final RxBool isLoading = true.obs;

  /// Whether this driver is already on a ride.
  ///
  /// [_onRequests] has always emptied the inbox for a busy driver - the same
  /// rule the ordinary dispatcher applies - but nothing said so. On the home
  /// screen that was invisible, because an empty inbox simply draws nothing.
  /// The Bid section has to tell the difference between *no offers* and *you
  /// are not being offered any because you are driving*.
  final RxBool isBusyOnRide = false.obs;

  /// The fleet owner whose wallet backs this driver, for [walletBlocker].
  ///
  /// The home screen's inbox gets this from `CabHomeController`, which holds a
  /// live listener on the owner's user document. The Bid section is a different
  /// drawer slot, so `CabHomeController` is not mounted while it is open and
  /// that value is not reachable.
  ///
  /// Opened **only for a driver who has an `ownerId`**. An owner-less driver -
  /// which is most of them - reads nothing here, and `walletBlocker` never
  /// looks at this value for them. Getting it wrong is not cosmetic: the blocker
  /// compares the *owner's* balance against the minimum deposit, so a default
  /// `UserModel()` with a null wallet would refuse every offer for a fleet
  /// driver whose owner is funded.
  final Rx<UserModel> owner = UserModel().obs;

  StreamSubscription<List<BiddingRequest>>? _requestsSub;

  /// Rides the customer has already awarded to this driver.
  ///
  /// See [BiddingService.wonRequestsStream]: this is what makes an acceptance
  /// arrive as a snapshot instead of waiting for the dispatcher's next sweep,
  /// and it survives the section being left and the app being restarted, which
  /// the per-submission [_rideSubs] entries do not.
  StreamSubscription<List<String>>? _wonSub;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _ownerSub;
  final Map<String, StreamSubscription<RideBidModel?>> _bidSubs = <String, StreamSubscription<RideBidModel?>>{};
  final Map<String, StreamSubscription<Map<String, dynamic>?>> _rideSubs = <String, StreamSubscription<Map<String, dynamic>?>>{};

  /// Rides this device has already handed to the normal ride flow, so a
  /// repeated snapshot does not re-run the hand-off.
  final Set<String> _claimed = <String>{};

  /// The latest inbox snapshot, so the busy rule can be re-applied to it when
  /// the driver's own document changes. Null until the first snapshot.
  List<BiddingRequest>? _lastRequests;

  /// Follows the driver's profile for [_watchProfile].
  Worker? _profileWorker;

  @override
  void onInit() {
    super.onInit();
    start();
  }

  @override
  void onClose() {
    _stopAll();
    super.onClose();
  }

  /// Opens the inbox listener, but only while bidding is switched on.
  void start() {
    if (!Constant.isBiddingEnabled) {
      _stopAll();
      return;
    }
    if (_requestsSub != null) return;
    _requestsSub = BiddingService.openRequestsStream(limit: Constant.biddingSettings.maxDriversPerRequest)
        .listen(_onRequests, onError: (Object error) => log('bidding requests listener error: $error'));
    _watchWins();
    _watchOwner();
    _watchProfile();
  }

  /// Re-applies the "already on a ride" rule when the driver's own document
  /// changes, not only when the inbox query does.
  ///
  /// [_onRequests] decided it from the profile at the moment an inbox
  /// snapshot arrived, and nothing asked again. A driver who finished a ride
  /// therefore kept seeing "you are on a ride" in the Bid section - with the
  /// open requests they were eligible for hidden - until some request happened
  /// to change. The cab dashboard already listens to that document; this only
  /// watches the value it keeps, and acts only when busy actually flips.
  void _watchProfile() {
    if (_profileWorker != null) return;
    if (!Get.isRegistered<CabDashBoardController>()) return;
    _profileWorker = ever<UserModel>(Get.find<CabDashBoardController>().userModel, (UserModel me) {
      final List<BiddingRequest>? requests = _lastRequests;
      if (requests == null) return;
      if (_isBusy(me) == isBusyOnRide.value) return;
      _onRequests(requests, me);
    });
  }

  static bool _isBusy(UserModel? me) => (me?.inProgressOrderID?.isNotEmpty ?? false) || me?.orderCabRequestData != null;

  /// Follows the rides this driver has been awarded.
  ///
  /// Opened alongside the inbox rather than at the moment an offer is
  /// submitted, so an acceptance that lands while the driver is on another
  /// screen - or while the app is being restarted - is still picked up the
  /// instant this controller exists.
  void _watchWins() {
    if (_wonSub != null) return;
    _wonSub = BiddingService.wonRequestsStream().listen(
      (List<String> rideIds) {
        for (final String rideId in rideIds) {
          if (rideId.isEmpty || _claimed.contains(rideId)) continue;
          _claimed.add(rideId);
          unawaited(_claimWonRide(rideId));
        }
      },
      onError: (Object error) => log('bidding wins listener error: $error'),
    );
  }

  /// Follows the fleet owner's wallet, for drivers who have one.
  ///
  /// One document, and only for a driver with an `ownerId`. Cancelled by
  /// [_stopAll] with everything else this controller opens.
  void _watchOwner() {
    if (_ownerSub != null) return;
    final String? ownerId = Constant.userModel?.ownerId;
    if (ownerId == null || ownerId.isEmpty) return;
    _ownerSub = FireStoreUtils.fireStore.collection(CollectionName.users).doc(ownerId).snapshots().listen(
      (DocumentSnapshot<Map<String, dynamic>> event) {
        final Map<String, dynamic>? data = event.data();
        if (data != null) owner.value = UserModel.fromJson(data);
      },
      onError: (Object error) => log('bidding owner listener error: $error'),
    );
  }

  void _stopAll() {
    _requestsSub?.cancel();
    _requestsSub = null;
    _wonSub?.cancel();
    _wonSub = null;
    _ownerSub?.cancel();
    _ownerSub = null;
    _profileWorker?.dispose();
    _profileWorker = null;
    _lastRequests = null;
    for (final StreamSubscription<RideBidModel?> sub in _bidSubs.values) {
      sub.cancel();
    }
    _bidSubs.clear();
    for (final StreamSubscription<Map<String, dynamic>?> sub in _rideSubs.values) {
      sub.cancel();
    }
    _rideSubs.clear();
    openRequests.clear();
    myBids.clear();
  }

  void _onRequests(List<BiddingRequest> requests, [UserModel? profile]) {
    _lastRequests = requests;
    isLoading.value = false;
    // A driver who is already on a ride must not be shown new requests, which
    // is the same rule the normal dispatcher applies before it offers a ride.
    final UserModel? me = profile ?? Constant.userModel;
    final bool busy = _isBusy(me);
    isBusyOnRide.value = busy;
    openRequests.value = busy ? <BiddingRequest>[] : requests;
    // The offer needs this driver's completed-trip count; start it now rather
    // than inside "Please wait" after the tap. See warmCompletedTrips.
    if (me != null) {
      if (busy) {
        BiddingService.forgetCompletedTrips();
      } else if (requests.isNotEmpty) {
        BiddingService.warmCompletedTrips(me);
      }
    }

    final Set<String> ids = openRequests.map((BiddingRequest r) => r.id).where((String id) => id.isNotEmpty).toSet();

    // Follow my own offer on each visible request.
    for (final String rideId in ids) {
      _bidSubs.putIfAbsent(
        rideId,
        () => BiddingService.myBidStream(rideId).listen((RideBidModel? bid) {
          if (bid == null) {
            myBids.remove(rideId);
          } else {
            myBids[rideId] = bid;
            // An offer that is still on the table is an offer whose outcome
            // this device has to be told about. [_watchRide] used to be opened
            // only by [_submit], so a bid made before the section was last left
            // - or before the app was last closed - was no longer being
            // followed, and the customer's decision reached the driver only
            // when the dispatcher next ran.
            if (bid.isLive) _watchRide(rideId);
          }
        }, onError: (Object error) => log('my bid listener error: $error')),
      );
    }

    // Drop listeners for requests that are no longer open to me, except the
    // ones I have a live offer on: those must stay watched until they are
    // decided, otherwise a win that arrives after the request leaves my query
    // would never reach this device.
    final List<String> stale = _bidSubs.keys.where((String id) => !ids.contains(id) && !_hasLiveBid(id)).toList();
    for (final String rideId in stale) {
      _bidSubs.remove(rideId)?.cancel();
      _rideSubs.remove(rideId)?.cancel();
      myBids.remove(rideId);
    }
  }

  bool _hasLiveBid(String rideId) => myBids[rideId]?.isLive == true;

  /// Watches one ride for the outcome of my offer.
  void _watchRide(String rideId) {
    _rideSubs.putIfAbsent(
      rideId,
      () => BiddingService.rideStream(rideId).listen((Map<String, dynamic>? data) => _onRideOutcome(rideId, data),
          onError: (Object error) => log('bidding ride listener error: $error')),
    );
  }

  Future<void> _onRideOutcome(String rideId, Map<String, dynamic>? data) async {
    if (data == null) return;
    final RideBiddingState state = RideBiddingState.fromJson(data);
    final String uid = FireStoreUtils.getCurrentUid();

    // A ride that has already ended is never handed to the ride flow: putting
    // it back on `inProgressOrderID` marked a free driver as busy.
    if (state.winningBidId == uid && !_claimed.contains(rideId) && !ActiveRideSelection.hasEnded(data['status'])) {
      _claimed.add(rideId);
      await _claimWonRide(rideId);
      return;
    }

    if (state.isFinished && state.winningBidId != uid) {
      // Lost, cancelled or expired: stop watching and drop it from the inbox.
      _rideSubs.remove(rideId)?.cancel();
      _bidSubs.remove(rideId)?.cancel();
      myBids.remove(rideId);
      openRequests.removeWhere((BiddingRequest r) => r.id == rideId);
    }
  }

  /// Hands a won ride to the normal ride flow.
  ///
  /// This performs the same local bookkeeping the driver-initiated
  /// `acceptOrder()` has always performed - the ride goes on
  /// `inProgressOrderID` and the pending-request slot is cleared - so from
  /// here on the ride is an ordinary booked ride and every existing screen,
  /// listener and status transition works unchanged.
  ///
  /// If the driver's app was closed when the customer accepted, the
  /// dispatcher performs the same reconciliation on its next run, so the ride
  /// is never left un-assigned.
  Future<void> _claimWonRide(String rideId) async {
    try {
      final UserModel? me = Constant.userModel;
      if (me == null) return;
      me.inProgressOrderID ??= <dynamic>[];
      // Already ours - the dispatcher reconciled it while the app was closed,
      // or another listener in this session got here first. Writing the same
      // document again would only cost a round trip and a redundant snapshot.
      if (me.inProgressOrderID!.contains(rideId)) {
        openRequests.clear();
        return;
      }
      if (!me.inProgressOrderID!.contains(rideId)) {
        me.inProgressOrderID!.add(rideId);
      }
      me.orderCabRequestData = null;
      await FireStoreUtils.updateUser(me);
      openRequests.clear();
      ShowToastDialog.showToast("Your offer was accepted".tr);
    } catch (e) {
      log('claiming won ride $rideId failed: $e');
    }
  }

  double minimumFareFor(BiddingRequest request) =>
      BiddingService.minimumAllowedFare(request.distanceKm, vehicleRatePerKm: request.vehicleRatePerKm);

  /// The one-tap raises offered on the counter-offer sheet.
  ///
  /// Deliberately a short, round set. They are additive, so any amount is
  /// reachable by tapping more than once, and the box stays typeable for
  /// anything else - the client's "50, 100 etc, any amount".
  static const List<num> quickRaises = <num>[20, 50, 100, 200];

  /// Adds [step] to whatever is in the counter-offer box.
  ///
  /// An empty or unparsable box is treated as the customer's own offer, which
  /// is what the sheet pre-fills, so the first tap always raises *their* number
  /// rather than starting from zero.
  void raiseCounterOffer(num step) {
    final double current = BiddingFareRules.parseAmount(counterOfferTextEditController.value.text) ?? 0;
    final double raised = current + step.toDouble();
    counterOfferTextEditController.value.text =
        BiddingFareRules.roundToCurrency(raised, BiddingService.currencyDecimals).toStringAsFixed(BiddingService.currencyDecimals);
    update();
  }

  /// The same wallet floor the existing accept button enforces. Returns null
  /// when the driver may bid, otherwise the message to show.
  String? walletBlocker({required UserModel driver, required UserModel owner}) {
    final double minimum = double.tryParse(Constant.minimumDepositToRideAccept) ?? 0;
    final bool hasOwner = driver.ownerId != null && driver.ownerId!.isNotEmpty;
    final num balance = hasOwner ? (owner.walletAmount ?? 0) : (driver.walletAmount ?? 0);
    if (balance >= minimum) return null;
    return hasOwner
        ? "Your owner has to maintain minimum {amount} wallet balance to accept the cab booking. Please contact your owner"
            .trParams(<String, String>{"amount": Constant.ownerMinimumDepositToRideAccept.toString()})
        : "You don't have sufficient balance in your wallet.".tr;
  }

  /// Accepts the customer's fare unchanged.
  Future<void> acceptOfferedFare(BiddingRequest request) =>
      _submit(request: request, amount: request.offeredFare.toDouble(), type: RideBidType.accept, note: null);

  /// Sends a counter offer, optionally with the driver's note.
  Future<void> sendCounterOffer(BiddingRequest request, {required bool withNote}) async {
    final double? amount = BiddingFareRules.parseAmount(counterOfferTextEditController.value.text);
    switch (BiddingService.checkFare(
      amount: amount,
      distanceKm: request.distanceKm,
      vehicleRatePerKm: request.vehicleRatePerKm,
    )) {
      case FareCheckResult.ok:
        break;
      case FareCheckResult.notANumber:
        ShowToastDialog.showToast("Enter your counter offer".tr);
        return;
      case FareCheckResult.notPositive:
        ShowToastDialog.showToast("The offered fare must be greater than zero".tr);
        return;
      case FareCheckResult.belowMinimum:
        ShowToastDialog.showToast("${'The minimum fare for this trip is'.tr} ${Constant.amountShow(amount: minimumFareFor(request).toString())}");
        return;
    }
    await _submit(
      request: request,
      amount: amount!,
      type: RideBidType.counter,
      note: withNote ? BiddingService.driverNoteKey : null,
    );
  }

  Future<void> _submit({required BiddingRequest request, required double amount, required String type, String? note}) async {
    final String rideId = request.id;
    if (rideId.isEmpty || inFlight.contains(rideId)) return;
    final UserModel? me = Constant.userModel;
    if (me == null) return;

    inFlight.add(rideId);
    ShowToastDialog.showLoader("Please wait".tr);
    try {
      final SubmitBidResult result = await BiddingService.submitBid(
        ride: request.ride,
        driver: me,
        amount: amount,
        type: type,
        note: note,
      );
      ShowToastDialog.closeLoader();
      switch (result) {
        case SubmitBidResult.ok:
          _watchRide(rideId);
          counterOfferTextEditController.value.clear();
          ShowToastDialog.showToast("Offer sent".tr);
          break;
        case SubmitBidResult.notOpen:
        case SubmitBidResult.rideGone:
          ShowToastDialog.showToast("This ride request is no longer open".tr);
          openRequests.removeWhere((BiddingRequest r) => r.id == rideId);
          break;
        case SubmitBidResult.requestExpired:
          ShowToastDialog.showToast("This ride request has expired".tr);
          openRequests.removeWhere((BiddingRequest r) => r.id == rideId);
          break;
        case SubmitBidResult.notEligible:
          ShowToastDialog.showToast("You are no longer eligible for this ride".tr);
          openRequests.removeWhere((BiddingRequest r) => r.id == rideId);
          break;
        case SubmitBidResult.invalidAmount:
          ShowToastDialog.showToast("The offered fare must be greater than zero".tr);
          break;
        case SubmitBidResult.belowMinimum:
          ShowToastDialog.showToast("${'The minimum fare for this trip is'.tr} ${Constant.amountShow(amount: minimumFareFor(request).toString())}");
          break;
      }
    } finally {
      inFlight.remove(rideId);
    }
  }

  /// Withdraws this driver's offer on [request].
  Future<void> withdraw(BiddingRequest request) async {
    final String rideId = request.id;
    if (rideId.isEmpty || inFlight.contains(rideId)) return;
    inFlight.add(rideId);
    // The same "Please wait" every other button on this card shows. Withdrawing
    // is a network round trip, and without it the card sat there looking
    // untouched until the toast arrived.
    ShowToastDialog.showLoader("Please wait".tr);
    try {
      final bool done = await BiddingService.withdrawBid(rideId: rideId);
      ShowToastDialog.closeLoader();
      ShowToastDialog.showToast(done ? "Offer withdrawn".tr : "This offer is no longer available".tr);
    } finally {
      ShowToastDialog.closeLoader();
      inFlight.remove(rideId);
    }
  }

  /// True when the request's own deadline has passed on this device's clock.
  bool isExpired(BiddingRequest request) => request.state.isExpiredAt(DateTime.now());
}
