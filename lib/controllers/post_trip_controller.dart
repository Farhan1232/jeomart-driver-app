import 'dart:developer';

import 'package:driver/constant/constant.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/models/driver_trip_model.dart';
import 'package:driver/models/section_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/models/vehicle_type.dart';
import 'package:driver/services/bidding_service.dart';
import 'package:driver/services/driver_trip_service.dart';
import 'package:driver/utils/driver_trip_state.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// The Post a Trip form.
///
/// Only the six fields the client asked for: From, To, Date, Time, a short
/// note and the full vehicle price. There is deliberately no seat count, no
/// per-seat price and no passenger inventory anywhere in it.
class PostTripController extends GetxController {
  final Rx<TextEditingController> fromTextEditController = TextEditingController().obs;
  final Rx<TextEditingController> toTextEditController = TextEditingController().obs;
  final Rx<TextEditingController> dateTextEditController = TextEditingController().obs;
  final Rx<TextEditingController> timeTextEditController = TextEditingController().obs;
  final Rx<TextEditingController> noteTextEditController = TextEditingController().obs;
  final Rx<TextEditingController> priceTextEditController = TextEditingController().obs;

  final Rxn<TripLocation> fromLocation = Rxn<TripLocation>();
  final Rxn<TripLocation> toLocation = Rxn<TripLocation>();
  final Rxn<DateTime> tripDate = Rxn<DateTime>();
  final Rxn<DateTime> tripTime = Rxn<DateTime>();

  RxBool isSaving = false.obs;

  /// The cab section this trip belongs to. Resolved the same way the driver's
  /// cab home screen resolves it, so a multi-section driver posts into the
  /// section they are actually driving in.
  RxString sectionId = ''.obs;
  RxString vehicleTypeName = ''.obs;

  /// Date format used by the parcel search screen, so the two date fields in
  /// this app read the same way.
  static final DateFormat dateFormat = DateFormat('dd-MMM-yyyy');

  @override
  void onInit() {
    super.onInit();
    resolveSection();
  }

  UserModel? get driver => Constant.userModel;

  Future<void> resolveSection() async {
    final UserModel? user = driver;
    final List<String> ids = user?.sectionIds ?? <String>[];
    if (ids.isEmpty) return;

    String resolved = ids.first;
    try {
      final List<SectionModel> cabSections = await FireStoreUtils.getSections('cab-service');
      final Iterable<String> cabIds = cabSections.map((SectionModel s) => s.id ?? '');
      final String match = ids.firstWhere(cabIds.contains, orElse: () => '');
      if (match.isNotEmpty) resolved = match;
    } catch (error) {
      log('PostTripController.resolveSection failed :: $error');
    }
    sectionId.value = resolved;
    await _loadVehicleTypeName(resolved);
  }

  Future<void> _loadVehicleTypeName(String sid) async {
    final Object? details = driver?.vehicleDetails?[sid];
    final String vehicleId = details is Map ? (details['vehicleId']?.toString() ?? '') : '';
    if (sid.isEmpty || vehicleId.isEmpty) return;
    try {
      final List<VehicleType> types = await FireStoreUtils.getCabVehicleType(sid);
      final VehicleType match = types.firstWhere((VehicleType t) => t.id == vehicleId, orElse: () => VehicleType());
      vehicleTypeName.value = match.name ?? '';
    } catch (error) {
      log('PostTripController._loadVehicleTypeName failed :: $error');
    }
  }

  void setFrom(String address, double latitude, double longitude) {
    fromTextEditController.value.text = address;
    fromLocation.value = TripLocation(latitude: latitude, longitude: longitude);
  }

  void setTo(String address, double latitude, double longitude) {
    toTextEditController.value.text = address;
    toLocation.value = TripLocation(latitude: latitude, longitude: longitude);
  }

  /// Date only. `firstDate` is today, so a past date cannot be picked at all
  /// and the validation error is a backstop rather than the first line of
  /// defence.
  Future<void> pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: Get.context!,
      initialDate: tripDate.value ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    tripDate.value = picked;
    dateTextEditController.value.text = dateFormat.format(picked);
    update();
  }

  Future<void> pickTime() async {
    final DateTime now = DateTime.now();
    final TimeOfDay? picked = await showTimePicker(
      context: Get.context!,
      initialTime: tripTime.value != null
          ? TimeOfDay(hour: tripTime.value!.hour, minute: tripTime.value!.minute)
          : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (picked == null) return;
    tripTime.value = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    timeTextEditController.value.text = picked.format(Get.context!);
    update();
  }

  List<TripValidationError> validate({DateTime? now}) {
    return DriverTripValidation.validate(
      fromAddress: fromTextEditController.value.text,
      fromLocation: fromLocation.value,
      toAddress: toTextEditController.value.text,
      toLocation: toLocation.value,
      date: tripDate.value,
      time: tripTime.value,
      note: noteTextEditController.value.text,
      price: priceTextEditController.value.text,
      now: now ?? DateTime.now(),
    );
  }

  /// Human text for the first thing wrong with the form.
  static String messageFor(TripValidationError error) {
    switch (error) {
      case TripValidationError.fromRequired:
        return 'Please select where the trip starts'.tr;
      case TripValidationError.toRequired:
        return 'Please select where the trip ends'.tr;
      case TripValidationError.sameFromAndTo:
        return 'From and To cannot be the same place'.tr;
      case TripValidationError.dateRequired:
        return 'Please select the trip date'.tr;
      case TripValidationError.timeRequired:
        return 'Please select the trip time'.tr;
      case TripValidationError.dateInPast:
        return 'The trip date and time must be in the future'.tr;
      case TripValidationError.noteTooLong:
        return 'The note is too long'.tr;
      case TripValidationError.priceRequired:
        return 'Please enter the full vehicle price'.tr;
      case TripValidationError.priceNotPositive:
        return 'The full vehicle price must be greater than zero'.tr;
    }
  }

  /// Validates, builds and writes the trip.
  ///
  /// Returns true when the trip was published, so the screen can close itself.
  Future<bool> publish() async {
    if (isSaving.value) return false;

    if (!DriverTripService.canPublish) {
      ShowToastDialog.showToast("Your My Trips access has ended".tr);
      return false;
    }

    final List<TripValidationError> errors = validate();
    if (errors.isNotEmpty) {
      ShowToastDialog.showToast(messageFor(errors.first));
      return false;
    }

    final UserModel? user = driver;
    if (user == null || (user.id ?? '').isEmpty) {
      ShowToastDialog.showToast("Something went wrong. Please try again.".tr);
      return false;
    }
    if (sectionId.value.isEmpty) {
      await resolveSection();
      if (sectionId.value.isEmpty) {
        ShowToastDialog.showToast("Something went wrong. Please try again.".tr);
        return false;
      }
    }

    isSaving.value = true;
    ShowToastDialog.showLoader("Please wait".tr);
    try {
      final DateTime now = DateTime.now();
      // The real number of completed rides, not the stored counter, which
      // read 0 for taxi drivers - see BiddingService.completedTrips.
      final num completedTrips = await BiddingService.completedTrips(user);
      final DriverTripModel trip = DriverTripService.buildTrip(
        driver: user,
        sectionId: sectionId.value,
        fromAddress: fromTextEditController.value.text,
        fromLocation: fromLocation.value!,
        toAddress: toTextEditController.value.text,
        toLocation: toLocation.value!,
        departure: DriverTripValidation.combine(tripDate.value!, tripTime.value!),
        note: noteTextEditController.value.text,
        fullVehiclePrice: double.parse(priceTextEditController.value.text.trim()),
        now: now,
        vehicleTypeName: vehicleTypeName.value,
        completedTrips: completedTrips,
      );

      final bool published = await DriverTripService.publishTrip(trip);
      ShowToastDialog.closeLoader();
      if (published) {
        ShowToastDialog.showToast("Trip published".tr);
        return true;
      }
      ShowToastDialog.showToast("Something went wrong. Please try again.".tr);
      return false;
    } catch (error) {
      ShowToastDialog.closeLoader();
      log('PostTripController.publish failed :: $error');
      ShowToastDialog.showToast("Something went wrong. Please try again.".tr);
      return false;
    } finally {
      isSaving.value = false;
    }
  }
}
