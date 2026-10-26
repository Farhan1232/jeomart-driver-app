import 'dart:io';

import 'package:driver/constant/constant.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/models/zone_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileController extends GetxController {
  RxBool isLoading = true.obs;
  Rx<UserModel> userModel = UserModel().obs;

  Rx<TextEditingController> firstNameController = TextEditingController().obs;
  Rx<TextEditingController> lastNameController = TextEditingController().obs;
  Rx<TextEditingController> emailController = TextEditingController().obs;
  Rx<TextEditingController> phoneNumberController = TextEditingController().obs;
  Rx<TextEditingController> countryCodeController = TextEditingController(text: Constant.defaultCountryCode).obs;
  Rx<TextEditingController> countryISOCodeController = TextEditingController(text: Constant.defaultCountryCode).obs;

  Rx<ZoneModel> selectedZone = ZoneModel().obs;
  RxList<ZoneModel> zoneList = <ZoneModel>[].obs;

  @override
  void onInit() {
    getData();
    super.onInit();
  }

  Future<void> getData() async {
    await FireStoreUtils.getZone().then((value) {
      if (value != null) {
        zoneList.value = value;
      }
    });

    await FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid()).then((value) {
      if (value != null) {
        userModel.value = value;
        firstNameController.value.text = userModel.value.firstName.toString();
        lastNameController.value.text = userModel.value.lastName.toString();
        emailController.value.text = userModel.value.email.toString();
        phoneNumberController.value.text = userModel.value.phoneNumber.toString();
        countryCodeController.value.text = userModel.value.countryCode.toString();
        countryISOCodeController.value.text = userModel.value.countryISOCode.toString();
        profileImage.value = userModel.value.profilePictureURL ?? '';

        for (var element in zoneList) {
          if (element.id == userModel.value.zoneId) {
            selectedZone.value = element;
          }
        }
      }
    });

    isLoading.value = false;
  }

  /// Saves the profile.
  ///
  /// A failed photo upload used to leave the loader up with nothing saved, and
  /// a save that did not go through still closed the screen as if it had. The
  /// loader is closed on every path now, and the screen only closes on a save
  /// that happened.
  Future<void> saveData() async {
    ShowToastDialog.showLoader("Please wait".tr);
    bool saved = false;
    try {
      if (Constant().hasValidUrl(profileImage.value) == false && profileImage.value.isNotEmpty) {
        profileImage.value = await Constant.uploadUserImageToFireStorage(
          File(profileImage.value),
          "profileImage/${FireStoreUtils.getCurrentUid()}",
          File(profileImage.value).path.split('/').last,
        );
      }

      userModel.value.firstName = firstNameController.value.text;
      userModel.value.lastName = lastNameController.value.text;
      userModel.value.profilePictureURL = profileImage.value;
      userModel.value.zoneId = selectedZone.value.id;

      saved = await FireStoreUtils.updateUser(userModel.value);
    } catch (e) {
      debugPrint("saveData() error: $e");
    } finally {
      ShowToastDialog.closeLoader();
    }

    if (!saved) {
      ShowToastDialog.showToast("Something went wrong. Please try again.".tr);
      return;
    }
    Get.back(result: true);
  }

  final ImagePicker _imagePicker = ImagePicker();
  RxString profileImage = "".obs;

  Future pickFile({required ImageSource source}) async {
    try {
      XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) return;
      Get.back();
      profileImage.value = image.path;
    } on PlatformException catch (e) {
      ShowToastDialog.showToast("${"failed_to_pick".tr} : \n $e");
    }
  }
}
