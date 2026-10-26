import 'package:driver/app/cab_screen/bidding_request_card.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/controllers/bidding_request_controller.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/services/bidding_service.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// The driver's bidding inbox, shown under the map on the cab home screen.
///
/// Built only when the admin's global bidding switch is on; with it off this
/// widget returns nothing and the screen is exactly what it was before.
/// Everything is drawn with the driver app's own components - RoundedButtonFill,
/// TextFieldWidget, MySeparator - and AppThemeData typography and colours.
///
/// This is the **compact** view. The same offers, in a full screen with its own
/// empty and switched-off states, are the Bid section: `BiddingScreen`. Both
/// render [BiddingRequestCard], so the card can only ever change in one place.
class BiddingRequestsView extends StatelessWidget {
  const BiddingRequestsView({super.key, required this.isDark, required this.driver, required this.owner});

  final bool isDark;
  final UserModel driver;
  final UserModel owner;

  @override
  Widget build(BuildContext context) {
    if (!Constant.isBiddingEnabled) return const SizedBox.shrink();
    // Same pattern as every other screen in this app: the controller is owned
    // by the widget, so its Firestore listeners start with the view and are
    // cancelled in onClose() when it leaves.
    return GetX<BiddingRequestController>(
      init: BiddingRequestController(),
      builder: (BiddingRequestController controller) {
        // Picks the inbox up if the admin switched bidding on while the app
        // was already running. Idempotent.
        controller.start();
        final List<BiddingRequest> requests = controller.openRequests;
        if (requests.isEmpty) return const SizedBox.shrink();
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
          decoration: BoxDecoration(
            color: isDark ? AppThemeData.grey800 : Colors.white,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${'Ride offers near you'.tr} (${requests.length})",
                style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 16, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: requests.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => BiddingRequestCard(
                    isDark: isDark,
                    driver: driver,
                    owner: owner,
                    controller: controller,
                    request: requests[index],
                  ),
                ),
              ),
            ],
          ),
          );
      },
    );
  }
}
