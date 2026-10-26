import 'package:driver/app/chat_screens/chat_screen.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/widget/upcoming_trip_banner.dart';
import 'package:driver/widget/map_diagnostics_overlay.dart';
import 'package:driver/utils/driver_verification_gate.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/controllers/cab_dashboard_controller.dart';
import 'package:driver/controllers/cab_home_controller.dart';
import 'package:driver/app/cab_screen/bidding_requests_view.dart';
import 'package:driver/models/cab_order_model.dart';
import 'package:driver/models/tax_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/themes/responsive.dart';
import 'package:driver/themes/round_button_fill.dart';
import 'package:driver/themes/theme_controller.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/utils.dart';
import 'package:driver/widget/my_separator.dart';
import 'package:driver/widget/osm_map/osm_tile_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as flutterMap;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:timelines_plus/timelines_plus.dart';

class CabHomeScreen extends StatelessWidget {
  const CabHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    final isDark = themeController.isDark.value;
    final dashController = Get.put(CabDashBoardController());
    return GetX(
      init: CabHomeController(),
      builder: (controller) {
        // Reactive: `Constant.mapType` and `Constant.selectedMapType` are
        // filled in by a network read at launch, and this screen picks its map
        // from them. Read through `mapChoice` the build is subscribed to that
        // read landing, so a home screen drawn before the settings arrived
        // redraws onto the right map straight away - it used to keep the map
        // it had guessed at until an unrelated rebuild, which in practice
        // meant until a ride came in.
        final MapChoice mapChoice = Constant.mapChoice;
        return withMapDiagnostics(
          Scaffold(
          body: controller.isLoading.value
              ? Constant.loader()
              : (controller.awaitsDocumentVerification.value ?? driverAwaitsDocumentVerification(Constant.userModel))
                  ? Obx(() {
                      final isDark = themeController.isDark.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              decoration: ShapeDecoration(
                                color: isDark ? AppThemeData.grey700 : AppThemeData.grey200,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(120),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: SvgPicture.asset("assets/icons/ic_document.svg"),
                              ),
                            ),
                            const SizedBox(
                              height: 12,
                            ),
                            Text(
                              "Document Verification in Pending".tr,
                              style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontSize: 22, fontFamily: AppThemeData.semiBold),
                            ),
                            const SizedBox(
                              height: 5,
                            ),
                            Text(
                              "Your documents are being reviewed. We will notify you once the verification is complete.".tr,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: isDark ? AppThemeData.grey50 : AppThemeData.grey500, fontSize: 16, fontFamily: AppThemeData.bold),
                            ),
                            const SizedBox(
                              height: 20,
                            ),
                            RoundedButtonFill(
                              title: "View Status".tr,
                              width: 55,
                              height: 5.5,
                              color: AppThemeData.primary300,
                              textColor: AppThemeData.grey50,
                              onPress: () async {
                                CabDashBoardController dashBoardController = Get.put(CabDashBoardController());
                                dashBoardController.drawerIndex.value = 4;
                              },
                            ),
                          ],
                        ),
                      );
                    })
                  : Stack(
                      // THE reason the cab driver's map was invisible.
                      //
                      // A Stack sizes itself to its largest **non-positioned**
                      // child, floored at the incoming minimum (RenderStack
                      // `_computeSize`), and a Scaffold body is handed
                      // constraints with `minHeight: 0`.
                      //
                      // Every child here is `Positioned` except one:
                      // `_rideDetailsSheet`, which returns a bare
                      // `SizedBox.shrink()` while there is no ride. So with no
                      // ride the only non-positioned child measured 0x0, the
                      // Stack collapsed to 0x0, and the `Positioned.fill` map
                      // below filled nothing. The screen showed the Scaffold's
                      // white background - the map was built, centred and
                      // fetching tiles the whole time, in a box of zero size.
                      //
                      // The moment a ride arrived the sheet returned a
                      // `Positioned.fill` instead, the Stack had no
                      // non-positioned child left, `size = constraints.biggest`
                      // applied, and the map appeared. That is the whole of
                      // "the map only works once a ride comes in".
                      //
                      // `StackFit.expand` makes this Stack fill whatever it is
                      // given, whatever its children do.
                      fit: StackFit.expand,
                      children: [
                        // The map, full-bleed. It used to be an `Expanded` sibling of
                        // the panels below, which is why it kept being squeezed down to
                        // a strip: nothing constrained them, so they took their natural
                        // height and the map got whatever was left over.
                        Positioned.fill(
                          child: mapChoice.isInApp
                              ? Stack(
                                  children: [
                                    mapChoice.isOsm
                                        ? flutterMap.FlutterMap(
                                            mapController: controller.osmMapController,
                                            options: flutterMap.MapOptions(
                                              // Read once, by design, so it must
                                              // not be a reactive read: the seed
                                              // is already resolved when this
                                              // builds, and every later position
                                              // moves the camera instead.
                                              initialCenter: controller.initialMapCentre,
                                              initialZoom: controller.initialMapZoom,
                                              // A fix that lands before the map
                                              // is laid out used to be swallowed
                                              // by a bare `catch`. It is held and
                                              // applied here instead.
                                              onMapReady: controller.onMapReady,
                                              keepAlive: true,
                                            ),
                                            children: [
                                              osmTileLayer(),
                                              // GetBuilder works inside flutter_map's LayoutBuilder; Obx does not
                                              GetBuilder<CabHomeController>(
                                                builder: (c) => flutterMap.MarkerLayer(markers: c.osmMarkers),
                                              ),
                                              GetBuilder<CabHomeController>(
                                                builder: (c) {
                                                  if (c.routePoints.isNotEmpty && c.currentOrder.value.id != null) {
                                                    return flutterMap.PolylineLayer(
                                                      polylines: [
                                                        flutterMap.Polyline(
                                                          points: c.routePoints,
                                                          strokeWidth: 7.0,
                                                          color: AppThemeData.primary300,
                                                        ),
                                                      ],
                                                    );
                                                  }
                                                  return const SizedBox.shrink();
                                                },
                                              ),
                                            ],
                                          )
                                        // `Obx`, so a position fix redraws the
                                        // map and nothing else.
                                        //
                                        // `markers`, `polyLines` and `current`
                                        // are all read here, and reading an Rx
                                        // inside the enclosing `GetX` builder
                                        // subscribes the *whole screen* to it.
                                        // The driver's `users` document is
                                        // rewritten on every location update,
                                        // and its listener rewrites all three,
                                        // so every few seconds this rebuilt the
                                        // ride sheet, the timeline, the notices
                                        // and the bidding inbox as well as the
                                        // map - on the one screen a driver
                                        // keeps open while driving. Scoped
                                        // here, the same fix redraws the map
                                        // alone. Nothing about what is read, or
                                        // when it updates, changes.
                                        : Obx(
                                            () => GoogleMap(
                                            onMapCreated: (mapController) {
                                              controller.mapController = mapController;
                                              final lat = controller.current.value.latitude != 0.0 ? controller.current.value.latitude : (Constant.locationDataFinal?.latitude ?? 0.0);
                                              final lng = controller.current.value.longitude != 0.0 ? controller.current.value.longitude : (Constant.locationDataFinal?.longitude ?? 0.0);
                                              controller.mapController!.animateCamera(
                                                CameraUpdate.newCameraPosition(
                                                  CameraPosition(target: LatLng(lat, lng), zoom: 15, bearing: double.parse('${controller.driverModel.value.rotation ?? '0.0'}')),
                                                ),
                                              );
                                            },
                                            myLocationEnabled: true,
                                            myLocationButtonEnabled: true,
                                            mapType: MapType.normal,
                                            zoomControlsEnabled: true,
                                            polylines: Set<Polyline>.of(controller.polyLines.values),
                                            markers: controller.markers.values.toSet(),
                                            initialCameraPosition: CameraPosition(
                                              zoom: 15,
                                              target: LatLng(
                                                controller.current.value.latitude != 0.0 ? controller.current.value.latitude : (Constant.locationDataFinal?.latitude ?? 0.0),
                                                controller.current.value.longitude != 0.0 ? controller.current.value.longitude : (Constant.locationDataFinal?.longitude ?? 0.0),
                                              ),
                                            ),
                                          ),
                                          ),
                                    if (mapChoice.isOsm)
                                      Positioned(
                                        top: 20,
                                        right: 20,
                                        child: FloatingActionButton(
                                          heroTag: 'center_osm',
                                          onPressed: () {
                                            try {
                                              controller.animateToSource();
                                            } catch (e) {
                                              // ignore
                                            }
                                          },
                                          child: const Icon(Icons.my_location),
                                        ),
                                      ),
                                  ],
                                )
                              : Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SvgPicture.asset("assets/images/ic_location_map.svg"),
                                      const SizedBox(
                                        height: 10,
                                      ),
                                      Text(
                                        "${'Navigate with'.tr} ${Constant.mapType == "google" ? "Google Map" : Constant.mapType == "googleGo" ? "Google Go" : Constant.mapType == "waze" ? "Waze Map" : Constant.mapType == "mapswithme" ? "MapsWithMe Map" : Constant.mapType == "yandexNavi" ? "VandexNavi Map" : Constant.mapType == "yandexMaps" ? "Vandex Map" : ""}",
                                        style: TextStyle(color: isDark ? AppThemeData.grey50 : AppThemeData.grey900, fontSize: 22, fontFamily: AppThemeData.semiBold),
                                      ),
                                      Text(
                                        "${'Easily find your destination with a single tap redirect to'.tr}  ${Constant.mapType == "google" ? "Google Map" : Constant.mapType == "googleGo" ? "Google Go" : Constant.mapType == "waze" ? "Waze Map" : Constant.mapType == "mapswithme" ? "MapsWithMe Map" : Constant.mapType == "yandexNavi" ? "VandexNavi Map" : Constant.mapType == "yandexMaps" ? "Vandex Map" : ""} ${'for seamless navigation.'.tr}",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: isDark ? AppThemeData.grey50 : AppThemeData.grey900, fontSize: 16, fontFamily: AppThemeData.regular),
                                      ),
                                      const SizedBox(
                                        height: 30,
                                      ),
                                      RoundedButtonFill(
                                        title:
                                            "${'Redirect'} ${Constant.mapType == "google" ? "Google Map" : Constant.mapType == "googleGo" ? "Google Go" : Constant.mapType == "waze" ? "Waze Map" : Constant.mapType == "mapswithme" ? "MapsWithMe Map" : Constant.mapType == "yandexNavi" ? "VandexNavi Map" : Constant.mapType == "yandexMaps" ? "Vandex Map" : ""}"
                                                .tr,
                                        width: 55,
                                        height: 5.5,
                                        color: AppThemeData.primary300,
                                        textColor: AppThemeData.grey50,
                                        onPress: () async {
                                          if (controller.currentOrder.value.id != null) {
                                            if (controller.currentOrder.value.status != Constant.driverPending) {
                                              // Accepted is the drive to the pickup as much as Shipped is: the
                                              // button did nothing for that whole leg.
                                              if (controller.currentOrder.value.status == Constant.orderShipped || controller.currentOrder.value.status == Constant.driverAccepted) {
                                                Utils.redirectMap(
                                                    name: controller.currentOrder.value.sourceLocationName.toString(),
                                                    latitude: controller.currentOrder.value.sourceLocation!.latitude ?? 0.0,
                                                    longLatitude: controller.currentOrder.value.sourceLocation!.longitude ?? 0.0);
                                              } else if (controller.currentOrder.value.status == Constant.orderInTransit) {
                                                Utils.redirectMap(
                                                    name: controller.currentOrder.value.destinationLocationName.toString(),
                                                    latitude: controller.currentOrder.value.destinationLocation!.latitude ?? 0.0,
                                                    longLatitude: controller.currentOrder.value.destinationLocation!.longitude ?? 0.0);
                                              }
                                            } else {
                                              Utils.redirectMap(
                                                  name: controller.currentOrder.value.sourceLocationName.toString(),
                                                  latitude: controller.currentOrder.value.sourceLocation!.latitude ?? 0.0,
                                                  longLatitude: controller.currentOrder.value.sourceLocation!.longitude ?? 0.0);
                                            }
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        // The two top notices, floated over the map rather than
                        // stacked above it, so they cost the map no height.
                        //
                        // One `Positioned` holding a `Column`, not two
                        // `Positioned(top: 0)` siblings that would draw on top
                        // of each other. Each notice still collapses to an
                        // empty box on its own, so the row is only as tall as
                        // whatever actually has something to say.
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: SafeArea(
                            bottom: false,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // The driver's scheduled trip, once its
                                // departure time is near. Reads nothing at all
                                // for a driver who cannot post trips.
                                UpcomingTripBanner(isDark: isDark),
                                Obx(() {
                              final user = dashController.userModel.value;
                              final controllerOwner = controller.ownerModel.value;
    
                              final num wallet = user.walletAmount ?? 0.0;
                              final num ownerWallet = controllerOwner.walletAmount ?? 0.0;
                              final String? ownerId = user.ownerId;
    
                              final num minDeposit = double.tryParse(Constant.minimumDepositToRideAccept) ?? 0;
    
                              // 🧠 Logic:
                              // If individual driver → check driver's own wallet
                              // If owner driver → check owner's wallet
                              if ((ownerId == null || ownerId.isEmpty) && wallet < minDeposit) {
                                // Individual driver case
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10, left: 10, right: 10),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppThemeData.danger50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        "${'You must have at least'.tr} ${Constant.amountShow(amount: Constant.minimumDepositToRideAccept.toString())} ${'in your wallet to receive orders'.tr}",
                                        style: TextStyle(
                                          color: AppThemeData.grey900,
                                          fontSize: 14,
                                          fontFamily: AppThemeData.semiBold,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              } else if (ownerId != null && ownerId.isNotEmpty && ownerWallet < minDeposit) {
                                // Owner-driver case
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10, left: 10, right: 10),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppThemeData.danger50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        "Your owner doesn't have the minimum wallet amount to receive orders. Please contact your owner.".tr,
                                        style: TextStyle(
                                          color: AppThemeData.grey900,
                                          fontSize: 14,
                                          fontFamily: AppThemeData.semiBold,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              } else {
                                return const SizedBox();
                              }
                                }),
                              ],
                            ),
                          ),
                        ),
                        // The ride panels - the same widgets, in the same order, now
                        // inside a sheet the driver can pull out of the way.
                        _rideDetailsSheet(isDark, controller),
                        // Bidding inbox, bottom-anchored. It never shares the screen
                        // with the sheet above: that one needs an order, this one
                        // renders only while there is none. It already caps its own
                        // height at 45% and draws its own rounded top, so it is left
                        // exactly as it was.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Obx(
                              () => controller.currentOrder.value.id == null
                                  ? BiddingRequestsView(
                                      isDark: isDark,
                                      driver: controller.driverModel.value,
                                      owner: controller.ownerModel.value,
                                    )
                                  : const SizedBox(),
                            ),
                        ),
                      ],
                    ),
        ),
          screen: 'CabHomeScreen',
          isLoading: controller.isLoading.value,
          mapCentre: controller.initialMapCentre.toString(),
        );
      },
    );
  }

  /// The ride panels, over the map, as a sheet the driver can drag.
  ///
  /// These were siblings of the map in a `Column`. Nothing constrained them, so
  /// they took their natural height - most of the screen once a ride was
  /// underway - and the `Expanded` map was left with the remainder. The driver
  /// could not see the road. The widgets and the order they appear in are
  /// unchanged; only the box around them is new.
  ///
  /// The pattern is the customer app's `DraggableScrollableSheet`, so a ride in
  /// progress feels the same in both apps.
  ///
  /// The two panels are mutually exclusive by construction and always have
  /// been: `shouldShowOrderSheet` excludes exactly the two statuses that put
  /// the timeline on screen. They are still asked separately rather than
  /// collapsed into an if/else, so neither question changes meaning here.
  Widget _rideDetailsSheet(bool isDark, CabHomeController controller) {
    return Obx(() {
      final bool isIncomingRequest = controller.currentOrder.value.id != null &&
          (controller.currentOrder.value.status == Constant.driverPending || controller.currentOrder.value.status == Constant.orderPlaced);
      final bool isRideUnderway = controller.shouldShowOrderSheet;

      // No ride, no sheet - the map gets the whole screen.
      if (!isIncomingRequest && !isRideUnderway) return const SizedBox.shrink();

      return Positioned.fill(
        child: DraggableScrollableSheet(
          // Half: the ride and the road at once. Dragging down to the handle
          // gives the whole map, dragging up gives the whole panel.
          initialChildSize: 0.5,
          minChildSize: 0.14,
          maxChildSize: 0.88,
          // Sizes the sheet to the drag position instead of filling the Stack,
          // which is what leaves the map visible above it.
          expand: false,
          snap: true,
          // `minChildSize` and `maxChildSize` are snap points already, so this
          // single entry is what makes the middle stop exist.
          snapSizes: const <double>[0.5],
          builder: (BuildContext context, ScrollController scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, -2))],
              ),
              clipBehavior: Clip.antiAlias,
              // The sheet only drags while the gesture reaches a scrollable
              // driven by `scrollController`, so the panels go in a ListView
              // even though they are a fixed short list.
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  _sheetGrabHandle(),
                  if (isIncomingRequest) showDriverBottomSheet(isDark, controller),
                  if (isRideUnderway) buildOrderActionsCard(isDark, controller),
                ],
              ),
            );
          },
        ),
      );
    });
  }

  /// The grab handle. Collapsed, the sheet is this plus the first row of the
  /// panel underneath, which is the summary the driver reads at a glance.
  Widget _sheetGrabHandle() {
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          height: 4,
          width: 40,
          decoration: BoxDecoration(color: AppThemeData.grey400, borderRadius: BorderRadius.circular(10)),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// What the ride pays: the fare the customer agreed, less any discount, plus
  /// the taxes on it.
  ///
  /// One figure, computed once, for both panels. The accepted-ride panel had
  /// this arithmetic inline and showed the result only on a cash ride, under
  /// "Collect payment from customer"; the incoming-request panel did not show
  /// a price at all, so a driver was asked to accept a 14 km job without being
  /// told what it was worth.
  ///
  /// `tryParse` throughout: the old `double.parse(x.toString())` threw on an
  /// order with no subtotal, which is a crash on the panel rather than a
  /// missing number.
  static double rideTotal(CabOrderModel order) {
    final double subTotal = double.tryParse(order.subTotal?.toString() ?? '') ?? 0.0;
    final double discount = double.tryParse(order.discount?.toString() ?? '') ?? 0.0;
    double taxAmount = 0.0;
    for (final TaxModel tax in order.taxSetting ?? <TaxModel>[]) {
      taxAmount = taxAmount + Constant.calculateTax(amount: (subTotal - discount).toString(), taxModel: tax);
    }
    return (subTotal - discount) + taxAmount;
  }

  /// One label-and-amount line, as both panels draw them.
  Widget _amountRow(String label, String amount, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontFamily: AppThemeData.regular,
              color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
              fontSize: 16,
            ),
          ),
        ),
        Text(
          amount,
          textAlign: TextAlign.start,
          style: TextStyle(
            fontFamily: AppThemeData.semiBold,
            color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Padding showDriverBottomSheet(bool isDark, CabHomeController controller) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: ShapeDecoration(
          color: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Timeline.tileBuilder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                theme: TimelineThemeData(
                  nodePosition: 0,
                  // indicatorPosition: 0,
                ),
                builder: TimelineTileBuilder.connected(
                  contentsAlign: ContentsAlign.basic,
                  indicatorBuilder: (context, index) {
                    return index == 0
                        ? Container(
                            decoration: ShapeDecoration(
                              color: AppThemeData.primary50,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(120),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: SvgPicture.asset(
                                "assets/icons/ic_building.svg",
                                colorFilter: ColorFilter.mode(AppThemeData.primary300, BlendMode.srcIn),
                              ),
                            ),
                          )
                        : Container(
                            decoration: ShapeDecoration(
                              color: AppThemeData.carRent50,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(120),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: SvgPicture.asset(
                                "assets/icons/ic_location.svg",
                                colorFilter: ColorFilter.mode(AppThemeData.primary300, BlendMode.srcIn),
                              ),
                            ),
                          );
                  },
                  connectorBuilder: (context, index, connectorType) {
                    return const DashedLineConnector(
                      color: AppThemeData.grey300,
                      gap: 3,
                    );
                  },
                  contentsBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: index == 0
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  controller.currentOrder.value.author?.fullName() ?? '',
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: AppThemeData.semiBold,
                                    fontSize: 16,
                                    color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                                  ),
                                ),
                                // No phone number here: this card is a request the driver
                                // has not accepted yet. It is shown after acceptance, in
                                // buildOrderActionsCard.
                                Text(
                                  "${controller.currentOrder.value.sourceLocationName}",
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: AppThemeData.medium,
                                    fontSize: 14,
                                    color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Destination".tr,
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: AppThemeData.semiBold,
                                    fontSize: 16,
                                    color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                                  ),
                                ),
                                Text(
                                  controller.currentOrder.value.destinationLocationName.toString(),
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: AppThemeData.medium,
                                    fontSize: 14,
                                    color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                  itemCount: 2,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: MySeparator(color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      "Trip Distance".tr,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontFamily: AppThemeData.regular,
                        color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    "${(double.tryParse(controller.currentOrder.value.distance.toString()) ?? 0.0).toStringAsFixed(2)} ${Constant.distanceType}",
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontFamily: AppThemeData.semiBold,
                      color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(
                height: 5,
              ),
              // The price, before Accept - the thing the driver is agreeing to.
              // It was only ever shown after accepting, and then only on a cash
              // ride.
              _amountRow(
                "Ride Fare".tr,
                Constant.amountShow(amount: rideTotal(controller.currentOrder.value).toString()),
                isDark,
              ),
              const SizedBox(
                height: 5,
              ),
              controller.currentOrder.value.tipAmount == null || controller.currentOrder.value.tipAmount!.isEmpty || (double.tryParse(controller.currentOrder.value.tipAmount.toString()) ?? 0) <= 0
                  ? const SizedBox()
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            "Tips".tr,
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontFamily: AppThemeData.regular,
                              color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          Constant.amountShow(amount: controller.currentOrder.value.tipAmount),
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontFamily: AppThemeData.semiBold,
                            color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      "Ride Type".tr,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontFamily: AppThemeData.regular,
                        color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    controller.currentOrder.value.rideType ?? '',
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontFamily: AppThemeData.semiBold,
                      color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(
                height: 5,
              ),
              const SizedBox(
                height: 10,
              ),
              Row(
                children: [
                  Expanded(
                    child: RoundedButtonFill(
                      title: "Reject".tr,
                      width: 24,
                      height: 5.5,
                      borderRadius: 10,
                      color: AppThemeData.danger300,
                      textColor: AppThemeData.grey50,
                      onPress: () {
                        controller.rejectOrder();
                      },
                    ),
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: RoundedButtonFill(
                      title: "Accept".tr,
                      width: 24,
                      height: 5.5,
                      borderRadius: 10,
                      color: AppThemeData.success400,
                      textColor: AppThemeData.grey50,
                      onPress: () {
                        if (controller.driverModel.value.ownerId != null && controller.driverModel.value.ownerId!.isNotEmpty) {
                          if (controller.ownerModel.value.walletAmount != null && controller.ownerModel.value.walletAmount! >= (double.tryParse(Constant.minimumDepositToRideAccept) ?? 0)) {
                            controller.acceptOrder();
                          } else {
                            ShowToastDialog.showToast("Your owner has to maintain minimum {amount} wallet balance to accept the cab booking. Please contact your owner"
                                .trParams({"amount": Constant.ownerMinimumDepositToRideAccept.toString()}).tr);
                          }
                        } else {
                          if ((controller.driverModel.value.walletAmount ?? 0) >= (double.tryParse(Constant.minimumDepositToRideAccept) ?? 0)) {
                            controller.acceptOrder();
                          } else {
                            ShowToastDialog.showToast("You don't have sufficient balance in your wallet.");
                          }
                        }
                      },
                    ),
                  )
                ],
              ),
              const SizedBox(
                height: 10,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Container buildOrderActionsCard(isDark, CabHomeController controller) {
    final double totalAmount = rideTotal(controller.currentOrder.value);

    return Container(
      color: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                controller.currentOrder.value.status == Constant.orderShipped || controller.currentOrder.value.status == Constant.driverAccepted
                    ? Row(
                        children: [
                          Container(
                            decoration: ShapeDecoration(
                              color: AppThemeData.primary50,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(120),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: SvgPicture.asset(
                                "assets/icons/ic_building.svg",
                                colorFilter: ColorFilter.mode(AppThemeData.primary300, BlendMode.srcIn),
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  controller.currentOrder.value.author?.fullName() ?? '',
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: AppThemeData.semiBold,
                                    fontSize: 16,
                                    color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                                  ),
                                ),
                                // The number itself, not only a button that dials it.
                                // "Both need to see each others phone numbers" was the
                                // report, and a call icon is not seeing it.
                                Builder(
                                  builder: (_) {
                                    final author = controller.currentOrder.value.author;
                                    final phone = '${author?.countryCode ?? ''}${author?.phoneNumber ?? ''}'.trim();
                                    if (phone.isEmpty) return const SizedBox.shrink();
                                    return Text(
                                      phone,
                                      textAlign: TextAlign.start,
                                      style: TextStyle(
                                        fontFamily: AppThemeData.medium,
                                        fontSize: 14,
                                        color: isDark ? AppThemeData.grey200 : AppThemeData.grey700,
                                      ),
                                    );
                                  },
                                ),
                                Text(
                                  "${controller.currentOrder.value.sourceLocationName}",
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: AppThemeData.medium,
                                    fontSize: 14,
                                    color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          Column(
                            children: [
                              InkWell(
                                onTap: () {
                                  Constant.makePhoneCall(controller.currentOrder.value.author?.phoneNumber?.toString() ?? '');
                                },
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: ShapeDecoration(
                                    shape: RoundedRectangleBorder(
                                      side: BorderSide(width: 1, color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
                                      borderRadius: BorderRadius.circular(120),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: SvgPicture.asset("assets/icons/ic_phone_call.svg"),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 10,
                              ),
                              InkWell(
                                onTap: () async {
                                  ShowToastDialog.showLoader("Please wait".tr);

                                  // Both profiles at once. Neither read depends on the other,
                                  // but they were awaited one after the other, so opening the
                                  // chat cost two full Firestore round trips laid end to end
                                  // with the "Please wait" loader on screen for both of them.
                                  final List<UserModel?> people = await Future.wait(<Future<UserModel?>>[
                                    FireStoreUtils.getUserProfile(controller.currentOrder.value.authorID.toString()),
                                    FireStoreUtils.getUserProfile(controller.currentOrder.value.driverId.toString()),
                                  ]);
                                  UserModel? customer = people[0];
                                  UserModel? driver = people[1];

                                  ShowToastDialog.closeLoader();

                                  // A profile that could not be read threw on a `!` below, so
                                  // the chat button did nothing at all.
                                  if (customer == null || driver == null) {
                                    ShowToastDialog.showToast("User not found".tr);
                                    return;
                                  }

                                  // The keys below are the ones `ChatController`
                                  // reads. This call site used to pass the
                                  // multi-vendor set (customerName /
                                  // restaurantId / ...), so the controller
                                  // found no receiver and the cab chat opened
                                  // onto a thread it could not send to.
                                  Get.to(const ChatScreen(), arguments: {
                                    "senderName": driver.fullName(),
                                    "senderId": driver.id,
                                    "senderProfileUrl": driver.profilePictureURL ?? "",
                                    "receivedName": customer.fullName(),
                                    "receivedId": customer.id,
                                    "receivedProfileUrl": customer.profilePictureURL ?? "",
                                    "orderId": controller.currentOrder.value.id,
                                    "token": customer.fcmToken,
                                    "chatType": Constant.userRoleDriver,
                                  });
                                },
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: ShapeDecoration(
                                    shape: RoundedRectangleBorder(
                                      side: BorderSide(width: 1, color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
                                      borderRadius: BorderRadius.circular(120),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: SvgPicture.asset("assets/icons/ic_wechat.svg"),
                                  ),
                                ),
                              )
                            ],
                          ),
                        ],
                      )
                    : Timeline.tileBuilder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        theme: TimelineThemeData(
                          nodePosition: 0,
                          // indicatorPosition: 0,
                        ),
                        builder: TimelineTileBuilder.connected(
                          contentsAlign: ContentsAlign.basic,
                          indicatorBuilder: (context, index) {
                            return index == 0
                                ? Container(
                                    decoration: ShapeDecoration(
                                      color: AppThemeData.primary50,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(120),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: SvgPicture.asset(
                                        "assets/icons/ic_building.svg",
                                        colorFilter: ColorFilter.mode(AppThemeData.primary300, BlendMode.srcIn),
                                      ),
                                    ),
                                  )
                                : Container(
                                    decoration: ShapeDecoration(
                                      color: AppThemeData.carRent50,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(120),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: SvgPicture.asset(
                                        "assets/icons/ic_location.svg",
                                        colorFilter: ColorFilter.mode(AppThemeData.primary300, BlendMode.srcIn),
                                      ),
                                    ),
                                  );
                          },
                          connectorBuilder: (context, index, connectorType) {
                            return const DashedLineConnector(
                              color: AppThemeData.grey300,
                              gap: 3,
                            );
                          },
                          contentsBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              child: index == 0
                                  ? Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                controller.currentOrder.value.author?.fullName() ?? '',
                                                textAlign: TextAlign.start,
                                                style: TextStyle(
                                                  fontFamily: AppThemeData.semiBold,
                                                  fontSize: 16,
                                                  color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                                                ),
                                              ),
                                              // The number itself, not only a button that dials it.
                                              // "Both need to see each others phone numbers" was the
                                              // report, and a call icon is not seeing it.
                                              Builder(
                                                builder: (_) {
                                                  final author = controller.currentOrder.value.author;
                                                  final phone = '${author?.countryCode ?? ''}${author?.phoneNumber ?? ''}'.trim();
                                                  if (phone.isEmpty) return const SizedBox.shrink();
                                                  return Text(
                                                    phone,
                                                    textAlign: TextAlign.start,
                                                    style: TextStyle(
                                                      fontFamily: AppThemeData.medium,
                                                      fontSize: 14,
                                                      color: isDark ? AppThemeData.grey200 : AppThemeData.grey700,
                                                    ),
                                                  );
                                                },
                                              ),
                                              Text(
                                                "${controller.currentOrder.value.sourceLocationName}",
                                                textAlign: TextAlign.start,
                                                style: TextStyle(
                                                  fontFamily: AppThemeData.medium,
                                                  fontSize: 14,
                                                  color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(
                                          width: 5,
                                        ),
                                        InkWell(
                                          onTap: () {
                                            Constant.makePhoneCall(controller.currentOrder.value.author?.phoneNumber?.toString() ?? '');
                                          },
                                          child: Container(
                                            width: 42,
                                            height: 42,
                                            decoration: ShapeDecoration(
                                              shape: RoundedRectangleBorder(
                                                side: BorderSide(width: 1, color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
                                                borderRadius: BorderRadius.circular(120),
                                              ),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: SvgPicture.asset("assets/icons/ic_phone_call.svg"),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Destination".tr,
                                                textAlign: TextAlign.start,
                                                style: TextStyle(
                                                  fontFamily: AppThemeData.semiBold,
                                                  fontSize: 16,
                                                  color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                                                ),
                                              ),
                                              Text(
                                                controller.currentOrder.value.destinationLocationName.toString(),
                                                textAlign: TextAlign.start,
                                                style: TextStyle(
                                                  fontFamily: AppThemeData.medium,
                                                  fontSize: 14,
                                                  color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(
                                          width: 5,
                                        ),
                                        InkWell(
                                          onTap: () async {
                                            ShowToastDialog.showLoader("Please wait".tr);

                                            // Both profiles at once. Neither read depends on the other,
                                            // but they were awaited one after the other, so opening the
                                            // chat cost two full Firestore round trips laid end to end
                                            // with the "Please wait" loader on screen for both of them.
                                            final List<UserModel?> people = await Future.wait(<Future<UserModel?>>[
                                              FireStoreUtils.getUserProfile(controller.currentOrder.value.authorID.toString()),
                                              FireStoreUtils.getUserProfile(controller.currentOrder.value.driverId.toString()),
                                            ]);
                                            UserModel? customer = people[0];
                                            UserModel? driver = people[1];

                                            ShowToastDialog.closeLoader();

                                            if (customer == null || driver == null) {
                                              ShowToastDialog.showToast("User not found".tr);
                                              return;
                                            }

                                            Get.to(const ChatScreen(), arguments: {
                                              "senderName": driver.fullName(),
                                              "senderId": driver.id,
                                              "senderProfileUrl": driver.profilePictureURL ?? "",
                                              "receivedName": customer.fullName(),
                                              "receivedId": customer.id,
                                              "receivedProfileUrl": customer.profilePictureURL ?? "",
                                              "orderId": controller.currentOrder.value.id,
                                              "token": customer.fcmToken,
                                              "chatType": Constant.userRoleDriver,
                                            });
                                          },
                                          child: Container(
                                            width: 42,
                                            height: 42,
                                            decoration: ShapeDecoration(
                                              shape: RoundedRectangleBorder(
                                                side: BorderSide(width: 1, color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
                                                borderRadius: BorderRadius.circular(120),
                                              ),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: SvgPicture.asset("assets/icons/ic_wechat.svg"),
                                            ),
                                          ),
                                        )
                                      ],
                                    ),
                            );
                          },
                          itemCount: 2,
                        ),
                      ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: MySeparator(color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        "Payment Type".tr,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontFamily: AppThemeData.regular,
                          color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      (controller.currentOrder.value.paymentMethod ?? '').toLowerCase() == "cod" ? "Cash on delivery".tr : "Online".tr,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontFamily: AppThemeData.semiBold,
                        color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 5,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        "Ride Type".tr,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontFamily: AppThemeData.regular,
                          color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      controller.currentOrder.value.rideType ?? '',
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontFamily: AppThemeData.semiBold,
                        color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 5,
                ),
                // The fare, on every ride. It used to appear only on a cash
                // ride, as "Collect payment from customer", so a driver on a
                // card or wallet ride never saw what the trip was worth.
                _amountRow(
                  "Ride Fare".tr,
                  Constant.amountShow(amount: totalAmount.toString()),
                  isDark,
                ),
                const SizedBox(
                  height: 5,
                ),
                // `paymentMethod` was dereferenced with `!`, which is a crash
                // on the panel for an order saved without one.
                (controller.currentOrder.value.paymentMethod ?? '').toLowerCase() == "cod"
                    ? _amountRow(
                        "Collect Payment from customer".tr,
                        Constant.amountShow(amount: totalAmount.toString()),
                        isDark,
                      )
                    : const SizedBox(),
                const SizedBox(
                  height: 5,
                ),
                controller.currentOrder.value.tipAmount == null || controller.currentOrder.value.tipAmount!.isEmpty || (double.tryParse(controller.currentOrder.value.tipAmount.toString()) ?? 0) <= 0
                    ? const SizedBox()
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              "Tips".tr,
                              textAlign: TextAlign.start,
                              style: TextStyle(
                                fontFamily: AppThemeData.regular,
                                color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Text(
                            Constant.amountShow(amount: controller.currentOrder.value.tipAmount),
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontFamily: AppThemeData.semiBold,
                              color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                const SizedBox(
                  height: 10,
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () async {
              if (controller.currentOrder.value.status == Constant.orderShipped || controller.currentOrder.value.status == Constant.driverAccepted) {
                showVerifyPassengerDialog(Get.context!, isDark, controller);
              } else {
                if ((controller.currentOrder.value.paymentMethod ?? '').toLowerCase() == "cod") {
                  showConfirmCashPaymentDialog(Get.context!, isDark, onConfirm: () {
                    controller.completeRide();
                  });
                } else if (controller.currentOrder.value.paymentStatus == true) {
                  controller.completeRide();
                } else {
                  ShowToastDialog.showToast("Customer payment is pending".tr);
                }
              }
            },
            child: Container(
              color: AppThemeData.primary300,
              // The width of the sheet this sits in, not the width of the
              // screen. `Get.context` is the root context, so on a tablet in
              // split screen - or any time the sheet is narrower than the
              // display - this button was being sized to the wrong box.
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  controller.currentOrder.value.status == Constant.orderShipped || controller.currentOrder.value.status == Constant.driverAccepted
                      ? Constant.enableOTPTripStart
                          ? "Verify Code to customer".tr
                          : "Pickup Customer".tr
                      : "Complete Ride".tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? AppThemeData.grey50 : AppThemeData.grey50,
                    fontSize: 16,
                    fontFamily: AppThemeData.semiBold,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  void showVerifyPassengerDialog(BuildContext context, bool isDark, CabHomeController controller) {
    if (Constant.enableOTPTripStart == false) {
      controller.onRideStatus();
      return;
    }
    PinInputController otpController = PinInputController();

    Get.dialog(
      Dialog(
        backgroundColor: isDark
            ? AppThemeData.greyDark50 // 👈 dark background
            : AppThemeData.grey50,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20), // keeps margin around
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: Responsive.width(90, context),
          // 90% of a phone, but never wider than a comfortable reading measure.
          // On a tablet, 90% put four OTP cells in the middle of half a screen
          // of empty card.
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            // Scrollable: this dialog is always shown with the keyboard up, and
            // the keyboard is subtracted from the height a dialog is given. On
            // a short screen, or at a large system font size, the fixed column
            // had nowhere to go.
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: Text("Verify Passenger".tr, style: AppThemeData.boldTextStyle(fontSize: 22, color: isDark ? AppThemeData.greyDark900 : AppThemeData.grey900))),
                    InkWell(
                      onTap: () {
                        Get.back();
                      },
                      child: Icon(Icons.close),
                    )
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  "Enter the OTP shared by the customer to begin the trip".tr,
                  textAlign: TextAlign.start,
                  style: AppThemeData.mediumTextStyle(color: isDark ? AppThemeData.greyDark900 : AppThemeData.grey900, fontSize: 14),
                ),
                SizedBox(height: 20),
                MaterialPinField(
                  length: 4,
                  pinController: otpController,
                  keyboardType: TextInputType.phone,
                  enableAutofill: true,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  hintCharacter: "-",
                  theme: MaterialPinTheme(
                    cellSize: const Size(50, 50),
                    shape: MaterialPinShape.outlined,
                    borderRadius: BorderRadius.circular(10),
                    textStyle: TextStyle(
                      fontFamily: AppThemeData.regular,
                      color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                    ),
                    hintStyle: TextStyle(
                      fontFamily: AppThemeData.regular,
                      color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                    ),
                    fillColor: isDark ? AppThemeData.grey800 : AppThemeData.grey100,
                    borderColor: isDark ? AppThemeData.grey800 : AppThemeData.grey100,
                    focusedBorderColor: AppThemeData.primary300,
                    cursorColor: AppThemeData.primary300,
                  ),
                  onChanged: (value) {},
                  onCompleted: (pin) async {
                    // OTP completed
                  },
                ),
                SizedBox(height: 25),
                RoundedButtonFill(
                  title: "Start Ride".tr,
                  height: 5.5,
                  color: AppThemeData.primary300,
                  textColor: AppThemeData.grey50,
                  onPress: () async {
                    if (otpController.text.length < 4) {
                      ShowToastDialog.showToast("Please enter valid OTP".tr);
                      return;
                    }
                    if (otpController.text != controller.currentOrder.value.otpCode) {
                      ShowToastDialog.showToast("Please enter valid OTP".tr);
                      return;
                    }
                    controller.onRideStatus();
                  },
                )
              ],
            ),
            ),
          ),
        ),
      ),
      barrierDismissible: true,
    );
  }

  void showConfirmCashPaymentDialog(BuildContext context, bool isDark, {required VoidCallback onConfirm}) {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        backgroundColor: isDark
            ? AppThemeData.greyDark50 // 👈 dark background
            : AppThemeData.grey50, // 👈 light background
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          // Capped for the same reason as the OTP dialog above: 90% of a
          // tablet is not a dialog, it is a page.
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Confirm Cash Payment".tr,
                      style: AppThemeData.boldTextStyle(
                        fontSize: 20,
                        color: isDark ? AppThemeData.greyDark900 : AppThemeData.grey900,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Get.back(),
                    child: const Icon(Icons.close, size: 22),
                  )
                ],
              ),

              const SizedBox(height: 12),

              // Message
              Text(
                "Are you sure you received the cash from the passenger?".tr,
                style: AppThemeData.mediumTextStyle(
                  fontSize: 14,
                  color: isDark ? AppThemeData.greyDark900 : AppThemeData.grey700,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: RoundedButtonFill(
                      title: "Cancel".tr,
                      color: isDark ? AppThemeData.grey600 : AppThemeData.grey300,
                      textColor: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                      height: 5,
                      onPress: () {
                        Get.back();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RoundedButtonFill(
                      title: "Complete Ride".tr,
                      color: AppThemeData.driverApp300,
                      textColor: AppThemeData.grey50,
                      height: 5,
                      onPress: () {
                        Get.back();
                        onConfirm();
                      },
                      // onPress: () {
                      //   if (controller.currentOrder.value.paymentStatus == true) {
                      //     Get.back();
                      //     onConfirm();
                      //   } else {
                      //     ShowToastDialog.showToast("Customer payment is pending".tr);
                      //   }
                      // },
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }
}
