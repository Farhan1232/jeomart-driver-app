import 'package:driver/constant/constant.dart';
import 'package:driver/controllers/driver_location_controller.dart';
import 'package:driver/themes/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as flutterMap;
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:driver/widget/osm_map/osm_tile_layer.dart';

class DriverLocationScreen extends StatelessWidget {
  const DriverLocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    final isDark = themeController.isDark.value;
    return GetX(
        init: DriverLocationController(),
        builder: (controller) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                "Driver Locations",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              backgroundColor: isDark ? Colors.black : Colors.white,
              iconTheme: IconThemeData(
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            body: controller.isLoading.value
                ? Constant.loader()
                : Constant.selectedMapType == "osm"
                    ? Obx(() {
                        // The post-frame `animateToSource()` that used to sit
                        // here ran on **every rebuild** of this Obx — so each
                        // driver movement snapped the camera back to the first
                        // driver and an owner could not pan the board without it
                        // jumping out from under them. The camera is steered
                        // once, from the controller, through `onMapReady`.
                        return flutterMap.FlutterMap(
                          mapController: controller.osmMapController,
                          options: flutterMap.MapOptions(
                            // Read once by flutter_map, which is why assigning
                            // to `current` could never move this map.
                            initialCenter: controller.initialMapCentre,
                            initialZoom: controller.initialMapZoom,
                            onMapReady: controller.onMapReady,
                          ),
                          children: [
                            osmTileLayer(),
                            flutterMap.MarkerLayer(markers: controller.osmMarkers),
                          ],
                        );
                      })
                    : GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            controller.initialMapCentre.latitude,
                            controller.initialMapCentre.longitude,
                          ),
                          zoom: controller.initialMapZoom,
                        ),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        markers: controller.markers.toSet(),
                        onMapCreated: (GoogleMapController mapController) {
                          controller.mapController.complete(mapController);
                          // Wait for markers to load
                          Future.delayed(const Duration(milliseconds: 500), () async {
                            await controller.moveCameraToFirstDriver(mapController);
                          });
                        },
                      ),
          );
        });
  }
}
