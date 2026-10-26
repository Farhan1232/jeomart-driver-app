import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/app/auth_screen/login_screen.dart';
import 'package:driver/app/cab_screen/cab_dashboard_screen.dart';
import 'package:driver/app/dash_board_screen/dash_board_screen.dart';
import 'package:driver/app/multi_service/multi_service_dashboard_screen.dart';
import 'package:driver/app/owner_screen/owner_dashboard_screen.dart';
import 'package:driver/app/parcel_screen/parcel_dashboard_screen.dart';
import 'package:driver/app/rental_service/rental_dashboard_screen.dart';
import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/models/car_makes.dart';
import 'package:driver/models/car_model.dart';
import 'package:driver/models/section_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/models/vehicle_type.dart';
import 'package:driver/models/zone_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/city_filter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SignupController extends GetxController {
  Rx<TextEditingController> firstNameEditingController = TextEditingController().obs;
  Rx<TextEditingController> lastNameEditingController = TextEditingController().obs;
  Rx<TextEditingController> emailEditingController = TextEditingController().obs;
  Rx<TextEditingController> phoneNUmberEditingController = TextEditingController().obs;
  Rx<TextEditingController> countryCodeEditingController = TextEditingController(text: Constant.defaultCountryCode).obs;
  Rx<TextEditingController> countryISOCodeEditingController = TextEditingController(text: Constant.defaultCountryCode).obs;
  Rx<TextEditingController> passwordEditingController = TextEditingController().obs;
  Rx<TextEditingController> conformPasswordEditingController = TextEditingController().obs;
  Rx<TextEditingController> carPlatNumberEditingController = TextEditingController().obs;

  RxBool passwordVisible = true.obs;
  RxBool conformPasswordVisible = true.obs;

  RxString type = "".obs;
  Rx<UserModel> userModel = UserModel().obs;

  RxList<ZoneModel> zoneList = <ZoneModel>[].obs;
  Rx<ZoneModel> selectedZone = ZoneModel().obs;

  /// All active sections loaded from Firestore (no service filter)
  RxList<SectionModel> allSections = <SectionModel>[].obs;

  /// Sections the driver has selected during registration
  RxList<SectionModel> selectedSections = <SectionModel>[].obs;

  /// Vehicle types per section (loaded only for cab-service / rental-service sections)
  RxMap<String, List<VehicleType>> vehicleTypesPerSection = <String, List<VehicleType>>{}.obs;
  RxMap<String, VehicleType> selectedVehiclePerSection = <String, VehicleType>{}.obs;

  /// Shared car makes list (loaded once from Firestore)
  RxList<CarMakes> carMakesList = <CarMakes>[].obs;

  /// Per-section car details
  final Map<String, Rx<CarMakes>> selectedCarMakesPerSection = {};
  final Map<String, RxList<CarModel>> carModelListPerSection = {};
  final Map<String, Rx<CarModel>> selectedCarModelPerSection = {};
  final Map<String, Rx<TextEditingController>> carPlatePerSection = {};

  RxString selectedValue = "Individual".obs;

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool sectionNeedsVehicle(SectionModel section) => section.serviceTypeFlag == 'cab-service' || section.serviceTypeFlag == 'rental-service';

  bool get hasVehicleBasedSection => selectedSections.any(sectionNeedsVehicle);

  bool isSectionSelected(SectionModel section) => selectedSections.any((s) => s.id == section.id);

  /// Sections visible based on role selection.
  /// Company/Owner cannot register for delivery-service — only cab, parcel, rental.
  List<SectionModel> get visibleSections {
    if (selectedValue.value == 'Company') {
      return allSections.where((s) => s.serviceTypeFlag != 'delivery-service').toList();
    }
    return allSections;
  }

  /// Called when switching between Individual / Company to deselect
  /// any sections that are no longer visible (delivery-service for Company).
  void onRoleChanged(String role) {
    selectedValue.value = role;
    if (role == 'Company') {
      // Remove any delivery-service sections from selection
      final deliverySections = selectedSections.where((s) => s.serviceTypeFlag == 'delivery-service').toList();
      for (final s in deliverySections) {
        selectedSections.removeWhere((sec) => sec.id == s.id);
      }
    }
    update();
  }

  /// Returns a human-readable label for a section's serviceTypeFlag.
  String serviceFlagLabel(String? flag) {
    switch (flag) {
      case 'cab-service':
        return 'Cab';
      case 'parcel_delivery':
        return 'Parcel';
      case 'rental-service':
        return 'Rental';
      default:
        return 'Delivery';
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void onInit() {
    getArgument();
    ever<ZoneModel>(selectedZone, (_) => _refilterVehicleTypesForZone());
    super.onInit();
  }

  Future<void> getArgument() async {
    dynamic argumentData = Get.arguments;
    if (argumentData != null) {
      type.value = argumentData['type'];
      userModel.value = argumentData['userModel'];
      if (type.value == "mobileNumber") {
        phoneNUmberEditingController.value.text = userModel.value.phoneNumber ?? "";
        countryCodeEditingController.value.text = userModel.value.countryCode ?? Constant.defaultCountryCode;
        countryISOCodeEditingController.value.text = userModel.value.countryISOCode ?? Constant.defaultCountryCode;
      } else if (type.value == "google" || type.value == "apple") {
        emailEditingController.value.text = userModel.value.email ?? "";
        firstNameEditingController.value.text = userModel.value.firstName ?? "";
        lastNameEditingController.value.text = userModel.value.lastName ?? "";
      }
    }

    await Future.wait([
      FireStoreUtils.getZone().then((v) {
        if (v != null) zoneList.value = v;
      }),
      FireStoreUtils.getCarMakes().then((v) => carMakesList.value = v),
      FireStoreUtils.getAllActiveSections().then((v) => allSections.value = v),
    ]);
  }

  // ── Section toggle ─────────────────────────────────────────────────────────

  Future<void> toggleSection(SectionModel section) async {
    if (isSectionSelected(section)) {
      if (selectedSections.length == 1) {
        ShowToastDialog.showToast("At least one section must be selected.".tr);
        return;
      }
      selectedSections.removeWhere((s) => s.id == section.id);
      vehicleTypesPerSection.remove(section.id);
      selectedVehiclePerSection.remove(section.id);
      selectedCarMakesPerSection.remove(section.id);
      carModelListPerSection.remove(section.id);
      selectedCarModelPerSection.remove(section.id);
      carPlatePerSection.remove(section.id);
    } else {
      selectedSections.add(section);
      if (sectionNeedsVehicle(section)) {
        await _loadVehicleTypesForSection(section);
        // Init per-section car details
        selectedCarMakesPerSection[section.id!] = Rx<CarMakes>(CarMakes());
        carModelListPerSection[section.id!] = <CarModel>[].obs;
        selectedCarModelPerSection[section.id!] = Rx<CarModel>(CarModel());
        carPlatePerSection[section.id!] = Rx<TextEditingController>(TextEditingController());
      }
    }
    update();
  }

  Future<void> _loadVehicleTypesForSection(SectionModel section) async {
    ShowToastDialog.showLoader("Please wait".tr);
    List<VehicleType> types;
    if (section.serviceTypeFlag == 'cab-service') {
      types = await FireStoreUtils.getCabVehicleType(section.id.toString());
    } else {
      types = await FireStoreUtils.getRentalVehicleType(section.id.toString());
    }
    // Only the vehicle types offered in the chosen zone (admin panel).
    _allVehicleTypesPerSection[section.id!] = types;
    types = _inSelectedZone(types);
    vehicleTypesPerSection[section.id!] = types;
    if (types.isNotEmpty) selectedVehiclePerSection[section.id!] = types.first;
    ShowToastDialog.closeLoader();
    update();
  }

  // ── City (admin panel: vehicle types per city) ────────────────────────────

  /// Vehicle types as read, before the city filter, so a zone change can
  /// filter them again.
  final Map<String, List<VehicleType>> _allVehicleTypesPerSection = {};
  String? _vehicleTypesZoneId;

  List<VehicleType> _inSelectedZone(List<VehicleType> types) {
    _vehicleTypesZoneId = selectedZone.value.id;
    return CityFilter.keep(types, selectedZone.value.id, zoneIdsOf: (VehicleType t) => t.zoneIds, idOf: (VehicleType t) => t.id);
  }

  void _refilterVehicleTypesForZone() {
    if (selectedZone.value.id == _vehicleTypesZoneId) return;
    _allVehicleTypesPerSection.forEach((String sid, List<VehicleType> all) {
      if (!vehicleTypesPerSection.containsKey(sid)) return;
      final List<VehicleType> types = _inSelectedZone(all);
      vehicleTypesPerSection[sid] = types;
      final VehicleType? current = selectedVehiclePerSection[sid];
      if (types.isEmpty) {
        selectedVehiclePerSection.remove(sid);
      } else if (current == null || !types.any((VehicleType t) => t.id == current.id)) {
        selectedVehiclePerSection[sid] = types.first;
      }
    });
    _vehicleTypesZoneId = selectedZone.value.id;
    update();
  }

  Future<void> getCarModelForSection(String sectionId) async {
    ShowToastDialog.showLoader("Please wait".tr);
    final carMakes = selectedCarMakesPerSection[sectionId]?.value;
    carModelListPerSection[sectionId]?.clear();
    selectedCarModelPerSection[sectionId]?.value = CarModel();
    if (carMakes?.name != null) {
      await FireStoreUtils.getCarModel(carMakes!.name.toString()).then((v) {
        carModelListPerSection[sectionId]?.value = v;
      });
    }
    ShowToastDialog.closeLoader();
  }

  // ── Sign up ────────────────────────────────────────────────────────────────

  Future<void> signUpWithEmailAndPassword() async {
    await signUp();
  }

  Future<void> signUp() async {
    if (selectedSections.isEmpty) {
      ShowToastDialog.showToast("Please select at least one section.".tr);
      return;
    }
    ShowToastDialog.showLoader("Please wait".tr);

    await _loadVerificationRules();

    if (type.value == "google" || type.value == "apple" || type.value == "mobileNumber") {
      _populateUserModel();
      // A new account writes its starting Available Status; every later save
      // leaves it to the switch. See DriverOnlineWrite.
      await FireStoreUtils.updateUser(userModel.value, includeOnlineStatus: true);
      _navigateAfterSignup(userModel.value);
    } else {
      try {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailEditingController.value.text.trim(),
          password: passwordEditingController.value.text.trim(),
        );
        if (credential.user != null) {
          userModel.value.id = credential.user!.uid;
          _populateUserModel();
          // As above: the starting status, written once, at creation.
          await FireStoreUtils.updateUser(userModel.value, includeOnlineStatus: true);
          _navigateAfterSignup(userModel.value);
        }
      } on FirebaseAuthException catch (e) {
        if (e.code == 'weak-password') {
          ShowToastDialog.showToast("The password provided is too weak.".tr);
        } else if (e.code == 'email-already-in-use') {
          ShowToastDialog.showToast("The account already exists for that email.".tr);
        } else if (e.code == 'invalid-email') {
          ShowToastDialog.showToast("Enter email is Invalid".tr);
        }
        print(e);
      } catch (e) {
        print(e);
        ShowToastDialog.showToast(e.toString());
      }
    }

    ShowToastDialog.closeLoader();
  }

  /// The admin's document-verification switches, read from the server now.
  ///
  /// [_populateUserModel] copies them onto the new account once, for good. The
  /// launch-time copy can be a stale one from the device cache, and its
  /// default is "off", so a phone that had seen verification off - or could not
  /// read the setting at all - signed the driver up already approved. An
  /// answer that cannot be had here counts as verification on: the admin can
  /// approve a driver who waits, but not take back one who walked straight in.
  Future<void> _loadVerificationRules() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await FireStoreUtils.fireStore
          .collection(CollectionName.settings)
          .doc('document_verification_settings')
          .get(const GetOptions(source: Source.server));
      final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
      Constant.isDriverVerification = data['isDriverVerification'] as bool? ?? true;
      Constant.isOwnerVerification = data['isOwnerVerification'] as bool? ?? true;
    } catch (error) {
      log('signUp: verification settings unreadable, treating verification as on :: $error');
      Constant.isDriverVerification = true;
      Constant.isOwnerVerification = true;
    }
  }

  void _populateUserModel() {
    userModel.value.firstName = firstNameEditingController.value.text;
    userModel.value.lastName = lastNameEditingController.value.text;
    userModel.value.email = emailEditingController.value.text.toLowerCase();
    userModel.value.phoneNumber = phoneNUmberEditingController.value.text;
    userModel.value.role = Constant.userRoleDriver;
    userModel.value.isActive = false;
    userModel.value.active = Constant.autoApproveDriver == true ? true : false;
    userModel.value.isDocumentVerify = selectedValue.value == "Company"
        ? Constant.isOwnerVerification == true
            ? false
            : true
        : Constant.isDriverVerification == true
            ? false
            : true;
    userModel.value.countryCode = countryCodeEditingController.value.text;
    userModel.value.countryISOCode = countryISOCodeEditingController.value.text;
    userModel.value.createdAt = Timestamp.now();
    userModel.value.zoneId = selectedZone.value.id;
    userModel.value.appIdentifier = Platform.isAndroid ? 'android' : 'ios';
    userModel.value.provider = type.value.isEmpty ? 'email' : type.value;
    userModel.value.isOwner = selectedValue.value == "Company" ? true : false;
    userModel.value.isAutoVerify = selectedValue.value == "Company"
        ? Constant.isOwnerVerification == false
            ? true
            : false
        : Constant.isDriverVerification == false
            ? true
            : false;

    // ── Section IDs ──────────────────────────────────────────────────────────
    userModel.value.sectionIds = selectedSections.map((s) => s.id!).toList();

    // ── Derive serviceTypes from unique serviceTypeFlags of selected sections ─
    final uniqueFlags = selectedSections.map((s) => s.serviceTypeFlag ?? 'delivery-service').toSet().toList();
    userModel.value.serviceTypes = uniqueFlags;

    // ── sectionNames: simple {sectionId → sectionName} lookup ────────────────
    userModel.value.sectionNames = {
      for (final s in selectedSections) s.id!: s.name ?? s.id!,
    };

    // ── vehicleDetails: {sectionId → {vehicleId, vehicleType, carBrand, carModel, carPlateNumber}} ─
    // Skip for Company users — they register their own drivers separately.
    final Map<String, dynamic> vDetails = {};
    final bool isCompany = selectedValue.value == "Company";
    for (final section in selectedSections) {
      if (!isCompany && sectionNeedsVehicle(section)) {
        final vehicle = selectedVehiclePerSection[section.id];
        final carMakes = selectedCarMakesPerSection[section.id]?.value;
        final carModel = selectedCarModelPerSection[section.id]?.value;
        final carPlate = carPlatePerSection[section.id]?.value.text ?? '';
        vDetails[section.id!] = {
          'vehicleId': vehicle?.id ?? '',
          'vehicleType': vehicle?.name ?? '',
          'carBrand': carMakes?.name ?? '',
          'carModel': carModel?.name ?? '',
          'carPlateNumber': carPlate,
          if (section.serviceTypeFlag == 'cab-service') 'rideType': section.rideType ?? 'ride',
        };
      }
    }
    if (vDetails.isNotEmpty) userModel.value.vehicleDetails = vDetails;

    log(userModel.value.toJson().toString());
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _navigateAfterSignup(UserModel user) {
    if (!(Constant.autoApproveDriver ?? false)) {
      ShowToastDialog.showToast("Thank you for sign up, your application is under approval so please wait till that approve.".tr);
      Get.offAll(const LoginScreen());
      return;
    }
    navigateByUserModel(user);
  }

  /// Which services this driver works in.
  ///
  /// Two things on the driver's document can answer that, and they can
  /// disagree:
  ///
  ///  * the **recorded service** - `serviceTypes`, or the legacy `serviceType`
  ///    that preceded it. This is what the Admin Panel writes when an admin
  ///    picks a driver's sections (`drivers/edit.blade.php` writes
  ///    `serviceTypes` and `sectionIds` together from the one checkbox
  ///    selection), and it is what the panel itself *displays* and filters a
  ///    driver by - both `drivers/index.blade.php` and `drivers/view.blade.php`
  ///    read `serviceTypes || serviceType` and never look at the sections.
  ///  * the **sections** the driver sits in, `sectionIds` / `sectionId`, whose
  ///    `serviceTypeFlag` implies a service.
  ///
  /// The recorded service wins, because the client's requirement is that the
  /// driver's type stay exactly as selected in the Admin Panel, and the
  /// recorded service is the panel's own answer. The sections only *derive* one
  /// for a document that has no recorded service at all.
  ///
  /// This is the opposite of the previous precedence, which let the sections
  /// override the panel. That was there to heal documents corrupted by the old
  /// `UserModel.toJson()`, which invented `serviceTypes: ['delivery-service']`
  /// for any model that had not loaded the field; with that writer gone there
  /// is nothing left to heal - every document in the project whose plural field
  /// is set now agrees with its own sections - and the override had become the
  /// only remaining way for the app to contradict the panel. It still did, for
  /// eight drivers whose `sectionId` is stale demo data: a driver the panel
  /// lists as a delivery rider, sitting in the Cab Service section, was handed
  /// the cab dashboard.
  ///
  /// The sections it reads are the same ones every dashboard loads into
  /// [Constant.sectionModels] the moment it opens, so the fallback warms that
  /// cache rather than adding a round trip to it, and a section already in the
  /// cache costs nothing at all.
  static Future<List<String>> resolveServiceTypes(UserModel user) async {
    // `UserModel.fromJson` has already folded the legacy singular `serviceType`
    // into this list and dropped blank entries, so a non-empty list here is a
    // real answer from the document.
    final List<String> recorded =
        (user.serviceTypes ?? const <String>[]).where((String flag) => flag.isNotEmpty).toList();
    if (recorded.isNotEmpty) return recorded;

    final List<String> sectionIds =
        (user.sectionIds ?? const <String>[]).where((String id) => id.isNotEmpty).toList();
    if (sectionIds.isEmpty) return const <String>[];

    final List<SectionModel?> sections = await Future.wait(
      sectionIds.map((String id) async {
        final SectionModel? cached = Constant.sectionModels[id];
        if (cached != null) return cached;
        try {
          final SectionModel? loaded = await FireStoreUtils.getSectionBySectionId(id);
          if (loaded != null) Constant.sectionModels[id] = loaded;
          return loaded;
        } catch (error) {
          log('resolveServiceTypes: section $id could not be read :: $error');
          return null;
        }
      }),
    );

    final List<String> flags = <String>[];
    for (final SectionModel? section in sections) {
      final String flag = section?.serviceTypeFlag ?? '';
      if (flag.isNotEmpty && !flags.contains(flag)) flags.add(flag);
    }

    // Derived, so it is worth recording: the driver's document gains the answer
    // its sections already implied, and the next launch does not have to read
    // the sections again to find it. Nothing is written when the sections could
    // not be read, so a failed read never becomes a stored answer.
    if (flags.isNotEmpty) user.serviceTypes = flags;
    return flags;
  }

  static Future<void> navigateByUserModel(UserModel user) async {
    if (user.isOwner == true) {
      Get.offAll(OwnerDashboardScreen());
      return;
    }

    final List<String> serviceTypes = await resolveServiceTypes(user);
    if (serviceTypes.length > 1) {
      Get.offAll(const MultiServiceDashboardScreen());
      return;
    }
    _navigateByServiceType(serviceTypes.isEmpty ? 'delivery-service' : serviceTypes.first);
  }

  static void _navigateByServiceType(String serviceType) {
    switch (serviceType) {
      case 'cab-service':
        Get.offAll(const CabDashboardScreen());
        break;
      case 'parcel_delivery':
        Get.offAll(const ParcelDashboardScreen());
        break;
      case 'rental-service':
        Get.offAll(const RentalDashboardScreen());
        break;
      default:
        Get.offAll(const DashBoardScreen());
    }
  }
}
