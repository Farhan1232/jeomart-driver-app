import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../models/cab_order_model.dart';
import '../utils/fire_store_utils.dart';
import '../utils/driver_ride_counts.dart';
import '../utils/firestore_paginator.dart';

class CabOrderListController extends GetxController {
  RxBool isLoading = true.obs;
  RxString selectedTab = "On Going".obs;

  RxList<String> tabTitles = ["On Going", "Completed", "Cancelled"].obs;

  RxString driverId = ''.obs;

  /// Ride history is paged instead of streaming the driver's whole history.
  ///
  /// This also fixes a subscription leak: `fetchCabOrders()` used to be called
  /// again on every tab tap and opened a new, never-cancelled listener each
  /// time. Tabs now filter what is already loaded.
  FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, CabOrderModel>? ordersPaginator;

  List<CabOrderModel> get cabOrder => ordersPaginator?.items ?? <CabOrderModel>[];

  bool get hasMoreOrders => ordersPaginator?.hasMore.value ?? false;

  /// Whether the paginator is still topping the list up to its target.
  ///
  /// The list can be empty *and* still filling — the first page has landed but
  /// none of its rows match the selected tab. Screens use this so an empty tab
  /// shows a loader rather than "No orders found" over rows that are on the way.
  bool get isToppingUp => ordersPaginator?.isToppingUp.value ?? false;


  /// Statuses per tab. Filtering stays client-side so the Firestore query, and
  /// the index behind it, is unchanged.
  ///
  /// The lists come from [DriverRideCounts] rather than being spelled out here,
  /// so the "On Going" tab and the live count badge on the bottom bar are the
  /// same set of statuses by construction. A badge reading 2 over a tab listing
  /// 3 is worse than no badge.
  static const Map<String, List<String>> tabStatuses = {
    "On Going": DriverRideCounts.ongoingStatuses,
    "Completed": DriverRideCounts.completedStatuses,
    "Cancelled": DriverRideCounts.cancelledStatuses,
  };

  bool Function(CabOrderModel) _filterFor(String tab) {
    final statuses = tabStatuses[tab] ?? const <String>[];
    return (order) => statuses.contains(order.status);
  }

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    driverId.value = args?['driverId'] ?? FireStoreUtils.getCurrentUid();
    fetchCabOrders();
  }

  /// Only changes the visible tab - it no longer re-subscribes.
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
  Future<void> fetchCabOrders() async {
    isLoading.value = true;
    ordersPaginator?.dispose();
    final paginator = FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, CabOrderModel>(
      source: FirestorePageSource(FireStoreUtils.cabOrdersQuery(driverId.value), live: true),
      mapper: (doc) {
        final data = doc.data();
        if (data == null) return null;
        try {
          return CabOrderModel.fromJson(data);
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
  List<CabOrderModel> getOrdersForTab(String tab) {
    return cabOrder.where(_filterFor(tab)).toList();
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
