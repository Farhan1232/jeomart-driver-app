import 'dart:async';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/app/wallet_screen/payment_list_screen.dart';
import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/send_notification.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/models/parcel_order_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/models/wallet_transaction_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:get/get.dart';

class ParcelHomeController extends GetxController {
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

  RxList<ParcelOrderModel> parcelOrdersList = <ParcelOrderModel>[].obs;
  RxBool isLoading = true.obs;

  @override
  void onInit() {
    // TODO: implement onInit
    getParcelList();
    super.onInit();
  }

  Rx<UserModel> userModel = UserModel().obs;
  Rx<UserModel> ownerModel = UserModel().obs;

  /// Whether the "Document Verification in Pending" screen should show, kept
  /// in step with the live driver document so the home screen switches to the
  /// map the moment the admin approves - it used to wait for an app restart.
  /// Null until the first snapshot, when the screen falls back to the profile
  /// loaded at launch.
  final RxnBool awaitsDocumentVerification = RxnBool();

  /// Whether the two profile listeners in [getParcelList] are already open.
  ///
  /// `getParcelList()` is also what refreshes the list after a pickup and after
  /// a completion, and each of those used to open both listeners again on top
  /// of the ones already running - two more for every parcel handled, for as
  /// long as the screen lived, each rebuilding the screen on every write to
  /// the driver's document. They are opened once now; the list itself is still
  /// re-read on every call.
  bool _driverListenerOpen = false;
  bool _ownerListenerOpen = false;

  Future<void> getParcelList() async {
    print("==>${userModel.value.isActive}");
    if (!_driverListenerOpen) {
      _driverListenerOpen = true;
      _subscriptions.add(
        FireStoreUtils.fireStore.collection(CollectionName.users).doc(FireStoreUtils.getCurrentUid()).snapshots().listen((event) {
          if (event.exists) {
            userModel.value = UserModel.fromJson(event.data()!);
            awaitsDocumentVerification.value = userModel.value.isDocumentVerify == false && userModel.value.isAutoVerify == false;
            print("==>${userModel.value.isActive}");
            update();
          }
        }),
      );
    }
    print("==>${userModel.value.isActive}");


    await FireStoreUtils.getOnGoingParcelList().then(
      (value) {
        parcelOrdersList.value = value;
        update();
      },
    );

    if (!_ownerListenerOpen && Constant.userModel!.ownerId != null && Constant.userModel!.ownerId!.isNotEmpty) {
      _ownerListenerOpen = true;
      _subscriptions.add(
        FireStoreUtils.fireStore.collection(CollectionName.users).doc(Constant.userModel!.ownerId).snapshots().listen((event) async {
          if (event.exists) {
            ownerModel.value = UserModel.fromJson(event.data()!);
          }
        }),
      );
    }
    isLoading.value = false;
    update();
  }

  Future<void> pickupParcel(ParcelOrderModel parcelBookingData) async {
    ShowToastDialog.showLoader("Please wait".tr);
    // The loader is closed on every path. A throw from the list refresh used to
    // leave it up, blocking the screen, until the 30 s watchdog took it down.
    bool failed = false;
    try {
      parcelBookingData.status = Constant.orderInTransit;
      await FireStoreUtils.setParcelOrder(parcelBookingData);
      await getParcelList();
    } catch (e) {
      failed = true;
      log('pickupParcel() error: $e');
    } finally {
      ShowToastDialog.closeLoader();
    }
    if (failed) ShowToastDialog.showToast("Something went wrong. Please try again.".tr);
  }

  /// The parcel [completeParcel] is in the middle of completing.
  ///
  /// The loader was the only thing in the way of a second tap on Deliver
  /// Parcel, and its watchdog lifts it while the wallet writes may still be
  /// running - a second tap then ran the whole completion again, wallet credit
  /// included.
  String? _completingParcelId;

  /// Completes the parcel.
  ///
  /// The writes and their order are unchanged: wallet, then the parcel, then
  /// the list refresh, then the first-order referral. What is new is that a
  /// failure no longer leaves the loader up with the parcel half done and no
  /// word to the driver, a repeated tap is ignored while one completion runs,
  /// and the push is sent without holding the screen for it.
  Future<void> completeParcel(ParcelOrderModel parcelBookingData) async {
    final String? parcelId = parcelBookingData.id;
    if (parcelId != null && _completingParcelId == parcelId) {
      log('completeParcel: parcel $parcelId is already being completed; ignoring the repeated tap.');
      return;
    }
    _completingParcelId = parcelId;
    ShowToastDialog.showLoader("Please wait");
    bool failed = false;
    try {
      parcelBookingData.status = Constant.orderCompleted;

      await updateCabWalletAmount(parcelBookingData);
      await FireStoreUtils.setParcelOrder(parcelBookingData);
      Map<String, dynamic> payLoad = <String, dynamic>{"type": "parcel_order", "orderId": parcelBookingData.id};
      unawaited(SendNotification.sendFcmMessage(Constant.parcelCompleted, parcelBookingData.author?.fcmToken ?? '', payLoad));
      await getParcelList();
      await FireStoreUtils.getParcelFirstOrderOrNOt(parcelBookingData).then((value) async {
        if (value == true) {
          await FireStoreUtils.updateParcelReferralAmount(parcelBookingData);
        }
      });
    } catch (e) {
      failed = true;
      log('completeParcel() error: $e');
    } finally {
      _completingParcelId = null;
      ShowToastDialog.closeLoader();
    }
    if (failed) ShowToastDialog.showToast("Something went wrong. Please try again.".tr);
  }

  Future<void> updateCabWalletAmount(ParcelOrderModel orderModel) async {
    double totalTax = 0.0;
    double adminComm = 0.0;
    double discount = 0.0;
    double subTotal = 0.0;
    double totalAmount = 0.0;

    // Read without `!` and `double.parse`: a parcel saved without a commission,
    // a tax list or a numeric subtotal threw here, before a single write, and
    // Deliver Parcel did nothing. Well-formed orders get exactly the same values.
    subTotal = double.tryParse(orderModel.subTotal ?? '0.0') ?? 0.0;
    discount = double.tryParse(orderModel.discount ?? '0.0') ?? 0.0;

    for (var element in orderModel.taxSetting ?? []) {
      totalTax = totalTax + Constant.calculateTax(amount: (subTotal - discount).toString(), taxModel: element);
    }

    // The fleet owner's wallet when the driver has one, as before.
    final String? ownerId = orderModel.driver?.ownerId;
    final String walletUserId = ownerId != null && ownerId.isNotEmpty ? ownerId : FireStoreUtils.getCurrentUid();

    if ((orderModel.adminCommission ?? '').isNotEmpty) {
      adminComm = Constant.calculateAdminCommission(
          amount: (subTotal - discount).toString(),
          adminCommissionType: orderModel.adminCommissionType.toString(),
          adminCommission: orderModel.adminCommission ?? '0');
    }

    totalAmount = ((subTotal - discount) + totalTax);
    if (orderModel.paymentMethod.toString() != PaymentGateway.cod.name) {
      WalletTransactionModel transactionModel = WalletTransactionModel(
          id: Constant.getUuid(),
          amount: totalAmount,
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
          await FireStoreUtils.updateUserWallet(amount: totalAmount.toString(), userId: walletUserId);
        }
      });
    }

    WalletTransactionModel transactionModel = WalletTransactionModel(
        id: Constant.getUuid(),
        amount: adminComm,
        date: Timestamp.now(),
        paymentMethod: orderModel.paymentMethod ?? '',
        transactionUser: "driver",
        userId: walletUserId,
        isTopup: false,
        orderId: orderModel.id,
        note: "Admin commission deducted",
        paymentStatus: "success");

    await FireStoreUtils.setWalletTransaction(transactionModel).then((value) async {
      if (value == true) {
        await FireStoreUtils.updateUserWallet(amount: "-${adminComm.toString()}", userId: walletUserId);
      }
    });
  }

  String calculateParcelTotalAmountBooking(ParcelOrderModel parcelBookingData) {
    String subTotal = parcelBookingData.subTotal.toString();
    String discount = parcelBookingData.discount ?? "0.0";
    String taxAmount = "0.0";
    for (var element in parcelBookingData.taxSetting!) {
      taxAmount = (double.parse(taxAmount) +
              Constant.calculateTax(amount: (double.parse(subTotal) - double.parse(discount)).toString(), taxModel: element))
          .toStringAsFixed(int.tryParse(Constant.currencyModel!.decimalDigits.toString()) ?? 2);
    }

    return ((double.parse(subTotal) - (double.parse(discount))) + double.parse(taxAmount))
        .toStringAsFixed(int.tryParse(Constant.currencyModel!.decimalDigits.toString()) ?? 2);
  }
}
