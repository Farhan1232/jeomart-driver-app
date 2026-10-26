import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/send_notification.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/services/audio_player_service.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/utils/driver_map_location.dart';
import 'package:driver/utils/finished_order.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/network_timeout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as flutterMap;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as location;

import '../models/order_model.dart';

class HomeController extends GetxController {
  RxBool isLoading = true.obs;
  flutterMap.MapController osmMapController = flutterMap.MapController();
  RxList<flutterMap.Marker> osmMarkers = <flutterMap.Marker>[].obs;

  /// Where this screen's map looks, and how it gets there.
  ///
  /// The delivery home carried the identical defect as the cab home: the
  /// driver's `users` document was read with `?? 0.0`, so a driver whose
  /// document has no `location` — it is only written after the platform stream
  /// moves 1000 metres — centred the map on `0, 0`, which draws one flat blue
  /// tile and never recovers. See [isRealMapPoint].
  late final DriverMapCentre mapCentre = DriverMapCentre(
    osmMapController,
    onGoogleCamera: _moveGoogleCamera,
  );
  late final DriverMapLocation mapLocation = DriverMapLocation(onFix: _onMapFix);

  /// The coordinate the map is *built* on. A plain getter, not a reactive read:
  /// `initialCenter` is consumed once and every later fix moves the camera.
  location.LatLng get initialMapCentre => mapCentre.lastPoint ?? _mapSeed ?? _unknownCentre;

  /// Street zoom once the driver is placed, a wide one while they are not.
  double get initialMapZoom => (mapCentre.lastPoint ?? _mapSeed) != null ? 16 : 4;

  location.LatLng? _mapSeed;

  static final location.LatLng _unknownCentre = location.LatLng(21.1800, 72.8400);

  /// Wired to `MapOptions.onMapReady`.
  void onMapReady() => mapCentre.mapReady();

  /// Firestore listeners held by this controller.
  ///
  /// They used to be opened without ever being stored, so `_listenToOrder`
  /// stacked a new listener on every call and none were cancelled when the
  /// screen closed. Same pattern as CabHomeController.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _orderSub;

  @override
  void onInit() {
    _initController();
    super.onInit();
  }

  @override
  void onClose() {
    _driverSub?.cancel();
    _orderSub?.cancel();
    mapLocation.dispose();
    super.onClose();
  }

  Future<void> _initController() async {
    getArgument();
    // Resolved before anything awaits, because the map is built in this frame
    // and `initialCenter` is read once.
    _mapSeed = mapLocation.seed() ?? realMapPoint(Constant.userModel?.location);
    unawaited(mapLocation.start());
    await setIcons(); // wait for icons first
    getDriver();

    // The screen is released here, not inside the `users` listener below.
    //
    // `isLoading` gates the *whole* body, the map included, and it used to drop
    // only once that listener had delivered its first snapshot AND that
    // snapshot carried an `id`. So the map — which needs nothing from
    // Firestore, having already been seeded from the device above — waited a
    // full network round trip before it could draw a single tile. That is the
    // "map does not load" the client reports, and on a cold or flaky
    // connection it is the "app hangs on a spinner": a read that never lands,
    // a document that does not exist, or a listener error left `isLoading`
    // true for the life of the screen with nothing to recover it.
    //
    // Nothing below this line is skipped — the listener still arrives and still
    // repaints. Safe because an unloaded `driverModel` has a null `vendorID`,
    // so the document-verification branch of the body reads false and falls
    // through to the map, exactly as it does for a verified driver.
    isLoading.value = false;
  }

  /// Every position the map is given, from the disk seed to each live fix.
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
      debugPrint('HomeController: google camera not ready :: $error');
    }
  }

  Rx<OrderModel> orderModel = OrderModel().obs;
  Rx<OrderModel> currentOrder = OrderModel().obs;
  Rx<UserModel> driverModel = UserModel().obs;

  void getArgument() {
    dynamic argumentData = Get.arguments;
    if (argumentData != null) {
      orderModel.value = argumentData['orderModel'];
    }
  }

  Future<void> acceptOrder() async {
    ShowToastDialog.showLoader("Please wait".tr);

    await AudioPlayerService.playSound(false);

    currentOrder.value.status = Constant.driverAccepted;
    currentOrder.value.driverID = driverModel.value.id;
    currentOrder.value.driver = driverModel.value;

    driverModel.value.inProgressOrderID ??= [];
    driverModel.value.orderRequestData!.remove(currentOrder.value.id);
    driverModel.value.inProgressOrderID!.add(currentOrder.value.id);

    await FireStoreUtils.updateUser(driverModel.value);
    await FireStoreUtils.setOrder(currentOrder.value);
    print("SendNotification ===========>");
    SendNotification.sendFcmMessage(Constant.driverAcceptedNotification, currentOrder.value.author?.fcmToken ?? '', {});
    SendNotification.sendFcmMessage(Constant.driverAcceptedNotification, currentOrder.value.vendor?.fcmToken ?? '', {});
    ShowToastDialog.closeLoader();
  }

  Future<void> rejectOrder() async {
    ShowToastDialog.showLoader("Please wait".tr);
    // 🔊 Stop any ongoing alert sound (if playing)
    await AudioPlayerService.playSound(false);

    final driver = driverModel.value;
    final order = currentOrder.value;

    // 1️⃣ Validate order and driver
    if (order.id == null || driver.id == null) {
      debugPrint("⚠️ No valid order or driver found for rejection.");
      // The loader opened above has to come down on this path too.
      ShowToastDialog.closeLoader();
      return;
    }

    // 2️⃣ Add driver to rejected list safely
    order.rejectedByDrivers ??= [];
    if (!order.rejectedByDrivers!.contains(driver.id)) {
      order.rejectedByDrivers!.add(driver.id);
    }

    // 3️⃣ Update order status
    order.status = Constant.driverRejected;

    // 4️⃣ Push order update to Firestore
    await FireStoreUtils.setOrder(order);

    // 5️⃣ Clean up driver's order tracking data safely
    driver.orderRequestData?.remove(order.id);
    driver.inProgressOrderID?.remove(order.id);

    // 6️⃣ Update driver info in Firestore
    await FireStoreUtils.updateUser(driver);

    // 7️⃣ Reset order states
    currentOrder.value = OrderModel();
    orderModel.value = OrderModel();

    // 8️⃣ Clear map visuals and UI
    await clearMap();
    update();

    // 9️⃣ If multiple orders allowed, close dialog/screen
    ShowToastDialog.closeLoader();
    if (Constant.singleOrderReceive == false) {
      Get.back();
    }
    debugPrint("✅ Order ${order.id} rejected by driver ${driver.id}");
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

  Future<void> getCurrentOrder() async {
    final driver = driverModel.value;
    final currentId = currentOrder.value.id;

    // 1️⃣ Reset if current order is invalid
    if (currentId != null &&
        !(driver.orderRequestData?.contains(currentId) ?? false) &&
        !(driver.inProgressOrderID?.contains(currentId) ?? false)) {
      await _resetCurrentOrder();
      return;
    }

    // 2️⃣ Handle single-order mode
    if (Constant.singleOrderReceive == true) {
      final inProgress = driver.inProgressOrderID;
      final requests = driver.orderRequestData;

      if (inProgress != null && inProgress.isNotEmpty) {
        _listenToOrder(inProgress.first);
        return;
      }

      if (requests != null && requests.isNotEmpty) {
        _listenToOrder(requests.first, checkInRequestData: true);
        return;
      }
    }

    // 3️⃣ Handle fallback (when orderModel has ID)
    final fallbackId = orderModel.value.id;
    if (fallbackId != null) {
      _listenToOrder(fallbackId);
    }
  }

  /// What [_listenToOrder] is following, so it is not reopened for nothing.
  String? _orderListenKey;

  void _forgetOrderListener() {
    _orderSub?.cancel();
    _orderSub = null;
    _orderListenKey = null;
  }

  Future<void> _resetCurrentOrder() async {
    _forgetOrderListener();
    currentOrder.value = OrderModel();
    await clearMap();
    await AudioPlayerService.playSound(false);
    update();
  }

  /// 🔹 Listen to Firestore order updates for a specific orderId
  void _listenToOrder(String orderId, {bool checkInRequestData = false}) {
    // Already following this order the same way: keep the listener. It used to
    // be closed and opened again on every snapshot of the driver's document -
    // each position update and each button's write - which is a fresh server
    // round trip each time. Whenever the order is not on screen the listener is
    // dropped (see [_forgetOrderListener]), so a re-offered or late order still
    // opens a new one exactly as before.
    final String key = '$orderId|$checkInRequestData';
    if (_orderSub != null && _orderListenKey == key) return;
    _orderListenKey = key;
    // Only ever one order listener at a time.
    _orderSub?.cancel();
    _orderSub = FireStoreUtils.fireStore
        .collection(CollectionName.vendorOrders)
        .where('status', whereNotIn: [
          Constant.orderCancelled,
          Constant.driverRejected,
        ])
        .where('id', isEqualTo: orderId)
        .limit(1)
        .snapshots()
        .listen((event) async {
          // An order that is over - delivered, cancelled, rejected or gone -
          // comes off the driver's lists, or the dispatcher keeps treating the
          // driver as busy and offers them nothing more. See FinishedOrder.
          if (FinishedOrder.isFinished(
            fromCache: event.metadata.isFromCache,
            found: event.docs.isNotEmpty,
            status: event.docs.isEmpty ? null : event.docs.first.data()['status']?.toString(),
          )) {
            await _releaseFinishedOrder(orderId, found: event.docs.isNotEmpty);
          }

          if (event.docs.isEmpty) {
            await _handleOrderNotFound();
            return;
          }

          final data = event.docs.first.data();
          final newOrder = OrderModel.fromJson(data);

          if (checkInRequestData && !(driverModel.value.orderRequestData?.contains(newOrder.id) ?? false)) {
            await _handleOrderNotFound();
            return;
          }

          if (newOrder.rejectedByDrivers!.contains(driverModel.value.id)) {
            await _handleOrderNotFound();
            return;
          }

          // Guard: skip stale driverPending update if driver already accepted this order
          if (newOrder.status == Constant.driverPending && (driverModel.value.inProgressOrderID?.contains(newOrder.id) ?? false)) {
            return;
          }

          currentOrder.value = newOrder;
          // Update section model to match this order's section (multi-section support)
          final sid = newOrder.sectionId;
          if (sid != null && sid.isNotEmpty) {
            FireStoreUtils.getSectionBySectionId(sid).then((s) {
              if (s != null) Constant.sectionModels[sid] = s;
            });
          }
          changeData();
        });
  }

  /// Takes a finished order off this driver's lists, on the device at once and
  /// then on the server, only when the driver still holds it - so a profile
  /// save made in between cannot put it back from this controller's copy.
  Future<void> _releaseFinishedOrder(String orderId, {required bool found}) async {
    final UserModel driver = driverModel.value;
    final bool held = (driver.inProgressOrderID?.contains(orderId) ?? false) || (driver.orderRequestData?.contains(orderId) ?? false);
    if (!held) return;
    // Not a delivery order at all - a cab, parcel or rental order the same
    // driver holds. That screen owns it. See FinishedOrder.otherServiceCollections.
    if (!found && await _isOtherServiceOrder(orderId)) return;
    driver.inProgressOrderID?.remove(orderId);
    driver.orderRequestData?.remove(orderId);
    await FireStoreUtils.releaseDriverOrder(orderId);
  }

  /// Whether [orderId] is an order of one of the driver's other services.
  ///
  /// Asked of the server only. If it cannot be answered, the id is treated as
  /// someone else's and kept: releasing a live ride by mistake is the bug this
  /// guards against, keeping a finished one is what the next snapshot retries.
  Future<bool> _isOtherServiceOrder(String orderId) async {
    try {
      final List<DocumentSnapshot<Map<String, dynamic>>> docs = await Future.wait(
        FinishedOrder.otherServiceCollections.map(
          (String collection) => FireStoreUtils.fireStore.collection(collection).doc(orderId).get(const GetOptions(source: Source.server)),
        ),
      );
      return docs.any((DocumentSnapshot<Map<String, dynamic>> doc) => doc.exists);
    } catch (error) {
      log('HomeController: could not check $orderId against the other services :: $error');
      return true;
    }
  }

  Future<void> _handleOrderNotFound() async {
    _forgetOrderListener();
    currentOrder.value = OrderModel();
    await AudioPlayerService.playSound(false);
    update();
  }

  RxBool isChange = false.obs;

  /// The route last fetched, and when - the same rule as the cab screen.
  ///
  /// `changeData` runs on every snapshot of the driver's own document, and that
  /// document is written on every position update and by every button. Each
  /// one downloaded the route again from the public routing server, even when
  /// the driver had not moved, while the buttons' writes waited behind it.
  String? _routeKey;
  DateTime? _routeAt;
  static const Duration _routeMinInterval = Duration(seconds: 20);

  bool _routeIsDue() {
    if (currentOrder.value.id == null) return true;
    final location.LatLng? here = realMapPoint(driverModel.value.location);
    final String at = here == null ? '-' : '${here.latitude.toStringAsFixed(3)},${here.longitude.toStringAsFixed(3)}';
    final String key = '${currentOrder.value.id}|${currentOrder.value.status}|$at';
    final DateTime now = DateTime.now();
    if (key == _routeKey && _routeAt != null && now.difference(_routeAt!) < _routeMinInterval) return false;
    _routeKey = key;
    _routeAt = now;
    return true;
  }

  Future<void> changeData() async {
    print(
        "currentOrder.value.status :: ${currentOrder.value.id} :: ${currentOrder.value.status} :: ( ${orderModel.value.driver?.vendorID != null} :: ${orderModel.value.status})");

    if (Constant.mapType == "inappmap" && _routeIsDue()) {
      if (Constant.selectedMapType == "osm") {
        getOSMPolyline();
      } else {
        getDirections();
      }
    }
    if (currentOrder.value.status == Constant.driverPending) {
      await AudioPlayerService.playSound(true);
    } else {
      await AudioPlayerService.playSound(false);
    }
  }

  void getDriver() {
    _driverSub?.cancel();
    _driverSub = FireStoreUtils.fireStore.collection(CollectionName.users).doc(FireStoreUtils.getCurrentUid()).snapshots().listen(
      (event) async {
        if (event.exists) {
          driverModel.value = UserModel.fromJson(event.data()!);
          _updateCurrentLocationMarkers();
          if (driverModel.value.id != null) {
            update();
            changeData();
            getCurrentOrder();
            // Preload all registered sections into cache
            for (final sid in driverModel.value.sectionIds ?? <String>[]) {
              if (!Constant.sectionModels.containsKey(sid)) {
                FireStoreUtils.getSectionBySectionId(sid).then((s) {
                  if (s != null) Constant.sectionModels[sid] = s;
                });
              }
            }
          }
        }
      },
      onError: (Object error) => log('home driver listener error :: $error'),
    );
  }

  GoogleMapController? mapController;

  Rx<PolylinePoints> polylinePoints = PolylinePoints(apiKey: Constant.mapAPIKey).obs;
  RxMap<PolylineId, Polyline> polyLines = <PolylineId, Polyline>{}.obs;
  RxMap<String, Marker> markers = <String, Marker>{}.obs;

  BitmapDescriptor? departureIcon;
  BitmapDescriptor? destinationIcon;
  BitmapDescriptor? taxiIcon;

  Future<void> setIcons() async {
    if (Constant.selectedMapType == 'google') {
      final Uint8List departure = await Constant().getBytesFromAsset('assets/images/location_black3x.png', 100);
      final Uint8List destination = await Constant().getBytesFromAsset('assets/images/location_orange3x.png', 100);
      final Uint8List driver = await Constant().getBytesFromAsset('assets/images/food_delivery.png', 120);

      departureIcon = BitmapDescriptor.fromBytes(departure);
      destinationIcon = BitmapDescriptor.fromBytes(destination);
      taxiIcon = BitmapDescriptor.fromBytes(driver);
    }
  }

  Future<void> getDirections() async {
    final order = currentOrder.value;
    final driver = driverModel.value;

    // 1️⃣ Safety checks
    if (order.id == null) {
      debugPrint("⚠️ getDirections: Order ID is null");
      return;
    }

    final driverLoc = driver.location;
    if (driverLoc == null) {
      debugPrint("⚠️ getDirections: Driver location is null");
      return;
    }

    // Icons must be loaded before proceeding
    if (taxiIcon == null || destinationIcon == null || departureIcon == null) {
      debugPrint("⚠️ getDirections: One or more map icons are null");
      return;
    }

    // 2️⃣ Get start and end coordinates based on order status
    LatLng? origin;
    LatLng? destination;

    switch (order.status) {
      case Constant.orderShipped:
        origin = LatLng(driverLoc.latitude ?? 0.0, driverLoc.longitude ?? 0.0);
        destination = _toLatLng(order.vendor?.latitude, order.vendor?.longitude);
        break;

      case Constant.orderInTransit:
        origin = LatLng(driverLoc.latitude ?? 0.0, driverLoc.longitude ?? 0.0);
        destination = _toLatLng(
          order.address?.location?.latitude,
          order.address?.location?.longitude,
        );
        break;

      case Constant.driverPending:
        origin = _toLatLng(
          order.author?.location?.latitude,
          order.author?.location?.longitude,
        );
        destination = _toLatLng(order.vendor?.latitude, order.vendor?.longitude);
        break;

      default:
        debugPrint("⚠️ getDirections: Unknown order status ${order.status}");
        return;
    }

    if (origin == null || destination == null) {
      debugPrint("⚠️ getDirections: Missing origin or destination");
      return;
    }

    // 3️⃣ Fetch polyline route
    final polylineCoordinates = await _fetchPolyline(origin, destination);
    if (polylineCoordinates.isEmpty) {
      debugPrint("⚠️ getDirections: No route found between origin and destination");
    }

    // 4️⃣ Update markers safely
    markers.remove("Departure");
    markers.remove("Destination");
    markers.remove("Driver");

    if (order.status == Constant.orderShipped || order.status == Constant.driverPending) {
      markers['Departure'] = Marker(
        markerId: const MarkerId('Departure'),
        infoWindow: const InfoWindow(title: "Departure"),
        position: _toLatLng(order.vendor?.latitude, order.vendor?.longitude) ?? const LatLng(0, 0),
        icon: departureIcon!,
      );
    }

    if (order.status == Constant.orderInTransit || order.status == Constant.driverPending) {
      markers['Destination'] = Marker(
        markerId: const MarkerId('Destination'),
        infoWindow: const InfoWindow(title: "Destination"),
        position: _toLatLng(
              order.address?.location?.latitude,
              order.address?.location?.longitude,
            ) ??
            const LatLng(0, 0),
        icon: destinationIcon!,
      );
    }

    markers['Driver'] = Marker(
      markerId: const MarkerId('Driver'),
      infoWindow: const InfoWindow(title: "Driver"),
      position: LatLng(
        driverLoc.latitude ?? 0.0, // ✅ safe fallback
        driverLoc.longitude ?? 0.0, // ✅ safe fallback
      ),
      icon: taxiIcon!,
      rotation: double.tryParse(driver.rotation.toString()) ?? 0,
    );

    // 5️⃣ Draw polyline
    addPolyLine(polylineCoordinates);
  }

  /// Helper: safely convert to LatLng if valid
  LatLng? _toLatLng(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  /// Helper: fetch polyline safely
  Future<List<LatLng>> _fetchPolyline(LatLng origin, LatLng destination) async {
    try {
      final result = await polylinePoints.value.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: PointLatLng(origin.latitude, origin.longitude),
          destination: PointLatLng(destination.latitude, destination.longitude),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isEmpty) return [];

      return result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    } catch (e, st) {
      debugPrint("❌ getDirections _fetchPolyline error: $e\n$st");
      return [];
    }
  }

  void addPolyLine(List<LatLng> polylineCoordinates) {
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
    updateCameraLocation(polylineCoordinates.first, mapController);
  }

  Future<void> updateCameraLocation(
    LatLng source,
    GoogleMapController? mapController,
  ) async {
    mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: source,
          zoom: currentOrder.value.id == null || currentOrder.value.status == Constant.driverPending ? 16 : 20,
          bearing: double.parse(driverModel.value.rotation.toString()),
        ),
      ),
    );
  }

  /// The "put the map back on me" button. It moved to the driver's document
  /// location with no check at all, so on a document with none it threw the map
  /// into the Atlantic. Prefers the live fix, and refuses anything unreal.
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

  void _updateCurrentLocationMarkers() async {
    try {
      // The driver's own document is the weakest source of position here, not
      // the strongest: it is written only when the platform stream fires, and
      // that stream is throttled to `driverLocationUpdate` metres — 1000 on
      // this project. Read through `?? 0.0` a missing one became `0, 0` and
      // this listener overwrote the GPS fix with it on every snapshot.
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
        print("OSM map move ignored (controller not ready): $e");
      }

      // --- GOOGLE MAP Section ---
      try {
        // Remove old driver marker
        markers.remove("Driver");

        // Create new Google Marker
        markers["Driver"] = Marker(
          markerId: const MarkerId("Driver"),
          infoWindow: const InfoWindow(title: "Driver"),
          position: LatLng(current.value.latitude, current.value.longitude),
          icon: taxiIcon!,
          rotation: _safeRotation(),
          anchor: const Offset(0.5, 0.5),
          flat: true,
        );

        // Animate camera to current driver location
        if (mapController != null && isRealMapPoint(current.value.latitude, current.value.longitude)) {
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
      } catch (e) {
        print("Google map update ignored (controller not ready): $e");
      }

      update();
    } catch (e) {
      print("_updateCurrentLocationMarkers error: $e");
    }
  }

  double _safeRotation() {
    return double.tryParse(driverModel.value.rotation.toString()) ?? 0.0;
  }


  Rx<location.LatLng> source = location.LatLng(21.1702, 72.8311).obs; // Start (e.g., Surat)
  /// Deliberately not a place: `isRealMapPoint` rejects it, so no driver
  /// marker is drawn until a fix actually exists. It used to default to
  /// `21.18, 72.84` — Surat, India — which put a cab icon on the map of a
  /// driver who had never been there.
  Rx<location.LatLng> current = location.LatLng(0, 0).obs; // Moving marker
  Rx<location.LatLng> destination = location.LatLng(21.2000, 72.8600).obs; // Destination

  void setOsmMapMarker() {
    osmMarkers.value = [
      flutterMap.Marker(
        point: current.value,
        width: 45,
        height: 45,
        rotate: true,
        child: Image.asset('assets/images/food_delivery.png'),
      ),
      flutterMap.Marker(
        point: source.value,
        width: 40,
        height: 40,
        child: Image.asset('assets/images/location_black3x.png'),
      ),
      flutterMap.Marker(
        point: destination.value,
        width: 40,
        height: 40,
        child: Image.asset('assets/images/location_orange3x.png'),
      )
    ];
  }

  void getOSMPolyline() async {
    try {
      if (currentOrder.value.id == null) return;

      // Every coordinate here was force-unwrapped or read through `?? 0.0`.
      // Both are wrong for the same reason: five of the forty live driver
      // documents have no `location` at all, so this either threw and drew
      // nothing, or set the route's origin to `0, 0` and dragged the map into
      // the Atlantic with it. A leg with no real end is simply not drawn.
      final location.LatLng? here = realMapPoint(driverModel.value.location) ?? mapCentre.lastPoint;

      if (currentOrder.value.status != Constant.driverPending) {
        if (currentOrder.value.status == Constant.orderShipped) {
          final location.LatLng? vendor = realMapPoint(currentOrder.value.vendor);
          if (here != null) current.value = here;
          if (vendor != null) destination.value = vendor;
          animateToSource();
          if (here != null && vendor != null) {
            fetchRoute(here, vendor).then((value) => setOsmMapMarker());
          }
        } else if (currentOrder.value.status == Constant.orderInTransit) {
          final location.LatLng? dropOff = realMapPoint(currentOrder.value.address?.location);
          if (here != null) current.value = here;
          if (dropOff != null) destination.value = dropOff;
          setOsmMapMarker();
          if (here != null && dropOff != null) {
            fetchRoute(here, dropOff).then((value) => setOsmMapMarker());
          }
          animateToSource();
        }
      } else {
        final location.LatLng? customer = realMapPoint(currentOrder.value.author?.location);
        final location.LatLng? vendor = realMapPoint(currentOrder.value.vendor);
        if (customer != null) current.value = customer;
        if (vendor != null) destination.value = vendor;
        animateToSource();
        if (customer != null && vendor != null) {
          fetchRoute(customer, vendor).then((value) => setOsmMapMarker());
        }
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  RxList<location.LatLng> routePoints = <location.LatLng>[].obs;

  /// Fetches the driving line between two points, for the map to draw.
  ///
  /// Everything here used to be unguarded. `package:http` has no default
  /// timeout, so a stalled route server held this future open for as long as
  /// Android kept the socket; and `decoded['routes'][0]` throws outright when
  /// OSRM answers `{"code":"NoRoute"}` — which it does for any pair of points it
  /// cannot connect. Both callers invoke this as `fetchRoute(...).then(...)`
  /// with no `onError`, so that throw became an unhandled asynchronous error
  /// that took the marker refresh down with it and reported nothing.
  ///
  /// The route is decoration: the driver's position, the order and the
  /// addresses are all on screen without it. So every failure here now ends the
  /// same way — no line drawn, screen intact — which is what the working case
  /// already degraded to.
  Future<void> fetchRoute(location.LatLng source, location.LatLng destination) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${source.longitude},${source.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(NetworkTimeout.mapRequest);

      if (response.statusCode != 200) {
        log('home: failed to get route :: ${response.statusCode}');
        return;
      }

      final decoded = json.decode(response.body);
      final routes = decoded is Map ? decoded['routes'] : null;
      if (routes is! List || routes.isEmpty) return;
      final geometry = routes.first['geometry']?['coordinates'];
      if (geometry is! List) return;

      final List<location.LatLng> points = <location.LatLng>[];
      for (final coord in geometry) {
        if (coord is! List || coord.length < 2) continue;
        final lon = coord[0];
        final lat = coord[1];
        if (lat is! num || lon is! num) continue;
        points.add(location.LatLng(lat.toDouble(), lon.toDouble()));
      }

      // Swapped in whole rather than cleared first: clearing and then failing
      // part-way used to leave the map with half a route on it.
      routePoints
        ..clear()
        ..addAll(points);
    } catch (e) {
      log('home: route lookup failed :: $e');
    }
  }
}
