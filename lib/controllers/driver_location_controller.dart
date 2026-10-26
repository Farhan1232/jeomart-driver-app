import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/app/owner_screen/driver_order_list.dart';
import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/themes/round_button_fill.dart';
import 'package:driver/utils/driver_map_location.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as flutterMap;
import 'package:latlong2/latlong.dart' as latLng2;

class DriverLocationController extends GetxController {
  /// Live positions of this owner's drivers.
  ///
  /// Held so it is cancelled when the screen closes instead of running for the
  /// rest of the session.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _driverListSub;

  @override
  void onClose() {
    _driverListSub?.cancel();
    mapLocation.dispose();
    super.onClose();
  }

  RxBool isLoading = true.obs;
  RxList<UserModel> driverList = <UserModel>[].obs;
  RxSet<Marker> markers = <Marker>{}.obs;

  /// OSM map data
  final flutterMap.MapController osmMapController = flutterMap.MapController();
  RxList<flutterMap.Marker> osmMarkers = <flutterMap.Marker>[].obs;
  Rx<latLng2.LatLng> current = const latLng2.LatLng(12.9716, 77.5946).obs;

  /// Moves the camera, and seeds where it starts.
  ///
  /// `current` was a hardcoded Bangalore and the map was built with
  /// `initialCenter: current.value` — which flutter_map reads **once**. So
  /// assigning the first driver's position to `current` further down repainted
  /// nothing, and an owner outside Bangalore watched their fleet from 2,000 km
  /// away with no way to be moved. The camera is steered explicitly now, and
  /// the map opens on the owner's own position rather than a guess.
  late final DriverMapCentre mapCentre = DriverMapCentre(
    osmMapController,
    onGoogleCamera: _moveGoogleCamera,
  );
  late final DriverMapLocation mapLocation = DriverMapLocation(onFix: _onOwnerFix);

  latLng2.LatLng? _mapSeed;

  /// Read once by `MapOptions.initialCenter`.
  latLng2.LatLng get initialMapCentre => mapCentre.lastPoint ?? _mapSeed ?? current.value;

  double get initialMapZoom => (mapCentre.lastPoint ?? _mapSeed) != null ? 12 : 4;

  void onMapReady() => mapCentre.mapReady();

  Future<void> _moveGoogleCamera(latLng2.LatLng point) async {
    if (!mapController.isCompleted) return;
    final GoogleMapController google = await mapController.future;
    await google.animateCamera(
      CameraUpdate.newLatLng(LatLng(point.latitude, point.longitude)),
    );
  }

  /// The owner's own position, used only until a driver is on the board — once
  /// there is a fleet to watch, the fleet is what the owner wants centred.
  void _onOwnerFix(latLng2.LatLng point) {
    current.value = point;
    if (driverList.isEmpty) mapCentre.moveTo(point, zoom: 12);
  }

  BitmapDescriptor? driverIcon;
  final Completer<GoogleMapController> mapController = Completer();

  @override
  void onInit() {
    super.onInit();
    // Resolved before the first frame: the map is built in it and
    // `initialCenter` is read exactly once.
    _mapSeed = mapLocation.seed() ?? realMapPoint(Constant.userModel?.location);
    unawaited(mapLocation.start());
    getDriverList();
  }

  Future<void> getDriverList() async {
    isLoading.value = true;
    await _loadDriverIcon();

    _driverListSub?.cancel();
    _driverListSub = FireStoreUtils.fireStore.collection(CollectionName.users).where("ownerId", isEqualTo: FireStoreUtils.getCurrentUid()).where("isOwner", isEqualTo: false).snapshots().listen((
      event,
    ) {
      driverList.value = event.docs.map((e) => UserModel.fromJson(e.data())).toList();
      updateMarkers();
    });

    isLoading.value = false;
  }

  Future<void> _loadDriverIcon() async {
    final Uint8List driverBytes = await Constant().getBytesFromAsset('assets/images/ic_cab.png', 70);
    driverIcon = BitmapDescriptor.fromBytes(driverBytes);
  }

  /// Update both Google Map + OSM markers
  void updateMarkers() {
    final newMarkers = <Marker>{};
    final newOsmMarkers = <flutterMap.Marker>[];

    for (var driver in driverList) {
      final lat = driver.location?.latitude;
      final lng = driver.location?.longitude;
      if (lat != null && lng != null) {
        // Google Map Marker
        newMarkers.add(
          Marker(
            markerId: MarkerId(driver.id ?? ''),
            position: LatLng(lat, lng),
            rotation: double.tryParse(driver.rotation.toString()) ?? 0,
            anchor: const Offset(0.5, 0.5),
            flat: true,
            icon: driverIcon ?? BitmapDescriptor.defaultMarker,
            onTap: () => _showDriverBottomSheet(Get.context!, driver),
          ),
        );

        // OSM Marker
        newOsmMarkers.add(flutterMap.Marker(
          point: latLng2.LatLng(lat, lng),
          width: 60,
          height: 60,
          child: GestureDetector(
            onTap: () => _showDriverBottomSheet(Get.context!, driver),
            child: Image.asset('assets/images/ic_cab.png', width: 45),
          ),
        ));
      }
    }

    // ignore: invalid_use_of_protected_member
    markers.value = newMarkers;
    osmMarkers.value = newOsmMarkers;

    if (driverList.isNotEmpty) {
      // `realMapPoint` rather than `first.location!.latitude!`: that pair of
      // force-unwraps threw inside a snapshot callback for any driver holding a
      // location with a null coordinate, and it accepted the `0.01, 0.01`
      // placeholder that three of this fleet's drivers carry — centring the
      // board on Null Island. Falls through to the next driver that has a real
      // position instead of giving up on the first.
      for (final UserModel driver in driverList) {
        final latLng2.LatLng? point = realMapPoint(driver.location);
        if (point == null) continue;
        current.value = point;
        mapCentre.moveTo(point, zoom: 12);
        break;
      }
    }
  }

  /// Show driver bottom sheet
  void _showDriverBottomSheet(BuildContext context, UserModel driver) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  ClipOval(
                    child: NetworkImageWidget(
                      imageUrl: driver.profilePictureURL ?? "",
                      height: 55,
                      width: 55,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(driver.fullName(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text("Email: ${driver.email ?? '-'}"),
                        Text("Phone: ${driver.countryCode ?? ''} ${driver.phoneNumber ?? ''}"),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: RoundedButtonFill(
                      title: "Call".tr,
                      height: 5,
                      width: 100,
                      borderRadius: 10,
                      color: AppThemeData.primary300,
                      textColor: AppThemeData.grey50,
                      onPress: () async {
                        Constant.makePhoneCall(driver.phoneNumber.toString());
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: RoundedButtonFill(
                      title: "View Booking".tr,
                      height: 5,
                      width: 100,
                      borderRadius: 10,
                      color: AppThemeData.driverApp300,
                      textColor: AppThemeData.grey50,
                      onPress: () async {
                        Get.to(DriverOrderList(), arguments: {
                          "driverId": driver.id,
                          "serviceType": driver.serviceTypes?.first,
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  /// Move camera for Google Map
  Future<void> moveCameraToFirstDriver(GoogleMapController mapController) async {
    if (driverList.isNotEmpty) {
      final firstDriver = driverList.first;
      if (firstDriver.location?.latitude != null && firstDriver.location?.longitude != null) {
        final position = CameraPosition(
          target: LatLng(firstDriver.location!.latitude!, firstDriver.location!.longitude!),
          zoom: 15,
        );
        await mapController.animateCamera(CameraUpdate.newCameraPosition(position));
      }
    }
  }

  /// Animate OSM map
  // `animateToSource()` used to live here.
  //
  // It moved the camera to `driverList.first.location!.latitude!` — a pair of
  // force-unwraps behind a null check on the *holder* rather than on the
  // coordinates, so a driver whose location had a null field threw, and one
  // carrying the `0.01, 0.01` placeholder moved the board to Null Island. Its
  // only caller was a post-frame callback that re-ran on every repaint of this
  // screen, which is what made the owner's board snap back while they were
  // panning it. Both are gone: `mapCentre` steers the camera now, from the
  // checked point chosen in `updateMarkers`.
}
