import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/send_notification.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/models/order_model.dart';
import 'package:driver/models/wallet_transaction_model.dart';
import 'package:driver/services/audio_player_service.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:get/get.dart';

class DeliverOrderController extends GetxController {
  RxBool isLoading = true.obs;
  RxBool conformPickup = false.obs;

  @override
  void onInit() {
    // TODO: implement onInit
    getArgument();
    super.onInit();
  }

  Rx<OrderModel> orderModel = OrderModel().obs;

  RxInt totalQuantity = 0.obs;

  void getArgument() {
    dynamic argumentData = Get.arguments;
    if (argumentData != null) {
      orderModel.value = argumentData['orderModel'];
      for (var element in orderModel.value.products!) {
        totalQuantity.value += (element.quantity ?? 0);
      }
    }
    isLoading.value = false;
  }

  /// The order [completedOrder] is in the middle of completing.
  ///
  /// The loader was the only thing in the way of a second tap on Make Order
  /// Delivered, and its watchdog lifts it while the wallet writes may still be
  /// running - a second tap then ran the completion again.
  String? _completingOrderId;

  /// Marks the order delivered.
  ///
  /// Only the order itself is waited for; the wallet and the rest follow in
  /// [_settleDeliveredOrder]. A failure keeps the driver on this screen with a
  /// message, and the push to the customer is sent without holding the screen.
  Future<void> completedOrder() async {
    final String? orderId = orderModel.value.id;
    if (orderId != null && _completingOrderId == orderId) {
      log('completedOrder: order $orderId is already being completed; ignoring the repeated tap.');
      return;
    }
    _completingOrderId = orderId;
    ShowToastDialog.showLoader("Please wait".tr);
    bool failed = false;
    String? previousStatus;
    try {
      unawaited(AudioPlayerService.playSound(false));
      previousStatus = orderModel.value.status;
      orderModel.value.status = Constant.orderCompleted;
      // The order is what the customer, the store and the driver's own Home
      // screen are waiting on, so it is the only thing "Please wait" waits for.
      // The wallet came first and held the screen for 5-10 s on live orders,
      // almost all of it the balance transaction on the driver's profile, which
      // is busy with GPS writes. If this write fails nothing else has run, so a
      // second tap cannot apply the money twice.
      final bool? saved = await FireStoreUtils.setOrder(orderModel.value);
      if (saved != true) throw Exception('order $orderId was not saved');
      unawaited(SendNotification.sendFcmMessage(Constant.driverCompleted, orderModel.value.author?.fcmToken ?? '', {}));
      unawaited(_settleDeliveredOrder(orderModel.value));
    } catch (e) {
      failed = true;
      log('completedOrder() error: $e');
    } finally {
      _completingOrderId = null;
      ShowToastDialog.closeLoader();
    }
    if (failed) {
      orderModel.value.status = previousStatus;
      ShowToastDialog.showToast("Something went wrong. Please try again.".tr);
      return;
    }
    Get.back(result: true);
  }

  /// Everything a delivered order settles after it is saved, in the order it
  /// always ran: driver wallet, cashback, the driver's order lists, referral.
  ///
  /// Each step's own failure handling is unchanged (they log and carry on, as
  /// they did inside the loader). The order lists are cleared with the one-field
  /// release rather than a save of the whole profile: a whole-profile save also
  /// writes `wallet_amount`, and from a copy read before the balance moved it
  /// would undo the credit or debit made just above.
  Future<void> _settleDeliveredOrder(OrderModel order) async {
    try {
      await FireStoreUtils.updateWallateAmount(order);
      if (order.cashback?.cashbackValue != null && order.cashback?.id != null) {
        WalletTransactionModel transactionModel = WalletTransactionModel(
            id: Constant.getUuid(),
            amount: double.parse("${order.cashback?.cashbackValue ?? 0.0}"),
            date: Timestamp.now(),
            paymentMethod: "Cashback Amount",
            transactionUser: "user",
            userId: order.author?.id,
            isTopup: true,
            orderId: order.id,
            note: "Cashback Amount",
            paymentStatus: "success");
        await FireStoreUtils.setWalletTransaction(transactionModel).then((value) async {
          if (value == true) {
            await FireStoreUtils.updateUserWallet(amount: double.parse("${order.cashback?.cashbackValue ?? 0.0}").toString(), userId: order.author!.id.toString());
          }
        });
      }
      if (Constant.userModel?.vendorID != null && order.id != null) {
        await FireStoreUtils.releaseDriverOrder(order.id!);
      }
      await FireStoreUtils.getFirestOrderOrNOt(order).then((value) async {
        if (value == true) {
          await FireStoreUtils.updateReferralAmount(order);
        }
      });
    } catch (e, s) {
      log('settling delivered order ${order.id} failed: $e');
      log(s.toString());
    }
  }
}
