import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/app/wallet_screen/payment_list_screen.dart';
import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/send_notification.dart';
import 'package:driver/models/rental_order_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/models/wallet_transaction_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../constant/show_toast_dialog.dart' show ShowToastDialog;

class RentalHomeController extends GetxController {
  /// Firestore listeners opened by this controller.
  ///
  /// They used to run for the rest of the session because nothing cancelled
  /// them when the screen closed, and re-entering the screen opened another
  /// set on top.
  final List<StreamSubscription<dynamic>> _subscriptions = <StreamSubscription<dynamic>>[];

  @override
  void onClose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.onClose();
  }

  RxList<RentalOrderModel> rentalBookingData = <RentalOrderModel>[].obs;

  RxBool isLoading = true.obs;

  Rx<TextEditingController> currentKilometerController = TextEditingController().obs;
  Rx<TextEditingController> completeKilometerController = TextEditingController().obs;
  Rx<UserModel> userModel = UserModel().obs;
  Rx<UserModel> ownerModel = UserModel().obs;

  /// Whether the "Document Verification in Pending" screen should show, kept
  /// in step with the live driver document so the home screen switches to the
  /// map the moment the admin approves - it used to wait for an app restart.
  /// Null until the first snapshot, when the screen falls back to the profile
  /// loaded at launch.
  final RxnBool awaitsDocumentVerification = RxnBool();


  @override
  void onInit() {
    getBookingData();
    // TODO: implement onInit
    super.onInit();
  }


  Future<void> getBookingData() async {
    isLoading.value = true;
    rentalBookingData.clear();

    // Driver's active rental bookings
    _subscriptions.add(
      FireStoreUtils.fireStore
          .collection(CollectionName.rentalOrders)
          .where("driverId", isEqualTo: FireStoreUtils.getCurrentUid())
          .where("status", whereIn: [Constant.driverAccepted, Constant.orderInTransit, Constant.orderShipped])
          .snapshots()
          .listen((event) {
            rentalBookingData.clear();

            for (var element in event.docs) {
              rentalBookingData.add(RentalOrderModel.fromJson(element.data()));
            }

            // ✅ Turn off loader *after first snapshot*
            isLoading.value = false;
            update();
          }),
    );

    // Driver user data listener
    _subscriptions.add(
      FireStoreUtils.fireStore.collection(CollectionName.users).doc(FireStoreUtils.getCurrentUid()).snapshots().listen((event) {
        if (event.exists) {
          userModel.value = UserModel.fromJson(event.data()!);
          awaitsDocumentVerification.value = userModel.value.isDocumentVerify == false && userModel.value.isAutoVerify == false;
        }
      }),
    );

    if (Constant.userModel!.ownerId != null && Constant.userModel!.ownerId!.isNotEmpty) {
      _subscriptions.add(
        FireStoreUtils.fireStore.collection(CollectionName.users).doc(Constant.userModel!.ownerId).snapshots().listen((event) async {
          if (event.exists) {
            ownerModel.value = UserModel.fromJson(event.data()!);
          }
        }),
      );
    }
  }

  /// The booking a completion is currently running for. See [beginCompletion].
  String? _completingBookingId;

  /// Claims [bookingId] for one completion; false while one is already running.
  ///
  /// The loader was the only thing in the way of a second tap on Complete
  /// Booking or Ride Completed, and its watchdog lifts it while the wallet
  /// writes may still be running - a second tap then credited the booking
  /// again.
  bool beginCompletion(String? bookingId) {
    if (bookingId != null && _completingBookingId == bookingId) return false;
    _completingBookingId = bookingId;
    return true;
  }

  /// Releases [bookingId] once its completion has finished, either way.
  void endCompletion(String? bookingId) {
    if (_completingBookingId == bookingId) _completingBookingId = null;
  }

  /// Completes the booking.
  ///
  /// The writes and their order are unchanged. A failure now closes the loader
  /// and says so instead of leaving the booking half done behind a spinner, and
  /// the success message is shown after the loader closes rather than being
  /// dismissed with it.
  Future<void> completeParcel(RentalOrderModel parcelBookingData) async {
    if (!beginCompletion(parcelBookingData.id)) {
      log('completeParcel: booking ${parcelBookingData.id} is already being completed; ignoring the repeated tap.');
      return;
    }
    ShowToastDialog.showLoader("Please wait".tr);
    bool failed = false;
    try {
      parcelBookingData.status = Constant.orderCompleted;

      await updateCabWalletAmount(parcelBookingData);
      await FireStoreUtils.rentalOrderPlace(parcelBookingData);
      Map<String, dynamic> payLoad = <String, dynamic>{"type": "rental_order", "orderId": parcelBookingData.id};
      SendNotification.sendFcmMessage(Constant.rentalCompleted, parcelBookingData.author?.fcmToken ?? '', payLoad);
      FireStoreUtils.getRentalFirstOrderOrNOt(parcelBookingData).then((value) async {
        if (value == true) {
          await FireStoreUtils.updateRentalReferralAmount(parcelBookingData);
        }
      });
    } catch (e) {
      failed = true;
      log('completeParcel() error: $e');
    } finally {
      endCompletion(parcelBookingData.id);
      ShowToastDialog.closeLoader();
    }
    ShowToastDialog.showToast(failed ? "Something went wrong. Please try again.".tr : "Ride completed successfully".tr);
  }

  RxDouble subTotal = 0.0.obs;
  RxDouble discount = 0.0.obs;
  RxDouble taxAmount = 0.0.obs;
  RxDouble totalAmount = 0.0.obs;
  RxDouble extraKilometerCharge = 0.0.obs;
  RxDouble extraMinutesCharge = 0.0.obs;
  RxDouble adminComm = 0.0.obs;

  Future<void> updateCabWalletAmount(RentalOrderModel orderModel) async {
    subTotal.value = 0.0;
    discount.value = 0.0;
    taxAmount.value = 0.0;
    totalAmount.value = 0.0;
    extraKilometerCharge.value = 0.0;
    extraMinutesCharge.value = 0.0;
    adminComm.value = 0.0;
    subTotal.value = double.tryParse(orderModel.subTotal?.toString() ?? "0") ?? 0.0;
    discount.value = double.tryParse(orderModel.discount?.toString() ?? "0") ?? 0.0;

    // A package saved without its included hours or distance has no extra
    // charge that can be worked out, so that charge is skipped. `int.parse` and
    // `double.parse` threw here instead, before any write, and left the
    // completion on its loader with nothing done.
    final int? includedHours = int.tryParse(orderModel.rentalPackageModel?.includedHours.toString() ?? '');
    final double? includedDistance = double.tryParse(orderModel.rentalPackageModel?.includedDistance.toString() ?? '');

    if (orderModel.endTime != null && orderModel.startTime != null) {
      DateTime start = orderModel.startTime!.toDate();
      DateTime end = orderModel.endTime!.toDate();
      int hours = end.difference(start).inHours;
      if (includedHours != null && hours >= includedHours) {
        hours = hours - includedHours;
        double hourlyRate = double.tryParse(orderModel.rentalPackageModel?.extraMinuteFare?.toString() ?? "0") ?? 0.0;
        extraMinutesCharge.value = (hours * 60) * hourlyRate;
      }
    }

    if (orderModel.startKitoMetersReading != null && orderModel.endKitoMetersReading != null) {
      double startKm = double.tryParse(orderModel.startKitoMetersReading?.toString() ?? "0") ?? 0.0;
      double endKm = double.tryParse(orderModel.endKitoMetersReading?.toString() ?? "0") ?? 0.0;
      if (endKm > startKm) {
        double totalKm = endKm - startKm;
        if (includedDistance != null && totalKm > includedDistance) {
          totalKm = totalKm - includedDistance;
          double extraKmRate = double.tryParse(orderModel.rentalPackageModel?.extraKmFare?.toString() ?? "0") ?? 0.0;
          extraKilometerCharge.value = totalKm * extraKmRate;
        }
      }
    }
    subTotal.value = subTotal.value + extraKilometerCharge.value + extraMinutesCharge.value;

    if (orderModel.taxSetting != null) {
      for (var element in orderModel.taxSetting!) {
        taxAmount.value += Constant.calculateTax(amount: (subTotal.value - discount.value).toString(), taxModel: element);
      }
    }

    totalAmount.value = (subTotal.value - discount.value) + taxAmount.value;

    if ((orderModel.adminCommission ?? '').isNotEmpty) {
      adminComm.value = Constant.calculateAdminCommission(
          amount: (subTotal.value - discount.value).toString(), adminCommissionType: orderModel.adminCommissionType.toString(), adminCommission: orderModel.adminCommission ?? '0');
    }

    // The fleet owner's wallet when the driver has one, as before - read
    // without `!`, so a booking saved without its driver copy no longer throws.
    final String? ownerId = orderModel.driver?.ownerId;
    final String walletUserId = ownerId != null && ownerId.isNotEmpty ? ownerId : FireStoreUtils.getCurrentUid();

    if (orderModel.paymentMethod.toString() != PaymentGateway.cod.name) {
      WalletTransactionModel transactionModel = WalletTransactionModel(
          id: Constant.getUuid(),
          amount: totalAmount.value,
          date: Timestamp.now(),
          paymentMethod: orderModel.paymentMethod ?? '',
          transactionUser: "driver",
          userId: walletUserId,
          isTopup: true,
          orderId: orderModel.id,
          note: "Booking amount credited",
          paymentStatus: "success");

      await FireStoreUtils.setWalletTransaction(transactionModel).then((value) async {
        if (value == true) {
          await FireStoreUtils.updateUserWallet(amount: totalAmount.value.toString(), userId: walletUserId);
        }
      });
    }

    WalletTransactionModel adminCommissionTrancation = WalletTransactionModel(
        id: Constant.getUuid(),
        amount: adminComm.value,
        date: Timestamp.now(),
        paymentMethod: orderModel.paymentMethod ?? '',
        transactionUser: "driver",
        userId: walletUserId,
        isTopup: false,
        orderId: orderModel.id,
        note: "Admin commission deducted",
        paymentStatus: "success");

    print("=================== Admin Commission: ${adminComm.value} ==================");
    log("=========${adminCommissionTrancation.toJson().toString()}=========}");
    await FireStoreUtils.setWalletTransaction(adminCommissionTrancation).then((value) async {
      if (value == true) {
        await FireStoreUtils.updateUserWallet(amount: "-${adminComm.value.toString()}", userId: walletUserId);
      }
    });

  }
}
