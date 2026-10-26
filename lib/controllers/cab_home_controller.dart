import 'dart:async';

import 'package:driver/utils/driver_verification_gate.dart';
import 'package:driver/utils/driver_map_location.dart';
import 'package:driver/utils/active_ride_selection.dart';
import 'dart:convert';
import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:driver/utils/app_image_cache.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/app/wallet_screen/payment_list_screen.dart';
import 'package:driver/controllers/cab_dashboard_controller.dart';
import 'package:driver/utils/cab_bottom_navigation.dart';
import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/send_notification.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/models/cab_order_model.dart';
import 'package:driver/models/section_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/models/wallet_transaction_model.dart';
import 'package:driver/services/audio_player_service.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/network_timeout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as flutterMap;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as location;

class CabHomeController extends GetxController {
  RxBool isLoading = true.obs;
  flutterMap.MapController osmMapController = flutterMap.MapController();
  RxList<flutterMap.Marker> osmMarkers = <flutterMap.Marker>[].obs;

  /// Everything that decides where this screen's map looks.
  ///
  /// [mapCentre] holds a point until the map exists to receive it;
  /// [mapLocation] produces the points and keeps producing them. Between them
  /// they replace a single un-retried GPS call and a set of `?? 0.0` reads that
  /// turned "no location yet" into the middle of the Atlantic.
  late final DriverMapCentre mapCentre = DriverMapCentre(
    osmMapController,
    onGoogleCamera: _moveGoogleCamera,
  );
  late final DriverMapLocation mapLocation = DriverMapLocation(onFix: _onMapFix);

  /// The coordinate the map is *built* on.
  ///
  /// `MapOptions.initialCenter` is read exactly once, so this has to be a plain
  /// getter and not a reactive read: taking `current.value` here subscribed the
  /// whole screen to every GPS tick, and still could not recentre the map after
  /// the first frame. Moving the camera is [mapCentre]'s job now.
  location.LatLng get initialMapCentre => mapCentre.lastPoint ?? _mapSeed ?? _unknownCentre;

  /// Street zoom once we know where the driver is, and a wide one when we do
  /// not — an honest "still finding you" rather than a confident wrong street.
  double get initialMapZoom => (mapCentre.lastPoint ?? _mapSeed) != null ? 16 : 4;

  location.LatLng? _mapSeed;

  /// Only ever reached on a first launch that has no saved position, no cached
  /// fix and no location on the driver's own document.
  static final location.LatLng _unknownCentre = location.LatLng(21.1800, 72.8400);

  /// Wired to `MapOptions.onMapReady`.
  void onMapReady() => mapCentre.mapReady();

  /// Default driver icon loaded from local asset — shown when no section icon is available.
  BitmapDescriptor? _defaultDriverIcon;

  /// Cached section-specific icon so we don't re-download on every GPS update.
  String? _cachedIconUrl;
  BitmapDescriptor? _cachedSectionIcon;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _orderDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _orderQuerySub;

  /// The owner's profile listener, for a driver who belongs to a fleet.
  ///
  /// It was opened without being held on to, so nothing could cancel it: every
  /// time this screen was entered a fleet driver gained another permanent
  /// listener on the owner's `users` document, and the wallet banner at the top
  /// of the home screen was redrawn once per listener per change.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _ownerSub;

  @override
  void onInit() {
    getData();
    super.onInit();
  }

  @override
  void onClose() {
    _driverSub?.cancel();
    _ownerSub?.cancel();
    _orderDocSub?.cancel();
    _orderQuerySub?.cancel();
    mapLocation.dispose();
    super.onClose();
  }

  SectionModel? get _activeSectionModel {
    final sid = (currentOrder.value.sectionId?.isNotEmpty == true)
        ? currentOrder.value.sectionId
        : (driverModel.value.orderCabRequestData?.sectionId?.isNotEmpty == true)
            ? driverModel.value.orderCabRequestData!.sectionId
            : driverModel.value.sectionIds?.isNotEmpty == true
                ? driverModel.value.sectionIds!.first
                : null;
    return Constant.sectionModelFor(sid);
  }

  Future<void> getData() async {
    // Resolved before `isLoading` drops, because that is the frame the map is
    // built in and `initialCenter` is read once. Everything here is in memory
    // or on disk already; nothing waits on the GPS or on Firestore.
    _mapSeed = mapLocation.seed() ?? realMapPoint(Constant.userModel?.location);
    _subscribeDriver();
    unawaited(mapLocation.start());
    _loadDefaultIcon();
    isLoading.value = false;
  }

  Future<void> _loadDefaultIcon() async {
    _defaultDriverIcon = await _bitmapDescriptorFromAsset('assets/images/ic_cab.png', width: 120);
  }

  /// Returns the driver icon for Google Maps.
  /// Uses the active section's network icon if available (cached), otherwise the default asset icon.
  Future<BitmapDescriptor> _getDriverIcon() async {
    final iconUrl = _activeSectionModel?.markerIcon;
    if (iconUrl != null && iconUrl.isNotEmpty) {
      if (iconUrl != _cachedIconUrl || _cachedSectionIcon == null) {
        _cachedIconUrl = iconUrl;
        _cachedSectionIcon = await _bitmapDescriptorFromUrl(iconUrl, width: 120);
      }
      return _cachedSectionIcon!;
    }
    return _defaultDriverIcon ?? BitmapDescriptor.defaultMarker;
  }

  /// Returns the driver marker child widget for OSM.
  /// Shows asset icon immediately; section network icon only when a valid URL exists.
  Widget _driverMarkerWidget() {
    final iconUrl = _activeSectionModel?.markerIcon;
    if (iconUrl != null && iconUrl.isNotEmpty) {
      return CachedNetworkImage(
          cacheManager: AppImageCache.manager,
        imageUrl: iconUrl,
        width: 45,
        height: 45,
        fit: BoxFit.contain,
        placeholder: (_, __) => Image.asset('assets/images/ic_cab.png', width: 45, height: 45),
        errorWidget: (_, __, ___) => Image.asset('assets/images/ic_cab.png', width: 45, height: 45),
      );
    }
    return Image.asset('assets/images/ic_cab.png', width: 45, height: 45);
  }

  /// Every position the map is given, from the disk seed to each live fix.
  ///
  /// One entry point on purpose: the marker, the camera and `current` used to
  /// be updated from five different places, three of which could write `0, 0`.
  void _onMapFix(location.LatLng point) {
    current.value = point;
    mapCentre.moveTo(point);
    setOsmMapMarker();
    update();
  }

  /// Google Maps keeps its own camera, so [mapCentre] moves it alongside.
  void _moveGoogleCamera(location.LatLng point) {
    try {
      mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(point.latitude, point.longitude), zoom: 16),
        ),
      );
    } catch (error) {
      log('CabHomeController: google camera not ready :: $error');
    }
  }

  Rx<CabOrderModel> currentOrder = CabOrderModel().obs;
  Rx<UserModel> driverModel = UserModel().obs;
  Rx<UserModel> ownerModel = UserModel().obs;

  /// Whether the "Document Verification in Pending" screen should show, kept
  /// in step with the live driver document so the home screen switches to the
  /// map the moment the admin approves - it used to wait for an app restart.
  /// Null until the first snapshot, when the screen falls back to the profile
  /// loaded at launch.
  final RxnBool awaitsDocumentVerification = RxnBool();

  /// Takes the ride.
  ///
  /// The order the three side effects happen in is the whole of what the
  /// customer experiences as "accept is slow". It used to be:
  ///
  ///   stop the ringtone -> **write this driver's user document** -> write the
  ///   ride -> close the loader -> **send the push**, awaited.
  ///
  /// Only the second of those is what the customer's screen is listening to.
  /// `updateUser` is two round trips of its own (a `set` and an `update`), so
  /// the ride - the one document that tells the customer they have a driver -
  /// was written third, and the driver's own spinner was then held open past it
  /// for an FCM send that nobody on either screen is waiting for. The ride is
  /// written first now, the driver's document goes out alongside it rather than
  /// in front of it, and the push follows on its own.
  Future<void> acceptOrder() async {
    try {
      // Stopping the ringtone is a platform call; it is not something the
      // acceptance should be queued behind.
      unawaited(AudioPlayerService.playSound(false));
      ShowToastDialog.showLoader("Please wait".tr);

      final CabOrderModel order = currentOrder.value;

      driverModel.value.inProgressOrderID ??= [];
      if (!driverModel.value.inProgressOrderID!.contains(order.id)) {
        driverModel.value.inProgressOrderID!.add(order.id);
      }
      driverModel.value.orderCabRequestData = null;

      order.status = Constant.driverAccepted;
      order.driverId = driverModel.value.id;
      order.driver = driverModel.value;

      // Started together, not one behind the other.
      final Future<bool> profileWrite = FireStoreUtils.updateUser(driverModel.value);
      final bool written = await FireStoreUtils.setCabOrder(order);

      currentOrder.refresh();
      ShowToastDialog.closeLoader();

      if (!written) {
        ShowToastDialog.showToast("Something went wrong. Please try again.");
        return;
      }

      // Both of these are already on their way; neither has a screen waiting
      // on it. `unawaited` here is what keeps the tap from being charged for
      // an OAuth exchange and an FCM round trip.
      unawaited(profileWrite);
      unawaited(SendNotification.sendFcmMessage(Constant.driverAcceptedNotification, order.author?.fcmToken ?? "", {}));
    } catch (e, s) {
      ShowToastDialog.closeLoader();
      debugPrint("Error in acceptOrder: $e");
      debugPrintStack(stackTrace: s);
      ShowToastDialog.showToast("Something went wrong. Please try again.");
    }
  }

  Future<void> rejectOrder() async {
    try {
      unawaited(AudioPlayerService.playSound(false));

      // 1️⃣ Immediately update local state (UI)
      currentOrder.value.status = Constant.driverRejected;

      currentOrder.value.rejectedByDrivers ??= [];
      if (!currentOrder.value.rejectedByDrivers!.contains(driverModel.value.id)) {
        currentOrder.value.rejectedByDrivers!.add(driverModel.value.id);
      }

      // Immediately update UI so bottom sheet hides right away
      currentOrder.refresh();

      // 2️⃣ Update driver local state right away
      driverModel.value.orderCabRequestData = null;
      driverModel.value.inProgressOrderID = [];

      // 3️⃣ Both writes leave now, together, and neither is waited on. The
      // ride carries `rejectedByDrivers`, which is what lets the dispatcher
      // offer it straight to the next driver; the user document frees this
      // one. Awaiting the profile write here - which is two round trips - was
      // holding the bottom sheet open on screen after the driver had already
      // said no.
      unawaited(FireStoreUtils.setCabOrder(currentOrder.value));
      unawaited(FireStoreUtils.updateUser(driverModel.value));

      // 4️⃣ Close bottom sheet immediately (don’t wait for Firestore)
      if (Get.isBottomSheetOpen ?? false) {
        Get.back();
      } else if (Constant.singleOrderReceive == false) {
        Get.back();
      }

      // 5️⃣ Clear map immediately
      unawaited(clearMap());

      // 6️⃣ Reset local current order after short delay
      Future.delayed(const Duration(milliseconds: 300), () {
        currentOrder.value = CabOrderModel();
      });
    } catch (e, s) {
      print("rejectOrder() error: $e\n$s");
    }
  }

  bool get shouldShowOrderSheet {
    final status = currentOrder.value.status;
    // orderPlaced & driverPending = waiting for accept/reject → don't show ride actions card
    return currentOrder.value.id != null &&
        ![
          Constant.orderPlaced,
          Constant.driverPending,
          Constant.driverRejected,
          Constant.orderCompleted,
          Constant.orderCancelled,
        ].contains(status);
  }

  Future<void> clearMap() async {
    await AudioPlayerService.playSound(false);
    if (Constant.selectedMapType != 'osm') {
      markers.clear();
      polyLines.clear();
    } else {
      osmMarkers.clear();
      routePoints.clear();
    }
    update();
  }

  Future<void> onRideStatus() async {
    unawaited(AudioPlayerService.playSound(false));
    ShowToastDialog.showLoader("Please wait".tr);
    final String? statusBefore = currentOrder.value.status;
    currentOrder.value.status = Constant.orderInTransit;
    final bool written = await FireStoreUtils.setCabOrder(currentOrder.value);
    ShowToastDialog.closeLoader();
    // A ride that could not be started used to close the passenger dialog as
    // if it had, with the customer's app still waiting for pickup. The dialog
    // now stays up, so Start Ride can simply be tapped again.
    if (!written) {
      currentOrder.value.status = statusBefore;
      ShowToastDialog.showToast("Something went wrong. Please try again.".tr);
      return;
    }
    Get.back();
  }

  /// Completes the ride.
  ///
  /// The writes, and the order they are made in, are exactly what they were:
  /// the driver's wallet credit and the commission, the first-order referral,
  /// then the ride's `Order Completed`, then the driver's own document. Money
  /// still goes first, so a completion that is interrupted can never leave a
  /// completed ride with nothing booked against it.
  ///
  /// Two things are new, and neither touches a balance:
  ///
  ///  * **One completion per ride.** The blocking loader was the only thing in
  ///    the way of a second tap, and its 30 s watchdog takes it down on a slow
  ///    connection while the chain is still running - a second tap then ran
  ///    the whole completion again, wallet credit included.
  ///  * **The screen lets go of the ride as soon as `Order Completed` is
  ///    written**, instead of relying on the ride listener to echo the write
  ///    back and on the driver's document being saved after it. If that
  ///    listener had been dropped or was following something else, the
  ///    finished ride stayed on screen until the app was restarted.
  Future<void> completeRide() async {
    final String? rideId = currentOrder.value.id;
    if (rideId == null) return;
    if (_completingRideId == rideId) {
      log('completeRide: ride $rideId is already being completed; ignoring the repeated tap.');
      return;
    }
    _completingRideId = rideId;
    try {
      ShowToastDialog.showLoader("Please wait".tr);
      await updateCabWalletAmount(currentOrder.value);

      await FireStoreUtils.getFirestOrderOrNOtCabService(currentOrder.value).then((value) async {
        if (value == true) {
          await FireStoreUtils.updateReferralAmountCabService(currentOrder.value);
        }
      });

      currentOrder.value.status = Constant.orderCompleted;
      driverModel.value.inProgressOrderID = [];
      driverModel.value.orderCabRequestData = null;
      final bool rideWritten = await FireStoreUtils.setCabOrder(currentOrder.value);
      if (!rideWritten) {
        // Unchanged behaviour on purpose - the driver is still released below,
        // as before. Retrying here would run the wallet writes a second time.
        log('completeRide: ride $rideId could not be marked completed; see the setCabOrder error above.');
      }

      _endRideOnScreen(rideId);

      await FireStoreUtils.updateUser(driverModel.value);

      ShowToastDialog.closeLoader();
    } catch (e) {
      ShowToastDialog.closeLoader();
      log("Error in completeRide(): $e");
    } finally {
      _completingRideId = null;
    }
  }

  Future<void> updateCabWalletAmount(CabOrderModel orderModel) async {
    try {
      double totalTax = 0.0;
      double discount = 0.0;
      double subTotal = 0.0;
      double adminComm = 0.0;
      double totalAmount = 0.0;

      subTotal = double.tryParse(orderModel.subTotal ?? '0.0') ?? 0.0;
      discount = double.tryParse(orderModel.discount ?? '0.0') ?? 0.0;

      if (orderModel.taxSetting != null) {
        for (var element in orderModel.taxSetting!) {
          totalTax += Constant.calculateTax(amount: subTotal.toString(), taxModel: element);
        }
      }

      if ((orderModel.adminCommission ?? '').isNotEmpty) {
        adminComm = Constant.calculateAdminCommission(
            amount: (subTotal - discount).toString(), adminCommissionType: orderModel.adminCommissionType.toString(), adminCommission: orderModel.adminCommission ?? '0');
      }
      totalAmount = (subTotal + totalTax) - discount;

      final ownerId = orderModel.driver?.ownerId;
      final userIdForWallet = (ownerId != null && ownerId.isNotEmpty) ? ownerId : FireStoreUtils.getCurrentUid();

      if (orderModel.paymentMethod.toString() != PaymentGateway.cod.name) {
        WalletTransactionModel transactionModel = WalletTransactionModel(
            id: Constant.getUuid(),
            amount: totalAmount,
            date: Timestamp.now(),
            paymentMethod: orderModel.paymentMethod ?? '',
            transactionUser: "driver",
            userId: userIdForWallet,
            isTopup: true,
            orderId: orderModel.id,
            note: "Booking amount credited",
            paymentStatus: "success");

        final setTx = await FireStoreUtils.setWalletTransaction(transactionModel);
        if (setTx == true) {
          await FireStoreUtils.updateUserWallet(amount: totalAmount.toString(), userId: userIdForWallet);
        }
      }

      WalletTransactionModel adminTx = WalletTransactionModel(
          id: Constant.getUuid(),
          amount: adminComm,
          date: Timestamp.now(),
          paymentMethod: orderModel.paymentMethod ?? '',
          transactionUser: "driver",
          userId: userIdForWallet,
          isTopup: false,
          orderId: orderModel.id,
          note: "Admin commission deducted",
          paymentStatus: "success");

      final setAdmin = await FireStoreUtils.setWalletTransaction(adminTx);
      if (setAdmin == true) {
        await FireStoreUtils.updateUserWallet(amount: "-${adminComm.toString()}", userId: userIdForWallet);
      }
    } catch (e) {
      log("Error in updateCabWalletAmount(): $e");
    }
  }

  /// The ride [_orderDocSub] is following.
  ///
  /// Without it, [getCurrentOrder] cancelled and re-opened the ride listener on
  /// **every** snapshot of the driver's own user document - and that document
  /// is written on every location update, every accept, every reject. Each
  /// rebuild threw away a listener that was already delivering and waited on a
  /// fresh round trip for the first snapshot of its replacement, so a status
  /// change that landed during the gap reached the screen late. The ride the
  /// driver is on almost never changes while any of that is happening, so the
  /// listener is now opened once per ride and left alone.
  String? _watchedRideId;

  /// Rides this screen has seen end - completed, cancelled or rejected - so
  /// one that turns up on the driver's document again is recognised as over.
  /// See [ActiveRideSelection.select].
  final Set<String> _endedRideIds = <String>{};

  /// The ride [completeRide] is in the middle of completing.
  String? _completingRideId;

  Future<void> getCurrentOrder() async {
    try {
      final pendingRequest = driverModel.value.orderCabRequestData;

      final ActiveRideSelection selection = ActiveRideSelection.select(
        inProgress: driverModel.value.inProgressOrderID,
        pendingRequestId: pendingRequest?.id?.toString(),
        endedRideIds: _endedRideIds,
      );
      if (selection.endedStillListed.isNotEmpty) {
        _dropEndedRides(selection.endedStillListed);
      }
      final String? id = selection.rideId;

      // Already following this ride: nothing to rebuild.
      if (id != null && id == _watchedRideId && _orderDocSub != null) return;

      // No ride, and there was no ride last time either. This runs on every
      // location update, so clearing an already-clear map and redrawing the
      // screen for it is work the driver pays for and never sees.
      if (id == null && _watchedRideId == null && _orderDocSub == null && currentOrder.value.id == null) return;

      await _orderDocSub?.cancel();
      await _orderQuerySub?.cancel();
      _orderDocSub = null;
      _orderQuerySub = null;
      _watchedRideId = id;

      if (id != null) {
        // Show the order from the copy the dispatcher left on this driver's own
        // document, so the accept/reject sheet appears without waiting for the
        // Firestore snapshot.
        if (currentOrder.value.id == null && pendingRequest != null && pendingRequest.id?.toString() == id) {
          currentOrder.value = pendingRequest;
          changeData();
          update();
        }
        _orderDocSub = FireStoreUtils.fireStore.collection(CollectionName.ridesBooking).doc(id).snapshots().listen(
          (docSnap) => _handleOrderDoc(docSnap, id),
          // An error ends a Firestore subscription for good. Now that this one
          // is opened once per ride instead of once per snapshot of the
          // driver's own document, nothing else would ever put it back - so
          // forgetting which ride it was following is what lets the next
          // driver snapshot open a new one.
          onError: (Object error) {
            log('ride listener for $id failed :: $error');
            _watchedRideId = null;
            _orderDocSub?.cancel();
            _orderDocSub = null;
          },
        );
        return;
      }

      currentOrder.value = CabOrderModel();
      _routeKey = null;
      unawaited(clearMap());
      update();
    } catch (e) {
      log("getCurrentOrder() error: $e");
    }
  }

  /// Stops following ride [id], which has ended, and remembers that it did.
  ///
  /// The branches that handle an ended ride used to clear the screen but keep
  /// the ride listener and [_watchedRideId]. If the driver's document then
  /// still listed that ride - a write made from a copy of the profile read
  /// before the ride ended, landing after it - [getCurrentOrder] hit its
  /// "already following this ride" guard and returned on every snapshot. The
  /// screen looked free, the document said busy, no dispatcher offered the
  /// driver anything, and only an app restart put it right.
  void _forgetEndedRide(String id) {
    _endedRideIds.add(id);
    if (_watchedRideId != id) return;
    _watchedRideId = null;
    final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? doc = _orderDocSub;
    final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? query = _orderQuerySub;
    _orderDocSub = null;
    _orderQuerySub = null;
    unawaited(doc?.cancel());
    unawaited(query?.cancel());
  }

  /// Clears ride [id] from the screen, once it has ended.
  void _endRideOnScreen(String id) {
    _forgetEndedRide(id);
    currentOrder.value = CabOrderModel();
    _routeKey = null;
    unawaited(clearMap());
    update();
  }

  /// Takes rides this screen saw end back off the driver's document.
  ///
  /// One write, and only when such a ride is actually listed, so the driver is
  /// offered rides again instead of waiting for a restart.
  void _dropEndedRides(List<String> ended) {
    final List<dynamic> remaining = (driverModel.value.inProgressOrderID ?? <dynamic>[])
        .where((dynamic rideId) => !ended.contains(rideId?.toString()))
        .toList();
    driverModel.value.inProgressOrderID = remaining;
    log('CabHomeController: ${ended.join(', ')} had already ended but was still listed on this driver; removed.');
    unawaited(FireStoreUtils.updateUser(driverModel.value));
  }

  Future<void> _handleOrderDoc(DocumentSnapshot<Map<String, dynamic>> docSnap, String id) async {
    try {
      if (docSnap.exists) {
        final data = docSnap.data();
        if (data != null) {
          currentOrder.value = CabOrderModel.fromJson(data);
          changeData();
          if (currentOrder.value.status == Constant.orderCompleted) {
            _forgetEndedRide(id);
            driverModel.value.inProgressOrderID = [];
            unawaited(FireStoreUtils.updateUser(driverModel.value));
            currentOrder.value = CabOrderModel();
            _routeKey = null;
            unawaited(clearMap());
            update();
            return;
          } else if (currentOrder.value.status == Constant.orderRejected || currentOrder.value.status == Constant.orderCancelled) {
            _forgetEndedRide(id);
            driverModel.value.inProgressOrderID = [];
            driverModel.value.orderCabRequestData = null;
            unawaited(FireStoreUtils.updateUser(driverModel.value));
            currentOrder.value = CabOrderModel();
            _routeKey = null;
            unawaited(clearMap());
            update();
            return;
          }
          update();
          return;
        }
      }
      _orderQuerySub = FireStoreUtils.fireStore.collection(CollectionName.ridesBooking).where('id', isEqualTo: id).limit(1).snapshots().listen((qSnap) => _handleOrderQuery(qSnap, id));
    } catch (e) {
      log("Error listening to order doc: $e");
    }
  }

  Future<void> _handleOrderQuery(QuerySnapshot<Map<String, dynamic>> qSnap, String id) async {
    try {
      if (qSnap.docs.isNotEmpty) {
        final doc = qSnap.docs.first;
        final data = doc.data();
        currentOrder.value = CabOrderModel.fromJson(data);
        changeData();
        if (currentOrder.value.status == Constant.orderCompleted) {
          _forgetEndedRide(id);
          driverModel.value.inProgressOrderID = [];
          unawaited(FireStoreUtils.updateUser(driverModel.value));
          currentOrder.value = CabOrderModel();
          _routeKey = null;
          unawaited(clearMap());
          update();
          return;
        }
        update();
        return;
      } else {
        currentOrder.value = CabOrderModel();
        _routeKey = null;
        unawaited(AudioPlayerService.playSound(false));
        update();
      }
    } catch (e) {
      log("Error parsing order from query fallback: $e");
    }
  }

  RxBool isChange = false.obs;

  /// Everything a new ride snapshot has to do, in the order the driver
  /// experiences it.
  ///
  /// This used to draw the route **first**, and `await` it: a call to a public
  /// routing server bounded only by [NetworkTimeout.mapRequest], fifteen
  /// seconds. Behind that await sat the ride-request alert, the jump back to
  /// the home section, and - because every caller awaited `changeData()` in
  /// turn - the `update()` that redraws the screen. A slow or rate-limited
  /// route reply therefore delayed the *request itself* by up to fifteen
  /// seconds, and it was fetched again on every snapshot of either the ride or
  /// the driver's own document.
  ///
  /// Nothing on this path waits on the network any more. The alert, the
  /// section switch and the markers are local and happen on the spot; the
  /// route line is started and left to arrive, which is all a decoration on a
  /// map needs to do.
  ///
  /// Kept `async` so the existing call sites are unchanged, but it is finished
  /// before its future is: there is no `await` in it.
  Future<void> changeData() async {
    // Play alert sound for both "Order Placed" and "Driver Pending" — both need accept/reject
    final bool isRequest = currentOrder.value.status == Constant.driverPending || currentOrder.value.status == Constant.orderPlaced;
    if (isRequest) {
      _showRequestToDriver();
    }
    unawaited(AudioPlayerService.playSound(isRequest));
    setOsmMapMarker();
    unawaited(_refreshRoute());
  }

  /// The route line, fetched only when it would actually be a different line.
  ///
  /// The old code asked for a route on every snapshot it saw. The driver's own
  /// user document is written on every location update, so a ride in progress
  /// produced one routing request after another against the same free server -
  /// which answers more and more slowly under exactly that pattern, and was
  /// therefore making its own await longer. A route is worth re-fetching when
  /// the ride changes, when its status changes (the leg being drawn is a
  /// different leg), or when the driver has actually moved; [_routeKey] is all
  /// three, and [_routeMinInterval] is the floor underneath them.
  Future<void> _refreshRoute({bool force = false}) async {
    if (Constant.mapType != "inappmap") return;
    if (currentOrder.value.id == null) return;

    final String key = _routeSignature();
    final DateTime now = DateTime.now();
    if (!force && key == _routeKey && _routeAt != null && now.difference(_routeAt!) < _routeMinInterval) {
      return;
    }
    _routeKey = key;
    _routeAt = now;

    if (Constant.selectedMapType == "osm") {
      await getOSMPolyline();
    } else {
      await getGooglePolyline();
    }
  }

  /// What the drawn route depends on: which ride, which leg, and roughly where
  /// the driver is. Three decimal places is about a hundred metres, which is
  /// well inside the `driverLocationUpdate` distance the platform throttles
  /// location writes to.
  String _routeSignature() {
    final location.LatLng? here = realMapPoint(driverModel.value.location) ?? mapCentre.lastPoint;
    final String at = here == null ? '-' : '${here.latitude.toStringAsFixed(3)},${here.longitude.toStringAsFixed(3)}';
    return '${currentOrder.value.id}|${currentOrder.value.status}|$at';
  }

  /// Never more often than this, whatever the signature says.
  static const Duration _routeMinInterval = Duration(seconds: 20);

  String? _routeKey;
  DateTime? _routeAt;

  /// The ride this driver has already been shown, so a request that stays
  /// pending across several snapshots only pulls them in once.
  String? _announcedRequestId;

  /// Brings a new ride request on screen.
  ///
  /// The home section is the only place the accept/reject sheet is drawn, and
  /// it now stays alive while the driver is in another section - that is what
  /// stops every section reloading from the network when they come back. So a
  /// request can arrive, and ring, while its sheet is out of sight. This puts
  /// the driver back on it, once per ride.
  void _showRequestToDriver() {
    final String? id = currentOrder.value.id;
    if (id == null || id == _announcedRequestId) return;
    _announcedRequestId = id;
    if (!Get.isRegistered<CabDashBoardController>()) return;
    final CabDashBoardController dashboard = Get.find<CabDashBoardController>();
    if (dashboard.drawerIndex.value != CabBottomNavigation.homeDrawerIndex) {
      dashboard.drawerIndex.value = CabBottomNavigation.homeDrawerIndex;
    }
  }

  Future<void> _subscribeDriver() async {
    // Cancel before re-subscribing. Without this, a second call stacks a second
    // listener on the same documents and the first one can never be reached
    // again to close it.
    await _driverSub?.cancel();
    await _ownerSub?.cancel();

    _driverSub = FireStoreUtils.fireStore.collection(CollectionName.users).doc(FireStoreUtils.getCurrentUid()).snapshots().listen((event) => _onDriverSnapshot(event));

    if (Constant.userModel!.ownerId != null && Constant.userModel!.ownerId!.isNotEmpty) {
      _ownerSub = FireStoreUtils.fireStore.collection(CollectionName.users).doc(Constant.userModel!.ownerId).snapshots().listen(
        (event) async {
          if (event.exists) {
            ownerModel.value = UserModel.fromJson(event.data()!);
          }
        },
      );
    }
  }

  Future<void> _onDriverSnapshot(DocumentSnapshot<Map<String, dynamic>> event) async {
    try {
      if (event.exists && event.data() != null) {
        driverModel.value = UserModel.fromJson(event.data()!);
        awaitsDocumentVerification.value = driverAwaitsDocumentVerification(driverModel.value);
        _updateCurrentLocationMarkers();
        if (driverModel.value.id != null) {
          // `getCurrentOrder` only rebuilds anything when the ride this driver
          // is on has actually changed, and the ride listener it opens calls
          // `changeData` itself on every snapshot. The second, unconditional
          // `await changeData()` that used to be here therefore did nothing
          // except fetch the route a second time - on every location update -
          // and hold this callback open while it did.
          await getCurrentOrder();
          unawaited(_refreshRoute());
          // For multi-section drivers: use active order's sectionId when available.
          // currentOrder may not be populated yet (async listener), so also check
          // orderCabRequestData.sectionId (the pending push from customer side).
          final activeSectionId = (currentOrder.value.sectionId?.isNotEmpty == true)
              ? currentOrder.value.sectionId
              : (driverModel.value.orderCabRequestData?.sectionId?.isNotEmpty == true)
                  ? driverModel.value.orderCabRequestData!.sectionId
                  : driverModel.value.sectionIds?.isNotEmpty == true
                      ? driverModel.value.sectionIds!.first
                      : null;
          // Preload all registered sections into cache; also ensure active section is loaded
          for (final sid in driverModel.value.sectionIds ?? <String>[]) {
            if (!Constant.sectionModels.containsKey(sid)) {
              FireStoreUtils.getSectionBySectionId(sid).then((sectionValue) {
                if (sectionValue != null) Constant.sectionModels[sid] = sectionValue;
              });
            }
          }
          // Active order/request section may differ — ensure it's cached too
          if (activeSectionId != null &&
              activeSectionId.isNotEmpty &&
              !Constant.sectionModels.containsKey(activeSectionId)) {
            await FireStoreUtils.getSectionBySectionId(activeSectionId).then((sectionValue) {
              if (sectionValue != null) Constant.sectionModels[activeSectionId] = sectionValue;
            });
          }
          update();
        }
      }
    } catch (e) {
      log("getDriver() listener error: $e");
    }
  }

  void _updateCurrentLocationMarkers() async {
    try {
      // The driver's own `users` document is the *weakest* source of position
      // here, not the strongest. It is only written when the platform stream
      // fires, and that stream is throttled to `driverLocationUpdate` metres —
      // 1000 on this project — so a driver who has not moved a kilometre has no
      // `location` on it at all. Read through `?? 0.0` that became `0, 0`, this
      // listener overwrote whatever the GPS had found with it on every
      // snapshot, and the map sat on Null Island for the rest of the session.
      // So: a real document point is used only until a device fix exists, and
      // a point that is not a real place is not used at all.
      final location.LatLng? fromDocument = realMapPoint(driverModel.value.location);
      if (fromDocument != null && !mapLocation.hasDeviceFix) {
        current.value = fromDocument;
      }

      // --- OSM Section ---
      try {
        setOsmMapMarker();

        if (fromDocument != null && !mapLocation.hasDeviceFix) {
          mapCentre.moveTo(fromDocument);
        }
      } catch (e) {
        log("OSM map move ignored (controller not ready): $e");
      }

      // --- GOOGLE MAP Section ---
      try {
        final bool drawable = isRealMapPoint(current.value.latitude, current.value.longitude);
        if (drawable) {
          final driverIcon = await _getDriverIcon();

          // Remove old driver marker
          markers.remove("Driver");

          // Create new Google Marker
          markers["Driver"] = Marker(
            markerId: const MarkerId("Driver"),
            infoWindow: const InfoWindow(title: "Driver"),
            position: LatLng(current.value.latitude, current.value.longitude),
            icon: driverIcon,
            rotation: _safeRotation(),
            anchor: const Offset(0.5, 0.5),
            flat: true,
          );

          // Animate camera to current driver location
          if (mapController != null) {
            mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: LatLng(current.value.latitude, current.value.longitude),
                  zoom: 16,
                  bearing: _safeRotation(),
                ),
              ),
            );
          }
        }
      } catch (e) {
        log("Google map update ignored (controller not ready): $e");
      }

      update();

      log('_updateCurrentLocationMarkers: lat=${current.value.latitude}, lng=${current.value.longitude}, '
          'fromDocument=${fromDocument != null}, deviceFix=${mapLocation.hasDeviceFix}, '
          'osmMarkers=${osmMarkers.length}, googleMarkers=${markers.length}');
    } catch (e) {
      log("_updateCurrentLocationMarkers error: $e");
    }
  }

  GoogleMapController? mapController;

  Rx<PolylinePoints> polylinePoints = PolylinePoints(apiKey: Constant.mapAPIKey).obs;
  RxMap<PolylineId, Polyline> polyLines = <PolylineId, Polyline>{}.obs;
  RxMap<String, Marker> markers = <String, Marker>{}.obs;

  LatLng _safeLatLngFromLocation(dynamic loc) {
    final lat = (loc?.latitude is num) ? loc.latitude.toDouble() : 0.0;
    final lng = (loc?.longitude is num) ? loc.longitude.toDouble() : 0.0;
    return LatLng(lat, lng);
  }

  double _safeRotation() {
    return double.tryParse(driverModel.value.rotation.toString()) ?? 0.0;
  }

  Future<void> getGooglePolyline() async {
    try {
      if (currentOrder.value.id == null) return;

      final driverLatLng = _safeLatLngFromLocation(driverModel.value.location);

      // Check order status
      if (currentOrder.value.status != Constant.driverPending) {
        // Case 1: Driver Accepted or Order Shipped → Driver → Pickup
        if (currentOrder.value.status == Constant.driverAccepted || currentOrder.value.status == Constant.orderShipped) {
          final sourceLatLng = _safeLatLngFromLocation(currentOrder.value.sourceLocation);

          await _drawGoogleRoute(
            origin: driverLatLng,
            destination: sourceLatLng,
            addDriver: true,
            addSource: true,
            addDestination: false,
          );

          animateToSource();
        }

        // Case 2: Order In Transit → Driver → Destination
        else if (currentOrder.value.status == Constant.orderInTransit) {
          final destLatLng = _safeLatLngFromLocation(currentOrder.value.destinationLocation);

          await _drawGoogleRoute(
            origin: driverLatLng,
            destination: destLatLng,
            addDriver: true,
            addSource: false,
            addDestination: true,
          );

          animateToSource();
        }
      }

      // Case 3: Before driver assigned → Source → Destination
      else {
        final sourceLatLng = _safeLatLngFromLocation(currentOrder.value.sourceLocation);
        final destLatLng = _safeLatLngFromLocation(currentOrder.value.destinationLocation);

        await _drawGoogleRoute(
          origin: sourceLatLng,
          destination: destLatLng,
          addDriver: false,
          addSource: true,
          addDestination: true,
        );

        animateToSource();
      }
    } catch (e, s) {
      log('getGooglePolyline() error: $e');
      debugPrintStack(stackTrace: s);
    }
  }

  Future<void> _drawGoogleRoute({
    required LatLng origin,
    required LatLng destination,
    bool addDriver = true,
    bool addSource = true,
    bool addDestination = true,
  }) async {
    try {
      if ((origin.latitude == 0.0 && origin.longitude == 0.0) || (destination.latitude == 0.0 && destination.longitude == 0.0)) return;

      // Get route points from Google Directions API
      final result = await polylinePoints.value.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: PointLatLng(origin.latitude, origin.longitude),
          destination: PointLatLng(destination.latitude, destination.longitude),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isEmpty) {
        log('Google route not found');
        return;
      }

      final List<LatLng> polylineCoordinates = result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();

      // Draw polyline
      addPolyLine(polylineCoordinates);

      // --- Update markers (same style as OSM) ---
      await _updateGoogleMarkers(
        driverLatLng: addDriver ? origin : null,
        sourceLatLng: addSource ? _safeLatLngFromLocation(currentOrder.value.sourceLocation) : null,
        destinationLatLng: addDestination ? _safeLatLngFromLocation(currentOrder.value.destinationLocation) : null,
      );
    } catch (e) {
      log('_drawGoogleRoute error: $e');
    }
  }

  Future<void> _updateGoogleMarkers({
    LatLng? driverLatLng,
    LatLng? sourceLatLng,
    LatLng? destinationLatLng,
  }) async {
    final Map<String, Marker> newMarkers = {};

    // Driver Marker
    if (driverLatLng != null) {
      final driverIcon = await _getDriverIcon();
      newMarkers['Driver'] = Marker(
        markerId: const MarkerId('Driver'),
        position: driverLatLng,
        rotation: _safeRotation(),
        anchor: const Offset(0.5, 0.5),
        flat: true,
        icon: driverIcon,
      );
    }

    // Source Marker
    if (sourceLatLng != null) {
      final srcIcon = await _bitmapDescriptorFromAsset(
        'assets/images/location_black3x.png',
        width: 100,
      );
      newMarkers['Source'] = Marker(
        markerId: const MarkerId('Source'),
        position: sourceLatLng,
        icon: srcIcon,
      );
    }

    // Destination Marker
    if (destinationLatLng != null) {
      final dstIcon = await _bitmapDescriptorFromAsset(
        'assets/images/location_orange3x.png',
        width: 100,
      );
      newMarkers['Destination'] = Marker(
        markerId: const MarkerId('Destination'),
        position: destinationLatLng,
        icon: dstIcon,
      );
    }

    // Apply all markers
    // ✅ Apply all markers to your RxMap<String, Marker>
    markers
      ..clear()
      ..addAll(newMarkers);

    update();
  }

  Future<BitmapDescriptor> _bitmapDescriptorFromUrl(String url, {int width = 100}) async {
    try {
      final Uint8List bytes = await Constant().getBytesFromUrl(url, width: width);
      return BitmapDescriptor.fromBytes(bytes);
    } catch (e) {
      log('Error loading network icon: $e');
      return BitmapDescriptor.defaultMarker;
    }
  }

  Future<BitmapDescriptor> _bitmapDescriptorFromAsset(String asset, {int width = 100}) async {
    try {
      final Uint8List bytes = await Constant().getBytesFromAsset(asset, width);
      return BitmapDescriptor.fromBytes(bytes);
    } catch (e) {
      log('Error loading asset icon: $e');
      return BitmapDescriptor.defaultMarker;
    }
  }

  void addPolyLine(List<LatLng> polylineCoordinates) {
    if (polylineCoordinates.isEmpty) {
      // nothing to draw, but ensure markers updated
      update();
      return;
    }

    PolylineId id = const PolylineId("poly");
    Polyline polyline = Polyline(
      polylineId: id,
      color: AppThemeData.primary300,
      points: polylineCoordinates,
      width: 8,
      geodesic: true,
    );
    polyLines[id] = polyline;
    update();
    updateCameraLocation(polylineCoordinates.first);
  }

  Future<void> updateCameraLocation([LatLng? source]) async {
    try {
      if (mapController == null || source == null) return;
      await mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: source,
            zoom: currentOrder.value.id == null || currentOrder.value.status == Constant.driverPending ? 16 : 20,
            bearing: _safeRotation(),
          ),
        ),
      );
    } catch (e) {
      log("updateCameraLocation error: $e");
    }
  }

  /// The "put the map back on me" button.
  ///
  /// It read the driver's document with a `?? 0.0` and moved there with no
  /// check at all, so for a driver whose document holds no location the one
  /// control meant to rescue the screen was the fastest way to throw the map
  /// into the Atlantic. It now prefers the live fix and refuses to move
  /// anywhere that is not a real place.
  void animateToSource() {
    // Also the driver's way out if the fix never arrived: nothing else in the
    // app would ask for the permission a second time.
    unawaited(mapLocation.retryIfIdle());
    _updateCurrentLocationMarkers();
    final location.LatLng? target = mapCentre.lastPoint ??
        realMapPoint(driverModel.value.location) ??
        (isRealMapPoint(current.value.latitude, current.value.longitude) ? current.value : null);
    if (target != null) mapCentre.moveTo(target);
  }

  Rx<location.LatLng> source = location.LatLng(21.1702, 72.8311).obs; // Start (e.g., Surat)
  /// Deliberately not a place: `isRealMapPoint` rejects it, so no driver
  /// marker is drawn until a fix actually exists. It used to default to
  /// `21.18, 72.84` — Surat, India — which put a cab icon on the map of a
  /// driver who had never been there.
  Rx<location.LatLng> current = location.LatLng(0, 0).obs; // Moving marker
  Rx<location.LatLng> destination = location.LatLng(21.2000, 72.8600).obs; // Destination

  void setOsmMapMarker() {
    final List<flutterMap.Marker> mk = [];

    // Add driver/current marker only when we have a valid location. The old
    // test was `!= 0, 0` exactly, which let the `0.01, 0.01` placeholder three
    // live driver documents hold through as a real position.
    if (isRealMapPoint(current.value.latitude, current.value.longitude)) {
      mk.add(flutterMap.Marker(
        point: current.value,
        width: 45,
        height: 45,
        rotate: true,
        child: _driverMarkerWidget(),
      ));
    }

    // Add source marker if we have a valid source location (or an active order with non-zero coords)
    final hasSource = currentOrder.value.sourceLocation != null &&
        !(currentOrder.value.sourceLocation?.latitude == null || currentOrder.value.sourceLocation?.longitude == null) &&
        !(currentOrder.value.sourceLocation?.latitude == 0.0 && currentOrder.value.sourceLocation?.longitude == 0.0);
    if (hasSource) {
      source.value = location.LatLng(currentOrder.value.sourceLocation!.latitude ?? 0.0, currentOrder.value.sourceLocation!.longitude ?? 0.0);
      mk.add(flutterMap.Marker(
        point: source.value,
        width: 40,
        height: 40,
        child: Image.asset('assets/images/location_black3x.png'),
      ));
    }

    // Add destination marker if valid
    final hasDest = currentOrder.value.destinationLocation != null &&
        !(currentOrder.value.destinationLocation?.latitude == null || currentOrder.value.destinationLocation?.longitude == null) &&
        !(currentOrder.value.destinationLocation?.latitude == 0.0 && currentOrder.value.destinationLocation?.longitude == 0.0);
    if (hasDest) {
      destination.value = location.LatLng(currentOrder.value.destinationLocation!.latitude ?? 0.0, currentOrder.value.destinationLocation!.longitude ?? 0.0);
      mk.add(flutterMap.Marker(
        point: destination.value,
        width: 40,
        height: 40,
        child: Image.asset('assets/images/location_orange3x.png'),
      ));
    }

    osmMarkers.value = mk;
  }

  Future<void> getOSMPolyline() async {
    try {
      if (currentOrder.value.id == null) return;

      if (currentOrder.value.status != Constant.driverPending) {
        // Same `?? 0.0` as everywhere else in this file: on a ride whose driver
        // document has no location it moved the route's origin to Null Island,
        // which drew a polyline across the Atlantic and took the map with it.
        // The live fix is the origin now, and a leg with no real end is simply
        // not drawn.
        if (currentOrder.value.status == Constant.driverAccepted || currentOrder.value.status == Constant.orderShipped) {
          final location.LatLng? here = realMapPoint(driverModel.value.location) ?? mapCentre.lastPoint;
          final location.LatLng? pickup = realMapPoint(currentOrder.value.sourceLocation);
          if (here != null) current.value = here;
          if (pickup != null) source.value = pickup;
          animateToSource();
          if (here != null && pickup != null) await fetchRoute(here, pickup);
          setOsmMapMarker();
        } else if (currentOrder.value.status == Constant.orderInTransit) {
          final location.LatLng? here = realMapPoint(driverModel.value.location) ?? mapCentre.lastPoint;
          final location.LatLng? dropOff = realMapPoint(currentOrder.value.destinationLocation);
          if (here != null) current.value = here;
          if (dropOff != null) destination.value = dropOff;
          if (here != null && dropOff != null) await fetchRoute(here, dropOff);
          setOsmMapMarker();
          animateToSource();
        }
      } else {
        final location.LatLng? pickup = realMapPoint(currentOrder.value.sourceLocation);
        final location.LatLng? dropOff = realMapPoint(currentOrder.value.destinationLocation);
        if (pickup != null) current.value = pickup;
        if (dropOff != null) destination.value = dropOff;
        if (pickup != null && dropOff != null) await fetchRoute(pickup, dropOff);
        setOsmMapMarker();
        animateToSource();
      }
    } catch (e) {
      log('getOSMPolyline error: $e');
    }
  }

  RxList<location.LatLng> routePoints = <location.LatLng>[].obs;

  Future<void> fetchRoute(location.LatLng source, location.LatLng destination) async {
    try {
      // ensure valid coords
      final bothZero = source.latitude == 0.0 && source.longitude == 0.0 && destination.latitude == 0.0 && destination.longitude == 0.0;
      if (bothZero) {
        routePoints.clear();
        return;
      }

      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${source.longitude},${source.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(NetworkTimeout.mapRequest);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded != null && decoded['routes'] != null && decoded['routes'] is List && (decoded['routes'] as List).isNotEmpty && decoded['routes'][0]['geometry'] != null) {
          final geometry = decoded['routes'][0]['geometry']['coordinates'];
          routePoints.clear();
          for (var coord in geometry) {
            if (coord is List && coord.length >= 2) {
              final lon = coord[0];
              final lat = coord[1];
              if (lat is num && lon is num) {
                routePoints.add(location.LatLng(lat.toDouble(), lon.toDouble()));
              }
            }
          }
          return;
        }
        routePoints.clear();
      } else {
        log("Failed to get route: ${response.statusCode} ${response.body}");
        routePoints.clear();
      }
    } catch (e) {
      log("fetchRoute error: $e");
      routePoints.clear();
    }
  }
}
