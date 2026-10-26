import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../models/parcel_order_model.dart';
import '../utils/fire_store_utils.dart';
import '../utils/firestore_paginator.dart';

class ParcelOrderListController extends GetxController {
  RxBool isLoading = true.obs;

  RxString selectedTab = "In Transit".obs;
  RxList<String> tabTitles = ["In Transit", "Delivered", "Cancelled"].obs;

  RxString driverId = ''.obs;

  /// Parcel history is paged instead of streaming the driver's whole history.
  /// The first page stays live so status changes still arrive immediately.
  FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, ParcelOrderModel>? ordersPaginator;

  List<ParcelOrderModel> get parcelOrder => ordersPaginator?.items ?? <ParcelOrderModel>[];

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
    "In Transit": ["Order Placed", "Order Accepted", "Driver Accepted", "Driver Pending", "Order Shipped", "In Transit"],
    "Delivered": ["Order Completed"],
    "Cancelled": ["Order Rejected", "Order Cancelled", "Driver Rejected"],
  };

  bool Function(ParcelOrderModel) _filterFor(String tab) {
    final statuses = tabStatuses[tab] ?? const <String>[];
    return (order) => statuses.contains(order.status);
  }

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    driverId.value = args?['driverId'] ?? FireStoreUtils.getCurrentUid();
    listenParcelOrders();
  }

  /// Only changes the visible tab; the loaded pages are reused, and more are
  /// fetched if the new tab has nothing to show yet.
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
  Future<void> listenParcelOrders() async {
    isLoading.value = true;
    ordersPaginator?.dispose();
    final paginator = FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, ParcelOrderModel>(
      source: FirestorePageSource(FireStoreUtils.parcelOrdersQuery(driverId.value), live: true),
      mapper: (doc) {
        final data = doc.data();
        if (data == null) return null;
        try {
          return ParcelOrderModel.fromJson(data);
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
  List<ParcelOrderModel> getOrdersForTab(String tab) {
    return parcelOrder.where(_filterFor(tab)).toList();
  }

  String formatDate(Timestamp timestamp) {
    final dateTime = timestamp.toDate();
    return DateFormat("dd MMM yyyy, hh:mm a").format(dateTime);
  }

  @override
  void onClose() {
    ordersPaginator?.dispose();
    ordersPaginator = null;
    super.onClose();
  }
}
