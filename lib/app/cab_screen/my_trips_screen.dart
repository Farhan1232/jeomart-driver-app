import 'package:driver/app/cab_screen/post_trip_screen.dart';
import 'package:driver/app/chat_screens/chat_screen.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/controllers/my_trips_controller.dart';
import 'package:driver/models/driver_trip_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/themes/round_button_fill.dart';
import 'package:driver/themes/theme_controller.dart';
import 'package:driver/utils/driver_trip_state.dart';
import 'package:driver/utils/network_image_widget.dart';
import 'package:driver/widget/load_more_listener.dart';
import 'package:driver/widget/my_separator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// My Trips - the driver's own posted intercity / local full-vehicle trips.
///
/// Reached only from the drawer entry, which is only built while the admin's
/// grant is valid. The screen re-checks that itself, so a grant that runs out
/// while the screen is open turns it into an explanation rather than a page
/// whose buttons quietly stop working.
class MyTripsScreen extends StatelessWidget {
  const MyTripsScreen({super.key});

  static final DateFormat _tripFormat = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  Widget build(BuildContext context) {
    final ThemeController themeController = Get.find<ThemeController>();
    return Obx(() {
      final bool isDark = themeController.isDark.value;
      return GetX<MyTripsController>(
        init: MyTripsController(),
        builder: (MyTripsController controller) {
          // Cheap, and it is what makes the screen react to a revocation that
          // arrives on the dashboard's live user listener while it is open.
          controller.refreshAccess();

          return Scaffold(
            backgroundColor: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
            body: controller.hasAccess.value
                ? _body(context, controller, isDark)
                : _noAccess(isDark),
            floatingActionButton: controller.hasAccess.value
                ? FloatingActionButton.extended(
                    backgroundColor: AppThemeData.primary300,
                    onPressed: () async {
                      final dynamic published = await Get.to(() => const PostTripScreen());
                      if (published == true) await controller.refreshTrips();
                    },
                    icon: const Icon(Icons.add, color: AppThemeData.grey900),
                    label: Text(
                      "Post a Trip".tr,
                      style: AppThemeData.semiBoldTextStyle(fontSize: 14, color: AppThemeData.grey900),
                    ),
                  )
                : null,
          );
        },
      );
    });
  }

  Widget _noAccess(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_clock, size: 48, color: isDark ? AppThemeData.grey400 : AppThemeData.grey500),
          const SizedBox(height: 12),
          Text(
            "My Trips access has ended".tr,
            textAlign: TextAlign.center,
            style: AppThemeData.semiBoldTextStyle(fontSize: 18, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
          ),
          const SizedBox(height: 6),
          Text(
            "Contact the admin to renew your access.".tr,
            textAlign: TextAlign.center,
            style: AppThemeData.regularTextStyle(fontSize: 14, color: isDark ? AppThemeData.grey300 : AppThemeData.grey600),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, MyTripsController controller, bool isDark) {
    if (controller.isLoading.value) return Constant.loader();

    final List<DriverTripModel> trips = controller.tripsForTab(controller.selectedTab.value);

    return Column(
      children: [
        _tabs(context, controller, isDark),
        Expanded(
          child: trips.isEmpty
              // Still filling: the first page landed but nothing in it matches
              // this tab yet, so "no trips" would be a wrong answer rather than
              // an early one.
              ? (controller.isToppingUp
                  ? Constant.loader()
                  : Constant.showEmptyView(message: "No trips found".tr, isDark: isDark))
              : LoadMoreListener(
                  onLoadMore: controller.loadMoreTrips,
                  child: RefreshIndicator(
                    onRefresh: controller.refreshTrips,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: trips.length + (controller.hasMoreTrips ? 1 : 0),
                      itemBuilder: (BuildContext context, int index) {
                        if (index >= trips.length) return const LoadMoreIndicator();
                        return _tripCard(controller, trips[index], isDark);
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// The height of the tab strip.
  ///
  /// It was a flat 52, which is exactly right at the system font's default size
  /// and too short at every step above it - the chips are a 14 px label inside
  /// 8 px of padding, inside a strip with 8 px of its own, so a driver running
  /// a large accessibility font size had the row overflow underneath them.
  ///
  /// The 52 is kept as the floor, so nothing at all moves at the default size;
  /// above it the strip grows by exactly as much as the label did.
  static double tabStripHeight(BuildContext context) {
    const double base = 52;
    final double label = MediaQuery.textScalerOf(context).scale(14);
    return (base + (label - 14) * 1.45).clamp(base, 96.0).toDouble();
  }

  Widget _tabs(BuildContext context, MyTripsController controller, bool isDark) {
    return SizedBox(
      height: tabStripHeight(context),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: controller.tabKeys.length,
        itemBuilder: (BuildContext context, int index) {
          final String key = controller.tabKeys[index];
          final bool selected = controller.selectedTab.value == key;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () => controller.selectTab(key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: selected
                      ? AppThemeData.primary300
                      : isDark
                          ? AppThemeData.grey800
                          : AppThemeData.grey100,
                ),
                child: Center(
                  child: Text(
                    tabTitle(key),
                    style: AppThemeData.semiBoldTextStyle(
                      fontSize: 14,
                      color: selected
                          ? AppThemeData.grey900
                          : isDark
                              ? AppThemeData.grey200
                              : AppThemeData.grey700,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String tabTitle(String status) {
    switch (status) {
      case DriverTripStatus.active:
        return 'Active'.tr;
      case DriverTripStatus.booked:
        return 'Booked'.tr;
      case DriverTripStatus.completed:
        return 'Completed'.tr;
      case DriverTripStatus.expired:
        return 'Expired'.tr;
      case DriverTripStatus.cancelled:
        return 'Cancelled'.tr;
      default:
        return status;
    }
  }

  Widget _tripCard(MyTripsController controller, DriverTripModel trip, bool isDark) {
    final String status = trip.effectiveStatusAt(DateTime.now());
    final bool canCancel = status == DriverTripStatus.active || status == DriverTripStatus.booked;
    // Only a booked trip: completing means the journey ran, and a trip nobody
    // reserved had no journey to run. The ledger enforces the same rule inside
    // its transaction, so this only decides whether to offer the button.
    final bool canComplete = DriverTripStatus.acceptsCompletion(status);
    final bool busy = controller.isBusy(trip);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppThemeData.grey800 : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  trip.tripDateTime == null ? '' : _tripFormat.format(trip.tripDateTime!.toDate()),
                  style: AppThemeData.semiBoldTextStyle(fontSize: 16, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
                ),
              ),
              _statusChip(status, isDark),
            ],
          ),
          const SizedBox(height: 10),
          _locationRow(Icons.stop_circle_outlined, Colors.green, trip.fromAddress ?? '', isDark),
          const SizedBox(height: 6),
          _locationRow(Icons.radio_button_checked, Colors.red, trip.toAddress ?? '', isDark),
          if ((trip.note ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                trip.note!,
                style: AppThemeData.regularTextStyle(fontSize: 14, color: isDark ? AppThemeData.grey300 : AppThemeData.grey600),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: MySeparator(color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  "Full Vehicle Price".tr,
                  style: AppThemeData.regularTextStyle(fontSize: 14, color: isDark ? AppThemeData.grey300 : AppThemeData.grey600),
                ),
              ),
              Text(
                Constant.amountShow(amount: (trip.fullVehiclePrice ?? 0).toString()),
                style: AppThemeData.boldTextStyle(fontSize: 18, color: AppThemeData.primary300),
              ),
            ],
          ),
          if (trip.hasReservation) _passengerBlock(controller, trip, isDark),
          // Complete Ride first and Cancel Trip second, in that order, because
          // finishing a booked trip is the outcome the driver is looking for
          // and cancelling one is the exception.
          if (canComplete)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: RoundedButtonFill(
                title: "Complete Ride".tr,
                height: 4.5,
                color: AppThemeData.success400,
                textColor: AppThemeData.grey50,
                onPress: () {
                  if (busy) return;
                  _confirmComplete(controller, trip, isDark);
                },
              ),
            ),
          if (canCancel)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: RoundedButtonFill(
                title: "Cancel Trip".tr,
                height: 4.5,
                color: AppThemeData.danger300,
                textColor: AppThemeData.grey50,
                onPress: () {
                  if (busy) return;
                  _confirmCancel(controller, trip, isDark);
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Who took the vehicle, and the two ways to reach them.
  ///
  /// The phone number and the FCM token come from
  /// `driver_trips/{tripId}/reservation/{customerId}` - the document the
  /// customer writes when they take the trip. Until the read lands the block
  /// still shows the name the trip document carries, so the card never jumps
  /// from empty to populated.
  Widget _passengerBlock(MyTripsController controller, DriverTripModel trip, bool isDark) {
    final TripReservationModel? reservation = controller.reservationFor(trip);
    final String name = (reservation?.customerName ?? trip.reservedByName ?? '').trim();
    final String photo = reservation?.customerPhoto ?? trip.reservedByPhoto ?? '';
    final String phone = (reservation?.fullPhoneNumber ?? '').trim();
    final bool ended = DriverTripStatus.isFinished(trip.effectiveStatusAt(DateTime.now()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: MySeparator(color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
        ),
        Text(
          "Booked by".tr,
          style: AppThemeData.regularTextStyle(fontSize: 12, color: isDark ? AppThemeData.grey400 : AppThemeData.grey500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: NetworkImageWidget(imageUrl: photo, height: 44, width: 44, borderRadius: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name.isEmpty ? "Customer".tr : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppThemeData.semiBoldTextStyle(fontSize: 15, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    phone.isEmpty ? "Phone number not shared".tr : phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppThemeData.regularTextStyle(
                      fontSize: 14,
                      color: phone.isEmpty
                          ? (isDark ? AppThemeData.grey500 : AppThemeData.grey500)
                          : (isDark ? AppThemeData.grey200 : AppThemeData.grey700),
                    ),
                  ),
                ],
              ),
            ),
            // Both actions are for a live booking. Once the trip is finished -
            // cancelled, expired, or completed once its departure time is far
            // enough behind us - there is nothing left to arrange, so the
            // contact stays on the card as history without inviting a call.
            // `ended` is DriverTripStatus.isFinished, so a status added to that
            // set closes these buttons without a second rule being written here.
            if (!ended) ...<Widget>[
              const SizedBox(width: 8),
              _contactButton(
                icon: Icons.call_outlined,
                tooltip: "Call".tr,
                enabled: phone.isNotEmpty,
                isDark: isDark,
                onTap: () => Constant.makePhoneCall(phone),
              ),
              const SizedBox(width: 8),
              _contactButton(
                icon: Icons.chat_bubble_outline,
                tooltip: "Chat".tr,
                enabled: (reservation?.customerId ?? trip.reservedBy ?? '').isNotEmpty,
                isDark: isDark,
                onTap: () => _openChat(controller, trip, reservation),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _contactButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final Color foreground = enabled
        ? AppThemeData.primary300
        : (isDark ? AppThemeData.grey600 : AppThemeData.grey400);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: enabled ? AppThemeData.primary300 : (isDark ? AppThemeData.grey700 : AppThemeData.grey200)),
          ),
          child: Icon(icon, size: 20, color: foreground),
        ),
      ),
    );
  }

  /// Opens the app's existing chat on this trip.
  ///
  /// The thread is keyed by the trip id, the same way every other chat in this
  /// project is keyed by its order id, so both apps land in the same
  /// `chat/{id}/thread` and the message shows up in the ordinary inbox.
  Future<void> _openChat(MyTripsController controller, DriverTripModel trip, TripReservationModel? reservation) async {
    final String customerId = (reservation?.customerId ?? trip.reservedBy ?? '').trim();
    if (customerId.isEmpty) return;

    ShowToastDialog.showLoader("Please wait".tr);
    final UserModel? me = await controller.currentUser();
    ShowToastDialog.closeLoader();
    if (me == null) {
      ShowToastDialog.showToast("Something went wrong. Please try again.".tr);
      return;
    }

    Get.to(const ChatScreen(), arguments: <String, dynamic>{
      "senderName": me.fullName(),
      "senderId": me.id,
      "senderProfileUrl": me.profilePictureURL ?? '',
      "receivedName": (reservation?.customerName ?? trip.reservedByName ?? '').trim(),
      "receivedId": customerId,
      "receivedProfileUrl": reservation?.customerPhoto ?? trip.reservedByPhoto ?? '',
      "orderId": trip.id,
      "token": reservation?.fcmToken ?? '',
      "chatType": Constant.userRoleDriver,
      "chatSubtitle": "${'Trip'.tr} \u00b7 ${trip.fromAddress ?? ''} \u2192 ${trip.toAddress ?? ''}",
    });
  }

  /// Confirms Complete Ride.
  ///
  /// Asked rather than done on the tap because the status it writes is final:
  /// a completed trip is history in both apps and there is no button that
  /// undoes it.
  void _confirmComplete(MyTripsController controller, DriverTripModel trip, bool isDark) {
    Get.dialog(
      AlertDialog(
        backgroundColor: isDark ? AppThemeData.grey800 : Colors.white,
        title: Text(
          "Complete Ride".tr,
          style: AppThemeData.semiBoldTextStyle(fontSize: 18, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
        ),
        content: Text(
          "This trip will be saved as completed and will appear in your ride history and the customer's.".tr,
          style: AppThemeData.regularTextStyle(fontSize: 14, color: isDark ? AppThemeData.grey300 : AppThemeData.grey700),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Get.back(),
            child: Text("No".tr, style: AppThemeData.semiBoldTextStyle(fontSize: 14, color: AppThemeData.grey500)),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              controller.completeTrip(trip);
            },
            child: Text("Yes".tr, style: AppThemeData.semiBoldTextStyle(fontSize: 14, color: AppThemeData.success400)),
          ),
        ],
      ),
    );
  }

  void _confirmCancel(MyTripsController controller, DriverTripModel trip, bool isDark) {
    Get.dialog(
      AlertDialog(
        backgroundColor: isDark ? AppThemeData.grey800 : Colors.white,
        title: Text(
          "Cancel Trip".tr,
          style: AppThemeData.semiBoldTextStyle(fontSize: 18, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
        ),
        content: Text(
          trip.hasReservation
              ? "This trip is already booked. The customer will be told it is cancelled.".tr
              : "This trip will stop being shown to customers.".tr,
          style: AppThemeData.regularTextStyle(fontSize: 14, color: isDark ? AppThemeData.grey300 : AppThemeData.grey700),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Get.back(),
            child: Text("No".tr, style: AppThemeData.semiBoldTextStyle(fontSize: 14, color: AppThemeData.grey500)),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              controller.cancelTrip(trip);
            },
            child: Text("Yes".tr, style: AppThemeData.semiBoldTextStyle(fontSize: 14, color: AppThemeData.danger300)),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status, bool isDark) {
    Color color;
    switch (status) {
      case DriverTripStatus.active:
        color = AppThemeData.success400;
        break;
      case DriverTripStatus.booked:
        color = AppThemeData.primary300;
        break;
      case DriverTripStatus.completed:
        color = AppThemeData.success400;
        break;
      case DriverTripStatus.cancelled:
        color = AppThemeData.danger300;
        break;
      default:
        color = isDark ? AppThemeData.grey400 : AppThemeData.grey500;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: color.withValues(alpha: 0.15)),
      child: Text(tabTitle(status), style: AppThemeData.semiBoldTextStyle(fontSize: 12, color: color)),
    );
  }

  Widget _locationRow(IconData icon, Color color, String label, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppThemeData.mediumTextStyle(fontSize: 14, color: isDark ? AppThemeData.grey100 : AppThemeData.grey800),
          ),
        ),
      ],
    );
  }
}
