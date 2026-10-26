import 'package:driver/app/cab_screen/bidding_request_card.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/controllers/bidding_request_controller.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/services/bidding_service.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/themes/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// **Bid** - the driver's own bidding section.
///
/// Built to the same shape as My Trips, which is what the client asked for:
///
/// > make another section for bid same like my trips for drivers... in
/// > bottombar
///
/// Bidding worked before this screen existed, but the only way to see an offer
/// was the compact inbox under the map on the cab home screen, and only while
/// the driver was idle and looking at that one screen. This is a place the
/// driver can go and find the offers, from anywhere in the cab section.
///
/// It replaces nothing. `BiddingRequestsView` still draws the same offers on
/// the home screen, from the same [BiddingRequestCard], so a driver who never
/// opens this tab sees exactly what they saw before.
class BiddingScreen extends StatelessWidget {
  const BiddingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeController themeController = Get.find<ThemeController>();

    return Obx(() {
      final bool isDark = themeController.isDark.value;
      return GetX<BiddingRequestController>(
        init: BiddingRequestController(),
        builder: (BiddingRequestController controller) {
          // Read one observable before the branch, always.
          //
          // A GetX builder that subscribes to nothing throws "the improper use
          // of a GetX has been detected", and in a release build that is drawn
          // as a blank body or an error box with no message - which is exactly
          // what the client reported twice on the customer app. Two of the
          // branches below (bidding switched off, and the driver already on a
          // ride) read no observable of their own, so the subscription is made
          // here, unconditionally, instead of being left to whichever branch
          // happens to be taken.
          final bool loading = controller.isLoading.value;
          final bool busy = controller.isBusyOnRide.value;

          return Scaffold(
            backgroundColor: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
            appBar: AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: AppThemeData.primary300,
              title: Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 10),
                child: Text(
                  "Ride Offers".tr,
                  style: const TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 20, color: AppThemeData.grey50),
                ),
              ),
            ),
            body: _body(context, controller, isDark: isDark, loading: loading, busy: busy),
          );
        },
      );
    });
  }

  Widget _body(
    BuildContext context,
    BiddingRequestController controller, {
    required bool isDark,
    required bool loading,
    required bool busy,
  }) {
    // The switch is checked before `start()` is called, the same way the home
    // screen's inbox checks it: with bidding off the controller's `start()`
    // clears its lists, and clearing an observable from inside a builder marks
    // an already-built subtree dirty.
    //
    // The tab itself stays in the bar either way. A section that appears and
    // disappears under the driver's thumb is worse than one that says why it
    // is empty - the same decision the customer app's Bid tab makes.
    if (!Constant.isBiddingEnabled) {
      return _message(
        isDark: isDark,
        icon: Icons.sell_outlined,
        title: "Bidding is currently unavailable".tr,
        detail: "Ride offers are switched off for now. Your ordinary ride requests are not affected.".tr,
      );
    }

    // Picks the inbox up if the admin switched bidding on while the app was
    // already running. Idempotent.
    controller.start();

    if (busy) {
      return _message(
        isDark: isDark,
        icon: Icons.directions_car_filled_outlined,
        title: "You are on a ride".tr,
        detail: "New ride offers will appear here once your current ride is finished.".tr,
      );
    }

    if (loading) {
      return Center(child: CircularProgressIndicator(color: AppThemeData.primary300));
    }

    final List<BiddingRequest> requests = controller.openRequests;
    if (requests.isEmpty) {
      return _message(
        isDark: isDark,
        icon: Icons.sell_outlined,
        title: "No ride offers right now".tr,
        detail: "When a customer names their own fare for a trip near you, it will show up here.".tr,
      );
    }

    // `Constant.userModel` is kept current by the cab dashboard's live user
    // listener, so it is the same driver the home screen's inbox works from.
    // The owner comes from the controller, which follows the owner's wallet
    // for a fleet driver - see `BiddingRequestController.owner`.
    final UserModel driver = Constant.userModel ?? UserModel();
    final UserModel owner = controller.owner.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            "${'Ride offers near you'.tr} (${requests.length})",
            style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 16, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            itemCount: requests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int index) => BiddingRequestCard(
              isDark: isDark,
              driver: driver,
              owner: owner,
              controller: controller,
              request: requests[index],
            ),
          ),
        ),
      ],
    );
  }

  /// One centred explanation. Never a bare blank body - a screen that draws
  /// nothing is indistinguishable from a screen that has crashed, which is the
  /// report this section was built to avoid repeating.
  Widget _message({
    required bool isDark,
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: isDark ? AppThemeData.grey600 : AppThemeData.grey300),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 17, color: isDark ? AppThemeData.grey100 : AppThemeData.grey800),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 14, color: isDark ? AppThemeData.grey400 : AppThemeData.grey500),
            ),
          ],
        ),
      ),
    );
  }
}
