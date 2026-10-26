import 'dart:async';

import 'package:driver/constant/constant.dart';
import 'package:driver/controllers/post_trip_controller.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/themes/round_button_fill.dart';
import 'package:driver/themes/text_field_widget.dart';
import 'package:driver/themes/theme_controller.dart';
import 'package:driver/utils/driver_trip_state.dart';
import 'package:driver/utils/nearby_place_address.dart';
import 'package:driver/widget/osm_map/map_picker_page.dart';
import 'package:driver/widget/osm_map/place_model.dart';
import 'package:driver/widget/place_picker/location_picker_screen.dart';
import 'package:driver/widget/place_picker/selected_location_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geocoding/geocoding.dart';
import 'package:get/get.dart';

/// Post a Trip.
///
/// From and To use the app's existing location infrastructure unchanged - the
/// OSM `MapPickerPage` or the Google `LocationPickerScreen`, chosen by the same
/// `Constant.selectedMapType` switch the parcel search screen reads - so there
/// is no second location system and no second set of permissions.
class PostTripScreen extends StatelessWidget {
  const PostTripScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeController themeController = Get.find<ThemeController>();
    return Obx(() {
      final bool isDark = themeController.isDark.value;
      return GetX<PostTripController>(
        init: PostTripController(),
        builder: (PostTripController controller) {
          return Scaffold(
            backgroundColor: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
            appBar: AppBar(
              backgroundColor: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
              centerTitle: false,
              titleSpacing: 0,
              iconTheme: IconThemeData(color: isDark ? AppThemeData.greyDark900 : AppThemeData.grey900, size: 20),
              title: Text(
                "Post a Trip".tr,
                style: TextStyle(color: isDark ? AppThemeData.grey50 : AppThemeData.grey900, fontSize: 18, fontFamily: AppThemeData.medium),
              ),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFieldWidget(
                    title: 'From'.tr,
                    hintText: 'Where does the trip start?'.tr,
                    controller: controller.fromTextEditController.value,
                    readOnly: true,
                    onClick: () => _pickLocation(context, isFrom: true, controller: controller),
                    prefix: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SvgPicture.asset("assets/icons/ic_source.svg"),
                    ),
                  ),
                  TextFieldWidget(
                    title: 'To'.tr,
                    hintText: 'Where does the trip end?'.tr,
                    controller: controller.toTextEditController.value,
                    readOnly: true,
                    onClick: () => _pickLocation(context, isFrom: false, controller: controller),
                    prefix: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SvgPicture.asset("assets/icons/ic_destination.svg"),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFieldWidget(
                          title: 'Date'.tr,
                          hintText: 'Select Date'.tr,
                          controller: controller.dateTextEditController.value,
                          readOnly: true,
                          onClick: controller.pickDate,
                          prefix: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: SvgPicture.asset("assets/icons/ic_calender.svg", height: 18, width: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFieldWidget(
                          title: 'Time'.tr,
                          hintText: 'Select Time'.tr,
                          controller: controller.timeTextEditController.value,
                          readOnly: true,
                          onClick: controller.pickTime,
                          prefix: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: SvgPicture.asset("assets/icons/ic_time.svg", height: 18, width: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextFieldWidget(
                    title: 'Small note to customers'.tr,
                    hintText: 'For example: leaving from the main bus stand'.tr,
                    controller: controller.noteTextEditController.value,
                    maxLine: 3,
                    maxLength: DriverTripValidation.maxNoteLength,
                    textInputType: TextInputType.multiline,
                  ),
                  TextFieldWidget(
                    title: 'Full Vehicle Price'.tr,
                    hintText: 'Price for the whole vehicle'.tr,
                    controller: controller.priceTextEditController.value,
                    textInputType: const TextInputType.numberWithOptions(decimal: true),
                    prefix: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        Constant.currencyModel?.symbol ?? '',
                        style: AppThemeData.semiBoldTextStyle(fontSize: 16, color: isDark ? AppThemeData.grey100 : AppThemeData.grey800),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      "This price is for the whole vehicle. The first customer who books takes the whole trip.".tr,
                      style: AppThemeData.regularTextStyle(fontSize: 13, color: isDark ? AppThemeData.grey300 : AppThemeData.grey600),
                    ),
                  ),
                  Text(
                    "${'This trip will be shown to customers for'.tr} ${Constant.driverTripSettings.visibilityHours} ${'hours'.tr}",
                    style: AppThemeData.regularTextStyle(fontSize: 13, color: isDark ? AppThemeData.grey300 : AppThemeData.grey600),
                  ),
                  const SizedBox(height: 20),
                  RoundedButtonFill(
                    title: "Publish Trip".tr,
                    height: 5.5,
                    color: AppThemeData.primary300,
                    textColor: AppThemeData.grey50,
                    onPress: () async {
                      FocusScope.of(context).unfocus();
                      final bool published = await controller.publish();
                      if (published) Get.back(result: true);
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  /// The project's own two location pickers, picked by the same switch every
  /// other From/To field in these apps uses.
  Future<void> _pickLocation(BuildContext context, {required bool isFrom, required PostTripController controller}) async {
    if (Constant.selectedMapType == 'osm') {
      final PlaceModel? result = await Get.to(() => MapPickerPage());
      if (result == null) return;
      final String address = result.address.toString();
      final double lat = result.coordinates.latitude;
      final double lng = result.coordinates.longitude;
      if (isFrom) {
        controller.setFrom(address, lat, lng);
      } else {
        controller.setTo(address, lat, lng);
      }
      unawaited(_addNearbyPlace(controller, isFrom: isFrom, lat: lat, lng: lng));
      return;
    }

    final dynamic value = await Get.to(() => const LocationPickerScreen());
    if (value == null) return;
    final SelectedLocationModel selected = value as SelectedLocationModel;
    if (selected.latLng == null) return;
    final String address = _formatPlacemark(selected.address);
    if (isFrom) {
      controller.setFrom(address, selected.latLng!.latitude, selected.latLng!.longitude);
    } else {
      controller.setTo(address, selected.latLng!.latitude, selected.latLng!.longitude);
    }
  }

  /// Puts the nearest named place in front of a From/To whose street has no
  /// name in OpenStreetMap ("Kohat, Tehsil Kohat, ..." becomes "Near KDA PARK,
  /// Kohat, ..."). See [NearbyPlaceAddress]. Only applied while the same point
  /// and the same text are still selected.
  Future<void> _addNearbyPlace(PostTripController controller, {required bool isFrom, required double lat, required double lng}) async {
    final TextEditingController field = isFrom ? controller.fromTextEditController.value : controller.toTextEditController.value;
    final String before = field.text;
    final String better = await NearbyPlaceAddress.describe(lat, lng, before);
    if (better == before) return;
    final TripLocation? now = isFrom ? controller.fromLocation.value : controller.toLocation.value;
    if (now?.latitude != lat || now?.longitude != lng || field.text != before) return;
    field.text = better;
  }

  /// The same readable address the parcel search screen builds from a
  /// `Placemark`, kept identical so two screens do not format one place two
  /// different ways.
  String _formatPlacemark(Placemark? place) {
    return '${place?.name ?? ''}, ${place?.street ?? ''}, ${place?.subLocality ?? ''}, '
            '${place?.locality ?? ''}, ${place?.administrativeArea ?? ''}, ${place?.postalCode ?? ''}, ${place?.country ?? ''}'
        .replaceAll(RegExp(r', ,|, , ,'), ',')
        .trim()
        .replaceAll(RegExp(r',+$'), '');
  }
}
