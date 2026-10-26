import 'dart:async';
import 'dart:developer';
import 'dart:convert';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:driver/utils/network_timeout.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart' as osm;
import '../constant/collection_name.dart';
import '../constant/constant.dart';
import '../models/cab_order_model.dart';
import '../models/user_model.dart';
import '../themes/app_them_data.dart';
import '../utils/fire_store_utils.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CabOrderDetailsController extends GetxController {
  Rx<CabOrderModel> cabOrder = CabOrderModel().obs;

  RxBool isLoading = false.obs;

  // Google Maps Data
  RxSet<gmap.Marker> googleMarkers = <gmap.Marker>{}.obs;
  RxSet<gmap.Polyline> googlePolylines = <gmap.Polyline>{}.obs;

  // OSM Data
  RxList<osm.LatLng> osmPolyline = <osm.LatLng>[].obs;

  final String googleApiKey = Constant.mapAPIKey;

  final Rx<UserModel?> driverUser = Rx<UserModel?>(null);

  /// Follows the ride this screen was opened on.
  ///
  /// The screen used to draw the copy of the ride it was handed and never look
  /// again, so a booking opened from the list froze at whatever status it had
  /// when it was tapped. One document, cancelled with the screen.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _orderSub;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args != null) {
      cabOrder.value = args['cabOrderModel'] as CabOrderModel;
      calculateTotalAmount();
      _setMarkers();
      _getGoogleRoute();
      _getOsmRoute();
      _watchOrder();
    }
  }

  @override
  void onClose() {
    _orderSub?.cancel();
    super.onClose();
  }

  void _watchOrder() {
    final String id = cabOrder.value.id ?? '';
    if (id.isEmpty) return;
    _orderSub = FireStoreUtils.fireStore.collection(CollectionName.ridesBooking).doc(id).snapshots().listen((snapshot) {
      final Map<String, dynamic>? data = snapshot.data();
      if (data == null) return;
      cabOrder.value = CabOrderModel.fromJson(data);
      calculateTotalAmount();
    }, onError: (Object error) => log('cab order details listener error: $error'));
  }

  String formatDate(Timestamp timestamp) {
    final dateTime = timestamp.toDate();
    return DateFormat("dd MMM yyyy, hh:mm a").format(dateTime);
  }

  /// The line under "Booking Date:".
  ///
  /// `scheduleDateTime` is only written for a ride booked for later, so it is
  /// null on every ride hailed for now; `createdAt` is the date the list screen
  /// already prints for those. An empty string rather than a placeholder when
  /// neither exists - the label alone reads better than "Booking Date: N/A".
  String get bookingDate {
    final Timestamp? when = cabOrder.value.scheduleDateTime ?? cabOrder.value.createdAt;
    return when == null ? '' : formatDate(when);
  }

  RxDouble subTotal = 0.0.obs;
  RxDouble discount = 0.0.obs;
  RxDouble taxAmount = 0.0.obs;
  RxDouble totalAmount = 0.0.obs;
  RxDouble adminCommission = 0.0.obs;

  Future<void> fetchDriverDetails() async {
    if (cabOrder.value.driverId != null) {
      await FireStoreUtils.getUserProfile(cabOrder.value.driverId ?? '').then((value) {
        if (value != null) {
          driverUser.value = value;
        }
      });
    }
  }

  /// The fare breakdown for this ride.
  ///
  /// Every figure here is optional on a real ride document and this runs from
  /// `onInit`, so one missing field used to throw before the screen had a
  /// chance to build - which is why opening any order drew a blank screen.
  /// `adminCommission` is null on every ride placed while the admin has the
  /// section's commission switched off, which on the live project is most of
  /// them; `taxSetting` is null on the rest.
  void calculateTotalAmount() {
    taxAmount = 0.0.obs;
    discount = 0.0.obs;
    subTotal.value = double.tryParse(cabOrder.value.subTotal?.toString() ?? '') ?? 0.0;
    discount.value = double.tryParse(cabOrder.value.discount ?? '') ?? 0.0;

    for (var element in cabOrder.value.taxSetting ?? []) {
      taxAmount.value = (taxAmount.value + Constant.calculateTax(amount: (subTotal.value - discount.value).toString(), taxModel: element));
    }

    final String commission = cabOrder.value.adminCommission ?? '';
    if (commission.isNotEmpty) {
      adminCommission.value = Constant.calculateAdminCommission(
          amount: (subTotal.value - discount.value).toString(), adminCommissionType: cabOrder.value.adminCommissionType.toString(), adminCommission: commission);
    }

    totalAmount.value = (subTotal.value - discount.value) + taxAmount.value;
    update();
  }

  /// Whether this ride carries both ends of the journey as coordinates.
  ///
  /// A ride can reach this screen without them, and every map call below needs
  /// all four numbers, so they are asked for once here rather than asserted
  /// four times over.
  bool get hasRoute =>
      cabOrder.value.sourceLocation?.latitude != null &&
      cabOrder.value.sourceLocation?.longitude != null &&
      cabOrder.value.destinationLocation?.latitude != null &&
      cabOrder.value.destinationLocation?.longitude != null;

  void _setMarkers() {
    if (!hasRoute) return;
    final sourceLat = cabOrder.value.sourceLocation!.latitude;
    final sourceLng = cabOrder.value.sourceLocation!.longitude;
    final destLat = cabOrder.value.destinationLocation!.latitude;
    final destLng = cabOrder.value.destinationLocation!.longitude;

    // ignore: invalid_use_of_protected_member
    googleMarkers.value = {
      gmap.Marker(
        markerId: const gmap.MarkerId('source'),
        position: gmap.LatLng(sourceLat!, sourceLng!),
        icon: gmap.BitmapDescriptor.defaultMarkerWithHue(gmap.BitmapDescriptor.hueGreen),
      ),
      gmap.Marker(
        markerId: const gmap.MarkerId('destination'),
        position: gmap.LatLng(destLat!, destLng!),
        icon: gmap.BitmapDescriptor.defaultMarkerWithHue(gmap.BitmapDescriptor.hueRed),
      ),
    };
  }

  ///Google Directions API
  ///
  /// A route line is decoration on a screen whose job is the fare and the
  /// addresses, and this runs unawaited from `onInit`. A refused key, an
  /// offline phone or a reply without a `routes` array must therefore leave the
  /// rest of the screen alone rather than throw into nothing.
  Future<void> _getGoogleRoute() async {
    if (!hasRoute) return;
    final src = cabOrder.value.sourceLocation!;
    final dest = cabOrder.value.destinationLocation!;

    final url = "https://maps.googleapis.com/maps/api/directions/json?origin=${src.latitude},${src.longitude}&destination=${dest.latitude},${dest.longitude}&key=$googleApiKey";

    try {
      final response = await http.get(Uri.parse(url)).timeout(NetworkTimeout.mapRequest);
      final data = jsonDecode(response.body);
      final routes = data is Map ? data["routes"] : null;
      if (routes is! List || routes.isEmpty) return;

      final points = routes[0]["overview_polyline"]["points"];
      final polylinePoints = PolylinePoints.decodePolyline(points);

      final polylineCoords = polylinePoints.map((p) => gmap.LatLng(p.latitude, p.longitude)).toList();

      // ignore: invalid_use_of_protected_member
      googlePolylines.value = {gmap.Polyline(polylineId: const gmap.PolylineId("google_route"), color: AppThemeData.onDemandDark100, width: 5, points: polylineCoords)};
    } catch (_) {
      // No line drawn. The addresses and the fare are already on screen.
    }
  }

  /// OSM Route (OSRM API)
  Future<void> _getOsmRoute() async {
    if (!hasRoute) return;
    final src = cabOrder.value.sourceLocation!;
    final dest = cabOrder.value.destinationLocation!;

    final url = "https://router.project-osrm.org/route/v1/driving/${src.longitude},${src.latitude};${dest.longitude},${dest.latitude}?overview=full&geometries=geojson";

    try {
      final response = await http.get(Uri.parse(url)).timeout(NetworkTimeout.mapRequest);
      final data = jsonDecode(response.body);
      final routes = data is Map ? data["routes"] : null;
      if (routes is! List || routes.isEmpty) return;

      final coords = routes[0]["geometry"]["coordinates"] as List<dynamic>;

      osmPolyline.value = coords.map((c) => osm.LatLng(c[1].toDouble(), c[0].toDouble())).toList();
    } catch (_) {
      // As above.
    }
  }
}
