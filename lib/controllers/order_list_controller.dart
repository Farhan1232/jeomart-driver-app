import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/models/order_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/firestore_paginator.dart';
import 'package:get/get.dart';

class OrderListController extends GetxController {
  RxBool isLoading = true.obs;

  /// Delivery history is paged instead of downloading every order the driver
  /// has ever delivered.
  FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel>? ordersPaginator;

  List<OrderModel> get orderList => ordersPaginator?.items ?? <OrderModel>[];

  bool get hasMoreOrders => ordersPaginator?.hasMore.value ?? false;

  @override
  void onInit() {
    getOrder();
    super.onInit();
  }

  Future<void> getOrder() async {
    isLoading.value = true;
    ordersPaginator?.dispose();
    final paginator = FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel>(
      source: FirestorePageSource(FireStoreUtils.deliveryOrdersQuery(Constant.userModel!.id.toString()), live: true),
      mapper: (doc) {
        final data = doc.data();
        if (data == null) return null;
        try {
          return OrderModel.fromJson(data);
        } catch (_) {
          return null;
        }
      },
      pageSize: 20,
    );
    ordersPaginator = paginator;
    await paginator.refresh();
    isLoading.value = false;
  }

  Future<void> loadMoreOrders() async {
    await ordersPaginator?.loadMore();
  }

  Future<void> refreshOrders() async {
    await ordersPaginator?.refresh();
  }

  @override
  void onClose() {
    ordersPaginator?.dispose();
    ordersPaginator = null;
    super.onClose();
  }
}
