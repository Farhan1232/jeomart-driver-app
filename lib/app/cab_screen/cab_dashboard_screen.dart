import 'package:driver/app/auth_screen/login_screen.dart';
import 'package:driver/app/cab_screen/bidding_screen.dart';
import 'package:driver/app/cab_screen/cab_order_list_screen.dart';
import 'package:driver/app/cab_screen/my_trips_screen.dart';
import 'package:driver/app/change_language/change_language_screen.dart';
import 'package:driver/app/change_password_screen/change_password_screen.dart';
import 'package:driver/app/chat_screens/driver_inbox_screen.dart';
import 'package:driver/app/change_section_screen/change_section_screen.dart';
import 'package:driver/app/edit_profile_screen/edit_profile_screen.dart';
import 'package:driver/app/terms_and_condition/terms_and_condition_screen.dart';
import 'package:driver/app/verification_screen/verification_screen.dart';
import 'package:driver/app/wallet_screen/wallet_screen.dart';
import 'package:driver/app/withdraw_method_setup_screens/withdraw_method_setup_screen.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/controllers/cab_dashboard_controller.dart';
import 'package:driver/services/audio_player_service.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/themes/custom_dialog_box.dart';
import 'package:driver/themes/theme_controller.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/driver_menu_visibility.dart';
import 'package:driver/utils/cab_bottom_navigation.dart';
import 'package:driver/utils/cab_nav_badges.dart';
import 'package:driver/utils/my_trips_access.dart';
import 'package:driver/utils/network_image_widget.dart';
import 'package:driver/widget/lazy_indexed_stack.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';

import '../vehicle_information_screen/vehicle_information_screen.dart';
import 'cab_home_screen.dart';

class CabDashboardScreen extends StatelessWidget {
  const CabDashboardScreen({super.key, this.embedded = false});

  /// True when this dashboard is rendered inside
  /// `MultiServiceDashboardScreen`, which already owns a bottom navigation bar
  /// for switching services. The cab bar is suppressed there so a
  /// multi-service driver never gets two stacked bars; that wrapper carries the
  /// My Trips tab itself instead.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    return Obx(() {
      final isDark = themeController.isDark.value;
      return GetX(
        init: CabDashBoardController(),
        builder: (controller) {
          return Scaffold(
            drawerEnableOpenDragGesture: false,
            appBar: AppBar(
              // backgroundColor: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
              titleSpacing: 5,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // One line each. An AppBar is a fixed 56 px box, so a driver
                  // whose name wrapped to a second line overflowed the bar
                  // instead of being shortened.
                  Text('Welcome Back 👋'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: isDark ? AppThemeData.grey50 : AppThemeData.grey900, fontSize: 12, fontFamily: AppThemeData.medium)),
                  Text(Constant.userModel!.fullName().tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: isDark ? AppThemeData.grey50 : AppThemeData.grey900, fontSize: 14, fontFamily: AppThemeData.semiBold)),
                ],
              ),
              actions: [
                Constant.userModel!.ownerId != null && Constant.userModel!.ownerId!.isNotEmpty
                    ? SizedBox()
                    : InkWell(
                      onTap: () {
                        Get.to(const WalletScreen(isAppBarShow: true));
                      },
                      child: SvgPicture.asset("assets/icons/ic_wallet_home.svg"),
                    ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () {
                    Get.to(const EditProfileScreen());
                  },
                  child: SvgPicture.asset("assets/icons/ic_user_business.svg"),
                ),
                const SizedBox(width: 10),
              ],
              leading: Builder(
                builder: (context) {
                  return InkWell(
                    onTap: () {
                      Scaffold.of(context).openDrawer();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Container(
                        decoration: ShapeDecoration(color: isDark ? AppThemeData.carRent600 : AppThemeData.carRent50, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(120))),
                        child: Padding(padding: const EdgeInsets.all(8), child: SvgPicture.asset("assets/icons/ic_drawer_open.svg")),
                      ),
                    ),
                  );
                },
              ),
            ),
            drawer: const DrawerView(),
            body: _dashboardBody(controller),
            bottomNavigationBar: _bottomNavigationBar(controller, isDark),
          );
        },
      );
    });
  }

  /// The four sections in the bottom bar, in the order they are held.
  ///
  /// These are the ones a driver moves between all day, so they are built once
  /// and kept. The drawer pages are not: they are visited rarely, several of
  /// them are forms, and keeping a form's half-finished state across a visit
  /// to the drawer is a change nobody asked for.
  static const List<int> _keptSections = <int>[
    CabBottomNavigation.homeDrawerIndex,
    CabBottomNavigation.ordersDrawerIndex,
    CabBottomNavigation.bidDrawerIndex,
    CabBottomNavigation.myTripsDrawerIndex,
  ];

  /// The dashboard body.
  ///
  /// Switching sections used to replace the body outright, which disposed the
  /// section being left: its controller reached `onClose`, its listeners were
  /// cancelled, and returning to it re-ran every Firestore query from scratch.
  /// The bar sections now live in a [LazyIndexedStack] that keeps them, and it
  /// stays mounted underneath the drawer pages so a trip to the drawer does not
  /// throw them away either.
  ///
  /// `StackFit.expand` because that is the constraint `body:` gave these
  /// screens before: a loose one would let them size to their content and
  /// change how every one of them lays out.
  Widget _dashboardBody(CabDashBoardController controller) {
    final int drawerIndex = controller.drawerIndex.value;
    final int section = _keptSections.indexOf(drawerIndex);
    final bool inKeptSection = section >= 0;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Offstage(
          offstage: !inKeptSection,
          // Animations and tickers in a section nobody is looking at do no
          // work while it waits offstage.
          child: TickerMode(
            enabled: inKeptSection,
            child: LazyIndexedStack(
              index: inKeptSection ? section : 0,
              itemCount: _keptSections.length,
              itemBuilder: (BuildContext context, int i) => _sectionFor(_keptSections[i]),
            ),
          ),
        ),
        if (!inKeptSection) _drawerPageFor(drawerIndex),
      ],
    );
  }

  /// One of the four kept sections.
  Widget _sectionFor(int drawerIndex) {
    switch (drawerIndex) {
      case CabBottomNavigation.ordersDrawerIndex:
        return const CabOrderListScreen();
      case CabBottomNavigation.bidDrawerIndex:
        return const BiddingScreen();
      case CabBottomNavigation.myTripsDrawerIndex:
        return const MyTripsScreen();
      default:
        return const CabHomeScreen();
    }
  }

  /// A drawer page: built when it is opened, thrown away when it is left,
  /// exactly as before.
  Widget _drawerPageFor(int drawerIndex) {
    switch (drawerIndex) {
      case 2:
        return const WalletScreen(isAppBarShow: false);
      case 3:
        return const WithdrawMethodSetupScreen();
      case 4:
        return const VerificationScreen();
      case 5:
        return const DriverInboxScreen();
      case 6:
        return VehicleInformationScreen(serviceType: 'cab-service');
      case 7:
        return const ChangeLanguageScreen();
      case 8:
        return const TermsAndConditionScreen(type: "temsandcondition");
      case 9:
        return const TermsAndConditionScreen(type: "privacy");
      default:
        return ChangePasswordScreen();
    }
  }

  /// The cab section's bottom navigation.
  ///
  /// Present for every driver, the way the customer app's bar is - it used to
  /// be built only for a driver holding a My Trips grant, which is why the
  /// client saw no bar at all. It writes to the **existing** `drawerIndex`
  /// rather than holding an index of its own, so the bar and the drawer are two
  /// views of one navigation state and there is no second navigation system to
  /// keep in step.
  ///
  /// Null only when this dashboard is embedded in the multi-service bar, which
  /// already has a bar of its own; two stacked bottom bars is not navigation.
  Widget? _bottomNavigationBar(CabDashBoardController controller, bool isDark) {
    if (embedded) return null;

    // A reactive read, so the My Trips tab appears and disappears with the live
    // users/{uid} listener the dashboard already keeps open.
    final MyTripsAccess access = controller.userModel.value.myTripsAccess;
    final DateTime now = DateTime.now();
    final List<CabNavDestination> destinations =
        CabBottomNavigation.destinationsFor(access, now, openToAllDrivers: Constant.driverTripSettings.openToAllDrivers);
    if (destinations.isEmpty) return null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _rideCountsStrip(controller, isDark),
        BottomNavigationBar(
          currentIndex: CabBottomNavigation.currentIndexFor(destinations, controller.drawerIndex.value),
          onTap: (int position) {
            controller.drawerIndex.value = CabBottomNavigation.drawerIndexFor(destinations, position);
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppThemeData.primary300,
          unselectedItemColor: isDark ? AppThemeData.grey400 : AppThemeData.grey500,
          backgroundColor: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
          items: destinations.map((destination) => _navItemFor(destination, controller)).toList(),
        ),
      ],
    );
  }

  /// The live "how much is left, how much is done" strip that sits on top of
  /// the bar.
  ///
  /// Both figures are real: `Ongoing` is the length of a live Firestore
  /// listener over the driver's unfinished rides, and `Completed` is a
  /// `count()` over the finished ones, re-read every time a ride leaves the
  /// ongoing set. Nothing here is derived from whatever a list screen happens
  /// to have paged in.
  ///
  /// Hidden until the first read lands, so the driver is never shown a
  /// confident zero that is really "not known yet".
  Widget _rideCountsStrip(CabDashBoardController controller, bool isDark) {
    if (!controller.rideCountsLoaded.value) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
        border: Border(top: BorderSide(color: isDark ? AppThemeData.grey700 : AppThemeData.grey200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Flexible halves. Both tiles were mainAxisSize.min and inflexible,
          // so on a narrow phone - or with a four-figure count - the two of
          // them together were wider than the strip.
          Flexible(
            child: _rideCountTile(icon: Icons.local_taxi_outlined, label: 'Ongoing'.tr, value: controller.ongoingRides.value, color: AppThemeData.primary300, isDark: isDark),
          ),
          Container(width: 1, height: 22, color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
          Flexible(
            child: _rideCountTile(icon: Icons.check_circle_outline, label: 'Completed'.tr, value: controller.completedRides.value, color: AppThemeData.success400, isDark: isDark),
          ),
        ],
      ),
    );
  }

  Widget _rideCountTile({required IconData icon, required String label, required int value, required Color color, required bool isDark}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text('$value', style: TextStyle(fontFamily: AppThemeData.bold, fontSize: 15, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900)),
        const SizedBox(width: 4),
        // The count is the figure that must stay readable; the word beside it
        // is the part that gives way when there is not enough room.
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppThemeData.medium, fontSize: 13, color: isDark ? AppThemeData.grey300 : AppThemeData.grey600)),
        ),
      ],
    );
  }

  /// One tab of the bar: a Font Awesome glyph, with whatever badge
  /// [CabNavBadges] says that section carries.
  ///
  /// The icons are Font Awesome rather than Material because these four
  /// sections need to be told apart at a glance at 22 px, and Material's
  /// outlined set gives Bid and My Trips two thin line drawings that read as
  /// the same shape on a small screen. The solid glyphs - a clipboard, a
  /// gavel, a route - are distinct silhouettes.
  ///
  /// Selected and unselected use the same glyph. `BottomNavigationBar` already
  /// separates them by colour, and swapping the shape as well makes the bar
  /// twitch as the driver moves between tabs.
  BottomNavigationBarItem _navItemFor(CabNavDestination destination, CabDashBoardController controller) {
    final CabNavBadge badge = CabNavBadges.badgeFor(
      drawerIndex: destination.drawerIndex,
      ongoingRides: controller.ongoingRides.value,
      hasSeenSection: controller.hasSeenSection,
    );
    final FaIconData glyph = _glyphFor(destination.drawerIndex);
    final Widget icon = _badged(FaIcon(glyph, size: 21), badge);
    return BottomNavigationBarItem(icon: icon, activeIcon: icon, label: destination.labelKey.tr);
  }

  /// The glyph per drawer slot. Keyed by slot, never by position, for the same
  /// reason the destinations themselves are.
  FaIconData _glyphFor(int drawerIndex) {
    switch (drawerIndex) {
      case CabBottomNavigation.ordersDrawerIndex:
        return FontAwesomeIcons.clipboardList;
      case CabBottomNavigation.bidDrawerIndex:
        // A gavel: the driver answers a customer's named fare here.
        return FontAwesomeIcons.gavel;
      case CabBottomNavigation.myTripsDrawerIndex:
        return FontAwesomeIcons.route;
      default:
        return FontAwesomeIcons.house;
    }
  }

  /// Draws [badge] over [icon].
  ///
  /// Two marks that can appear together, so they are two nested `Badge`s rather
  /// than one widget that tries to be both:
  ///
  /// * a **red counter**, top-right, for work waiting in that section;
  /// * a **green NEW ribbon**, top-left, for a section this driver has never
  ///   opened. It clears on the first visit and never comes back, which is what
  ///   keeps it meaning something.
  ///
  /// Both sit outside the icon's own box, so neither can push the row wide
  /// enough to overflow the bar; and `badge` is skipped entirely when there is
  /// nothing to draw, so an ordinary tab pays for no extra widgets.
  Widget _badged(Widget icon, CabNavBadge badge) {
    if (badge.isEmpty) return icon;

    Widget child = icon;

    if (badge.hasCount) {
      child = badges.Badge(
        badgeContent: Text(
          badge.label,
          style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: AppThemeData.bold),
        ),
        position: badges.BadgePosition.topEnd(top: -9, end: -12),
        badgeAnimation: const badges.BadgeAnimation.scale(toAnimate: false),
        badgeStyle: badges.BadgeStyle(
          shape: badges.BadgeShape.circle,
          badgeColor: AppThemeData.danger300,
          padding: const EdgeInsets.all(5),
          // A ring in the bar's own colour, so the counter reads as a separate
          // object sitting on the icon rather than as part of the glyph.
          borderSide: BorderSide(color: _barBackground(), width: 1.5),
          elevation: 0,
        ),
        child: child,
      );
    }

    if (badge.isNew) {
      child = badges.Badge(
        badgeContent: Text(
          "NEW".tr,
          style: const TextStyle(color: Colors.white, fontSize: 7, fontFamily: AppThemeData.bold, letterSpacing: 0.3),
        ),
        position: badges.BadgePosition.topStart(top: -14, start: -14),
        badgeAnimation: const badges.BadgeAnimation.scale(toAnimate: false),
        badgeStyle: badges.BadgeStyle(
          shape: badges.BadgeShape.square,
          borderRadius: BorderRadius.circular(9),
          badgeColor: AppThemeData.success400,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          borderSide: BorderSide(color: _barBackground(), width: 1.2),
          elevation: 0,
        ),
        child: child,
      );
    }

    return child;
  }

  /// The colour behind the bar, which both badge rings are drawn in.
  Color _barBackground() =>
      Get.find<ThemeController>().isDark.value ? AppThemeData.grey900 : AppThemeData.grey50;
}

class DrawerView extends StatelessWidget {
  const DrawerView({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    return Obx(() {
      var isDark = themeController.isDark.value;
      return GetX(
        init: CabDashBoardController(),
        builder: (controller) {
          return Drawer(
            backgroundColor: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
            child: Padding(
              padding: EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top + 20, left: 16, right: 16),
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  Row(
                    children: [
                      ClipOval(child: NetworkImageWidget(imageUrl: Constant.userModel == null ? "" : Constant.userModel!.profilePictureURL.toString(), height: 55, width: 55)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Constant.userModel!.fullName().tr, style: TextStyle(color: isDark ? AppThemeData.grey50 : AppThemeData.grey900, fontSize: 18, fontFamily: AppThemeData.semiBold)),
                            Text('${Constant.userModel!.email}'.tr, style: TextStyle(color: isDark ? AppThemeData.grey50 : AppThemeData.grey900, fontSize: 14, fontFamily: AppThemeData.regular)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                    trailing: Transform.scale(
                      scale: 0.8,
                      child: CupertinoSwitch(
                        value: controller.userModel.value.isActive ?? false,
                        activeTrackColor: AppThemeData.primary300,
                        onChanged: (value) async {
                          // Unchanged rule: a driver who must be verified, and is not, cannot go available.
                          if (Constant.userModel?.isAutoVerify == false && controller.userModel.value.isDocumentVerify != true) {
                            ShowToastDialog.showToast("Document verification is pending. Please proceed to set up your document verification.".tr);
                            return;
                          }
                          if (value == true) {
                            controller.updateCurrentLocation();
                          }
                          // One field, the same one the Admin Panel's Online switch writes. See DriverOnlineWrite.
                          final bool saved = await FireStoreUtils.setDriverOnlineStatus(value);
                          if (saved) {
                            controller.userModel.value.isActive = value;
                            controller.userModel.refresh();
                          } else {
                            ShowToastDialog.showToast("Status not changed. Please check your internet connection and try again.".tr);
                          }
                        },
                      ),
                    ),
                    dense: true,
                    title: Text('Available Status'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('About App'.tr, style: TextStyle(color: isDark ? AppThemeData.grey400 : AppThemeData.grey500, fontSize: 12, fontFamily: AppThemeData.medium)),
                  ),
                  ListTile(
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                    leading: SvgPicture.asset("assets/icons/ic_home_add.svg", width: 20),
                    trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                    dense: true,
                    title: Text('Home'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                    onTap: () {
                      Get.back();
                      controller.drawerIndex.value = 0;
                    },
                  ),
                  // "Hide Change Section - Driver App". The owner/vendor guard
                  // below is the pre-existing one and is unchanged; only the
                  // visibility flag is new, so restoring the entry is one edit.
                  if (DriverMenuVisibility.showChangeSection && (Constant.userModel?.ownerId ?? '').isEmpty && (Constant.userModel?.vendorID ?? '').isEmpty)
                    ListTile(
                      visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                      contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                      leading: SvgPicture.asset("assets/icons/ic_view_grid_list.svg", width: 20, colorFilter: ColorFilter.mode(AppThemeData.primary300, BlendMode.srcIn)),
                      trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                      dense: true,
                      title: Text('Change Section'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                      onTap: () {
                        Get.back();
                        Get.to(() => const ChangeSectionScreen());
                      },
                    ),
                  ListTile(
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                    leading: SvgPicture.asset("assets/icons/ic_shoping_cart.svg", colorFilter: ColorFilter.mode(AppThemeData.primary300, BlendMode.srcIn)),
                    trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                    dense: true,
                    title: Text('Orders'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                    onTap: () {
                      Get.back();
                      controller.drawerIndex.value = 1;
                    },
                  ),
                  // Bid - the customer-named-fare offers. Unconditional: unlike
                  // My Trips below, bidding is one global admin switch rather
                  // than a per-driver grant, and the screen explains itself
                  // when that switch is off.
                  ListTile(
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                    leading: const Icon(Icons.sell_outlined, size: 20),
                    trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                    dense: true,
                    title: Text('Bid'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                    onTap: () {
                      Get.back();
                      controller.drawerIndex.value = CabBottomNavigation.bidDrawerIndex;
                    },
                  ),
                  // My Trips - driver-created intercity / local full-vehicle
                  // trips. Built only while the admin's time-limited grant is
                  // valid; every other entry keeps its position and its
                  // drawerIndex, so nothing else in this drawer moves.
                  if (MyTripsGate.showsInNavigation(
                        controller.userModel.value.myTripsAccess,
                        DateTime.now(),
                        openToAllDrivers: Constant.driverTripSettings.openToAllDrivers,
                      ) ||
                      Constant.hasMyTripsAccess)
                    ListTile(
                      visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                      contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                      leading: const Icon(Icons.alt_route, size: 20),
                      trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                      dense: true,
                      title: Text('My Trips'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                      onTap: () {
                        Get.back();
                        controller.drawerIndex.value = 11;
                      },
                    ),
                  Constant.userModel!.ownerId != null && Constant.userModel!.ownerId!.isNotEmpty
                      ? SizedBox()
                      : ListTile(
                        visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                        contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                        leading: SvgPicture.asset("assets/icons/ic_wallet.svg", colorFilter: ColorFilter.mode(AppThemeData.primary300, BlendMode.srcIn)),
                        trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                        dense: true,
                        title: Text('Wallet'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                        onTap: () {
                          Get.back();
                          controller.drawerIndex.value = 2;
                        },
                      ),
                  Constant.userModel!.ownerId != null && Constant.userModel!.ownerId!.isNotEmpty
                      ? SizedBox()
                      : ListTile(
                        visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                        contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                        leading: SvgPicture.asset("assets/icons/ic_settings.svg"),
                        trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                        dense: true,
                        title: Text('Withdrawal Method'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                        onTap: () {
                          Get.back();
                          controller.drawerIndex.value = 3;
                        },
                      ),
                  (((Constant.userModel?.ownerId == null || Constant.userModel!.ownerId!.isEmpty) && Constant.userModel?.isAutoVerify == false) &&
                          !((Constant.userModel?.ownerId != null && Constant.userModel!.ownerId!.isNotEmpty) && Constant.userModel?.isAutoVerify == false))
                      ? ListTile(
                        visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                        contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                        leading: SvgPicture.asset("assets/icons/ic_notes.svg"),
                        trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                        dense: true,
                        title: Text('Document Verification'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                        onTap: () {
                          Get.back();
                          controller.drawerIndex.value = 4;
                        },
                      )
                      : const SizedBox.shrink(),
                  ListTile(
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                    leading: SvgPicture.asset("assets/icons/ic_chat.svg"),
                    trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                    dense: true,
                    title: Text('Inbox'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                    onTap: () {
                      Get.back();
                      controller.drawerIndex.value = 5;
                    },
                  ),
                  // "Hide Vehicle information - Driver App". The entry is the
                  // only writer of drawer slot 6, so hiding it makes
                  // VehicleInformationScreen unreachable without removing it or
                  // any vehicle data the ride, bidding and trip flows read.
                  if (DriverMenuVisibility.showVehicleInformation)
                    ListTile(
                      visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                      contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                      leading: Icon(Icons.car_crash),
                      trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                      dense: true,
                      title: Text('Vehicle Information'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                      onTap: () {
                        Get.back();
                        controller.drawerIndex.value = DriverMenuVisibility.vehicleInformationDrawerIndex;
                      },
                    ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('App Preferences'.tr, style: TextStyle(color: isDark ? AppThemeData.grey400 : AppThemeData.grey500, fontSize: 12, fontFamily: AppThemeData.medium)),
                  ),
                  ListTile(
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                    leading: SvgPicture.asset("assets/icons/ic_change_language.svg"),
                    trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                    dense: true,
                    title: Text('Change Language'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                    onTap: () {
                      Get.back();
                      controller.drawerIndex.value = 7;
                    },
                  ),
                  ListTile(
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                    leading: SvgPicture.asset("assets/icons/ic_light_dark.svg"),
                    trailing: Transform.scale(
                      scale: 0.8,
                      child: CupertinoSwitch(
                        value: controller.isDarkModeSwitch.value,
                        activeTrackColor: AppThemeData.primary300,
                        onChanged: (value) {
                          controller.toggleDarkMode(value);
                        },
                      ),
                    ),
                    dense: true,
                    title: Text('Dark Mode'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('Social'.tr, style: TextStyle(color: isDark ? AppThemeData.grey400 : AppThemeData.grey500, fontSize: 12, fontFamily: AppThemeData.medium)),
                  ),
                  ListTile(
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                    leading: SvgPicture.asset("assets/icons/ic_share.svg"),
                    trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                    dense: true,
                    title: Text('Share app'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                    onTap: () {
                      Get.back();
                      Share.share(
                        '${'Check out JEOM, your ultimate food delivery application!'.tr} \n\n${'Google Play:'.tr} ${Constant.googlePlayLink} \n\n${'App Store:'.tr} ${Constant.appStoreLink}',
                        subject: 'Look what I made!'.tr,
                      );
                    },
                  ),
                  ListTile(
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                    leading: SvgPicture.asset("assets/icons/ic_rate.svg"),
                    trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                    dense: true,
                    title: Text('Rate the app'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                    onTap: () {
                      Get.back();
                      final InAppReview inAppReview = InAppReview.instance;
                      // requestReview() alone shows nothing on an APK install or once Google's
                      // quota is used, so on Android the button opens the Play Store page.
                      if (GetPlatform.isAndroid) {
                        inAppReview.openStoreListing();
                      } else {
                        inAppReview.requestReview();
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('Legal'.tr, style: TextStyle(color: isDark ? AppThemeData.grey400 : AppThemeData.grey500, fontSize: 12, fontFamily: AppThemeData.medium)),
                  ),
                  ListTile(
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                    leading: SvgPicture.asset("assets/icons/ic_terms_condition.svg", colorFilter: ColorFilter.mode(AppThemeData.primary300, BlendMode.srcIn)),
                    trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                    dense: true,
                    title: Text('Terms and Conditions'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                    onTap: () {
                      Get.back();
                      controller.drawerIndex.value = 8;
                    },
                  ),
                  ListTile(
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                    leading: SvgPicture.asset("assets/icons/ic_privacyPolicy.svg", colorFilter: const ColorFilter.mode(AppThemeData.danger300, BlendMode.srcIn)),
                    trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                    dense: true,
                    title: Text('Privacy Policy'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                    onTap: () {
                      Get.back();
                      controller.drawerIndex.value = 9;
                    },
                  ),
                  if (Constant.userModel?.provider != 'apple' && Constant.userModel?.provider != 'google')
                    ListTile(
                      visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                      contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                      leading: SvgPicture.asset("assets/icons/ic_mail.svg", colorFilter: ColorFilter.mode(AppThemeData.primary300, BlendMode.srcIn)),
                      trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24),
                      dense: true,
                      title: Text('Change Password'.tr, style: TextStyle(color: isDark ? AppThemeData.grey100 : AppThemeData.grey800, fontFamily: AppThemeData.semiBold)),
                      onTap: () {
                        Get.back();
                        controller.drawerIndex.value = 10;
                      },
                    ),
                  const SizedBox(height: 10),
                  ListTile(
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    contentPadding: const EdgeInsets.only(left: 0.0, right: 0.0),
                    leading: SvgPicture.asset("assets/icons/ic_logout.svg", colorFilter: const ColorFilter.mode(AppThemeData.danger300, BlendMode.srcIn)),
                    trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 24, color: AppThemeData.danger300),
                    dense: true,
                    title: Text('Log out'.tr, style: TextStyle(color: isDark ? AppThemeData.danger300 : AppThemeData.danger300, fontFamily: AppThemeData.semiBold)),
                    onTap: () {
                      Get.back();
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return CustomDialogBox(
                            title: "Log out".tr,
                            descriptions: "Are you sure you want to log out? You will need to enter your credentials to log back in.".tr,
                            positiveString: "Log out".tr,
                            negativeString: "Cancel".tr,
                            positiveClick: () async {
                              await AudioPlayerService.playSound(false);
                              Constant.userModel!.fcmToken = "";
                              // Offline too: a logged-out driver left online kept being offered rides
                              // that nobody could see. The same write the Available switch makes.
                              await FireStoreUtils.setDriverOnlineStatus(false);
                              await FireStoreUtils.updateUser(Constant.userModel!);
                              await FirebaseAuth.instance.signOut();
                              Get.offAll(const LoginScreen());
                            },
                            negativeClick: () {
                              Get.back();
                            },
                            img: Image.asset('assets/images/ic_logout.gif', height: 50, width: 50),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return CustomDialogBox(
                            title: "Delete Account".tr,
                            descriptions: "Are you sure you want to delete your account? This action is irreversible and will permanently remove all your data.".tr,
                            positiveString: "Delete".tr,
                            negativeString: "Cancel".tr,
                            positiveClick: () async {
                              ShowToastDialog.showLoader("Please wait".tr);
                              await FireStoreUtils.deleteUser().then((value) {
                                ShowToastDialog.closeLoader();
                                if (value == true) {
                                  ShowToastDialog.showToast("Account deleted successfully".tr);
                                  Get.offAll(const LoginScreen());
                                } else {
                                  ShowToastDialog.showToast("Contact Administrator".tr);
                                }
                              });
                            },
                            negativeClick: () {
                              Get.back();
                            },
                            img: Image.asset('assets/icons/delete_dialog.gif', height: 50, width: 50),
                          );
                        },
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SvgPicture.asset("assets/icons/ic_delete.svg", colorFilter: const ColorFilter.mode(AppThemeData.danger300, BlendMode.srcIn)),
                        const SizedBox(width: 10),
                        Text('Delete Account'.tr, style: TextStyle(color: isDark ? AppThemeData.danger300 : AppThemeData.danger300, fontFamily: AppThemeData.semiBold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      "V : ${Constant.appVersion}",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: AppThemeData.medium, fontSize: 14, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}
