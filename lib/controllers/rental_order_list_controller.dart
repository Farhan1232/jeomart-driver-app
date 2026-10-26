import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/rental_order_model.dart';
import '../utils/fire_store_utils.dart';
import '../utils/firestore_paginator.dart';

class RentalOrderListController extends GetxController {
  RxBool isLoading = true.obs;

  RxString selectedTab = "On Going".obs;
  RxList<String> tabTitles = ["On Going", "Completed", "Cancelled"].obs;

  final RxString selectedPaymentMethod = ''.obs;

  RxString driverId = ''.obs;

  /// Rental history is paged instead of streaming the driver's whole history.
  /// The first page stays live so status changes still arrive immediately.
  FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, RentalOrderModel>? ordersPaginator;

  List<RentalOrderModel> get rentalOrders => ordersPaginator?.items ?? <RentalOrderModel>[];

  bool get hasMoreOrders => ordersPaginator?.hasMore.value ?? false;

  /// Whether the paginator is still topping the list up to its target.
  ///
  /// The list can be empty *and* still filling — the first page has landed but
  /// none of its rows match the selected tab. Screens use this so an empty tab
  /// shows a loader rather than "No orders found" over rows that are on the way.
  bool get isToppingUp => ordersPaginator?.isToppingUp.value ?? false;


  /// Statuses per tab. Filtering stays client-side so the Firestore query, and
  /// the index behind it, is unchanged.
  static const Map<String, List<String>> tabStatuses = {
    "On Going": ["Order Placed", "Order Accepted", "Driver Accepted", "Driver Pending", "Order Shipped", "In Transit"],
    "Completed": ["Order Completed"],
    "Cancelled": ["Order Rejected", "Order Cancelled", "Driver Rejected"],
  };

  bool Function(RentalOrderModel) _filterFor(String tab) {
    final statuses = tabStatuses[tab] ?? const <String>[];
    return (order) => statuses.contains(order.status);
  }

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    driverId.value = args?['driverId'] ?? FireStoreUtils.getCurrentUid();
    listenRentalOrders();
  }

  Future<void> selectTab(String tab) async {
    selectedTab.value = tab;
    await ordersPaginator?.applyFilter(_filterFor(tab));
  }

  Future<void> loadMoreOrders() async {
    await ordersPaginator?.loadMore();
  }

  Future<void> refreshOrders() async {
    await ordersPaginator?.refresh();
  }

  /// Loads the first page and keeps it live; older pages arrive on scroll.
  Future<void> listenRentalOrders() async {
    isLoading.value = true;
    ordersPaginator?.dispose();
    final paginator = FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, RentalOrderModel>(
      source: FirestorePageSource(FireStoreUtils.rentalOrdersQuery(driverId.value), live: true),
      mapper: (doc) {
        final data = doc.data();
        if (data == null) return null;
        try {
          return RentalOrderModel.fromJson(data);
        } catch (_) {
          return null;
        }
      },
      pageSize: 20,
      autoFillTarget: 10,
      filter: _filterFor(selectedTab.value),
    );
    ordersPaginator = paginator;
    // The first page paints as soon as it lands; the top-up to
    // `autoFillTarget` continues behind the list instead of holding this
    // screen on a spinner through up to five more sequential reads.
    await paginator.refresh(awaitAutoFill: false);
    isLoading.value = false;
  }

  /// Return filtered list for a specific tab title
  List<RentalOrderModel> getOrdersForTab(String tab) {
    return rentalOrders.where(_filterFor(tab)).toList();
  }

  @override
  void onClose() {
    ordersPaginator?.dispose();
    ordersPaginator = null;
    super.onClose();
  }
}
