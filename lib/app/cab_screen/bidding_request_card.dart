import 'package:driver/constant/constant.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/controllers/bidding_request_controller.dart';
import 'package:driver/models/ride_bid_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/services/bidding_service.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/themes/round_button_fill.dart';
import 'package:driver/themes/text_field_widget.dart';
import 'package:driver/widget/my_separator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// One ride offer, as the driver sees it.
///
/// Lifted out of `BiddingRequestsView` so the compact inbox under the map on
/// the cab home screen and the full **Bid** section render the *same* card.
/// They used to be one widget with the card inlined in it; a second copy on the
/// new screen would have been two cards to keep in step, and the accept /
/// counter-offer / withdraw rules are exactly the code that must not drift.
///
/// It owns no state. Everything it shows and everything a button does goes
/// through the [BiddingRequestController] it is handed, which is the single
/// controller the section mounts.
class BiddingRequestCard extends StatelessWidget {
  const BiddingRequestCard({
    super.key,
    required this.isDark,
    required this.driver,
    required this.owner,
    required this.controller,
    required this.request,
  });

  final bool isDark;
  final UserModel driver;
  final UserModel owner;
  final BiddingRequestController controller;
  final BiddingRequest request;

  @override
  Widget build(BuildContext context) {
    // `Obx`, and not the enclosing `GetX` builder, is what makes this card
    // follow the driver's own offer.
    //
    // Both places that draw this card build it from a `ListView.builder`
    // `itemBuilder`, and an `itemBuilder` runs during layout - after the
    // enclosing builder function has already returned. GetX only records the
    // observables read *while* that function runs, so `myBids` and `inFlight`,
    // which are read here, were never subscribed to. The card therefore kept
    // whatever it was first drawn with, and only changed when something else
    // the outer builder does read happened to tick.
    //
    // What the driver saw: Withdraw took the offer off the table, the toast
    // said so, and the card still said "Your offer" with a Withdraw button. A
    // second tap then found the offer already withdrawn and answered "This
    // offer is no longer available" - so from the outside the button did
    // nothing at all. Same for an offer just sent, which stayed showing
    // Counter Offer / Accept.
    //
    // Nothing about what the buttons do changes; this only makes the card
    // redraw when the offer it is showing changes.
    return Obx(() => _card(context));
  }

  Widget _card(BuildContext context) {
    final RideBidModel? mine = controller.myBids[request.id];
    final bool busy = controller.inFlight.contains(request.id);
    final double minimum = controller.minimumFareFor(request);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isDark ? AppThemeData.grey700 : AppThemeData.grey50,
        border: Border.all(color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _locationRow(Icons.stop_circle_outlined, Colors.green, "Pickup".tr, request.ride.sourceLocationName ?? ''),
          const SizedBox(height: 6),
          _locationRow(Icons.radio_button_checked, Colors.red, "Destination".tr, request.ride.destinationLocationName ?? ''),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: MySeparator(color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  // `distanceKm` is normalised kilometres, so the unit is
                  // stated rather than taken from `Constant.distanceType`,
                  // which is the *display* unit and reads "Miles" on some
                  // installs.
                  "${'Trip Distance'.tr}: ${request.distanceKm.toStringAsFixed(2)} ${'KM'.tr}",
                  style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 14, color: isDark ? AppThemeData.grey300 : AppThemeData.grey600),
                ),
              ),
              Text(
                Constant.amountShow(amount: request.offeredFare.toString()),
                style: TextStyle(fontFamily: AppThemeData.bold, fontSize: 18, color: AppThemeData.primary300),
              ),
            ],
          ),
          Text(
            "Customer's offer".tr,
            style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 12, color: isDark ? AppThemeData.grey300 : AppThemeData.grey600),
          ),
          if (minimum > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "${'The minimum fare for this trip is'.tr} ${Constant.amountShow(amount: minimum.toString())}",
                style: TextStyle(fontFamily: AppThemeData.medium, fontSize: 12, color: AppThemeData.warning400),
              ),
            ),
          const SizedBox(height: 10),
          if (mine != null && mine.isLive)
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${'Your offer'.tr}: ${Constant.amountShow(amount: (mine.amount ?? 0).toString())}",
                    style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 15, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
                  ),
                ),
                RoundedButtonFill(
                  title: "Withdraw".tr,
                  width: 26,
                  height: 4.5,
                  borderRadius: 10,
                  color: AppThemeData.danger300,
                  textColor: AppThemeData.grey50,
                  onPress: () {
                    if (busy) return;
                    controller.withdraw(request);
                  },
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: RoundedButtonFill(
                    title: "Counter Offer".tr,
                    height: 5,
                    borderRadius: 10,
                    color: AppThemeData.warning400,
                    textColor: AppThemeData.grey50,
                    onPress: () {
                      if (busy) return;
                      final String? blocked = controller.walletBlocker(driver: driver, owner: owner);
                      if (blocked != null) {
                        ShowToastDialog.showToast(blocked);
                        return;
                      }
                      _openCounterOfferSheet(context, request);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RoundedButtonFill(
                    title: "Accept".tr,
                    height: 5,
                    borderRadius: 10,
                    color: AppThemeData.success400,
                    textColor: AppThemeData.grey50,
                    onPress: () {
                      if (busy) return;
                      final String? blocked = controller.walletBlocker(driver: driver, owner: owner);
                      if (blocked != null) {
                        ShowToastDialog.showToast(blocked);
                        return;
                      }
                      controller.acceptOfferedFare(request);
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _locationRow(IconData icon, Color color, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, color: color, size: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 12, color: isDark ? AppThemeData.grey300 : AppThemeData.grey600),
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AppThemeData.medium, fontSize: 14, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One "+50" style chip. Adds to whatever is currently in the box, so two
  /// taps on +50 is +100 and the driver is never made to do the arithmetic.
  Widget _raiseChip(num step) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => controller.raiseCounterOffer(step),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppThemeData.primary300),
          color: AppThemeData.primary300.withValues(alpha: 0.10),
        ),
        child: Text(
          "+${Constant.amountShow(amount: step.toString())}",
          style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 13, color: AppThemeData.primary300),
        ),
      ),
    );
  }

  /// The counter-offer sheet: an amount, and the note the client asked for.
  void _openCounterOfferSheet(BuildContext context, BiddingRequest request) {
    controller.counterOfferTextEditController.value.text = request.offeredFare.toString();
    final RxBool withNote = true.obs;

    Get.bottomSheet(
      // The keyboard inset has to be read from the **sheet's own** context.
      //
      // `MediaQuery.of(context)` on the card's context is evaluated once, here,
      // while the sheet is still being constructed - so the number it captured
      // was always "no keyboard", and it never changed afterwards. The box the
      // sheet opens raises the keyboard immediately, and Send Offer then sat
      // underneath it with no way to scroll to it. A `Builder` puts the read
      // below the route, where it is live.
      Builder(
        builder: (BuildContext sheetContext) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppThemeData.grey800 : Colors.white,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        // Scrollable, so a short screen - or a large system font, or a long
        // list of quick-raise chips - shortens the sheet rather than
        // overflowing it.
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Counter Offer".tr,
              style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 18, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
            ),
            const SizedBox(height: 4),
            Text(
              "${'Customer\'s offer'.tr}: ${Constant.amountShow(amount: request.offeredFare.toString())}",
              style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 14, color: isDark ? AppThemeData.grey300 : AppThemeData.grey600),
            ),
            const SizedBox(height: 12),
            TextFieldWidget(
              title: "Your fare".tr,
              hintText: "Enter your counter offer".tr,
              controller: controller.counterOfferTextEditController.value,
              textInputType: const TextInputType.numberWithOptions(decimal: true),
            ),
            // Quick raises, the way the client described the feature: "the
            // driver can increase the bidding, like +50, +100, any amount".
            // The box stays typeable, so an amount that is not on a chip is
            // still one edit away.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: BiddingRequestController.quickRaises
                  .map((num step) => _raiseChip(step))
                  .toList(),
            ),
            const SizedBox(height: 4),
            Obx(
              () => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: withNote.value,
                onChanged: (bool? value) => withNote.value = value ?? false,
                title: Text(
                  BiddingService.driverNoteKey.tr,
                  style: TextStyle(fontFamily: AppThemeData.medium, fontSize: 15, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
                ),
              ),
            ),
            const SizedBox(height: 4),
            RoundedButtonFill(
              title: "Send Offer".tr,
              height: 5.5,
              borderRadius: 10,
              color: AppThemeData.primary300,
              textColor: AppThemeData.grey50,
              onPress: () async {
                Get.back();
                await controller.sendCounterOffer(request, withNote: withNote.value);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
        ),
      ),
      ),
      isScrollControlled: true,
    );
  }
}
