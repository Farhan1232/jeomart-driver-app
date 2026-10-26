import 'package:driver/app/cab_screen/cab_dashboard_screen.dart';
import 'package:driver/app/cab_screen/my_trips_screen.dart';
import 'package:driver/app/dash_board_screen/dash_board_screen.dart';
import 'package:driver/app/parcel_screen/parcel_dashboard_screen.dart';
import 'package:driver/app/rental_service/rental_dashboard_screen.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/controllers/cab_dashboard_controller.dart';
import 'package:driver/controllers/dash_board_controller.dart';
import 'package:driver/controllers/parcel_dashboard_controller.dart';
import 'package:driver/controllers/rental_dashboard_controller.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/themes/theme_controller.dart';
import 'package:driver/utils/cab_bottom_navigation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:driver/widget/lazy_indexed_stack.dart';

/// Controller that tracks which service tab is active.
class MultiServiceDashboardController extends GetxController {
  RxInt currentIndex = 0.obs;

  /// Whether the My Trips tab belongs in this bar right now.
  ///
  /// A boolean rather than the grant itself, so it only fires when the answer
  /// actually changes - the driver's `users/{uid}` document is rewritten on
  /// every location update, and rebuilding the bar for each of those would be
  /// waste. `CabDashBoardController`'s existing listener pushes into it, so no
  /// second Firestore listener is opened.
  RxBool myTripsEnabled = false.obs;

  @override
  void onInit() {
    super.onInit();
    myTripsEnabled.value = Constant.hasMyTripsAccess;
  }
}

/// Unified dashboard for drivers registered to multiple services.
/// Shows a BottomNavigationBar with one tab per registered service.
/// Each tab renders the full existing service dashboard.
class MultiServiceDashboardScreen extends StatelessWidget {
  const MultiServiceDashboardScreen({super.key});

  /// Returns the ordered list of service type keys for this driver.
  List<String> _serviceTypes() {
    final user = Constant.userModel;
    if (user == null) return ['delivery-service'];
    if (user.serviceTypes != null && user.serviceTypes!.isNotEmpty) {
      return user.serviceTypes!;
    }
    return [user.serviceTypes?.first ?? 'delivery-service'];
  }

  Widget _dashboardForService(String serviceType) {
    switch (serviceType) {
      case 'cab-service':
        // Embedded: this wrapper already owns a bottom bar, and the My Trips
        // tab below belongs to it, so the cab dashboard must not draw a second
        // one on top.
        return const CabDashboardScreen(embedded: true);
      case 'parcel_delivery':
        return const ParcelDashboardScreen();
      case 'rental-service':
        return const RentalDashboardScreen();
      default:
        return const DashBoardScreen();
    }
  }

  BottomNavigationBarItem _navItemForService(String serviceType) {
    switch (serviceType) {
      case 'cab-service':
        return const BottomNavigationBarItem(icon: Icon(Icons.local_taxi_outlined), activeIcon: Icon(Icons.local_taxi), label: 'Cab');
      case 'parcel_delivery':
        return const BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), activeIcon: Icon(Icons.inventory_2), label: 'Parcel');
      case 'rental-service':
        return const BottomNavigationBarItem(icon: Icon(Icons.car_rental_outlined), activeIcon: Icon(Icons.car_rental), label: 'Rental');
      default:
        return const BottomNavigationBarItem(icon: Icon(Icons.delivery_dining_outlined), activeIcon: Icon(Icons.delivery_dining), label: 'Delivery');
    }
  }

  /// Whether the My Trips tab belongs in this bar.
  ///
  /// My Trips is a cab feature, so it is offered to a driver who actually
  /// drives cabs and whose admin grant is currently valid - the same question
  /// the cab dashboard's own bar asks, answered from the same grant, so the
  /// two bars can never disagree.
  bool _showsMyTrips(MultiServiceDashboardController controller, List<String> serviceTypes) {
    if (!serviceTypes.contains('cab-service')) return false;
    // A reactive read, kept current by CabDashBoardController's user listener,
    // so a grant issued or revoked while the app is open reaches this bar.
    return controller.myTripsEnabled.value;
  }

  @override
  Widget build(BuildContext context) {
    final serviceTypes = _serviceTypes();

    // Single service: skip wrapper, go directly to the appropriate dashboard.
    // That dashboard draws its own bottom bar when the driver has a My Trips
    // grant, so a single-service cab driver is covered there rather than here.
    if (serviceTypes.length == 1) {
      return _dashboardForService(serviceTypes.first);
    }

    final themeController = Get.find<ThemeController>();

    return GetBuilder<MultiServiceDashboardController>(
      init: MultiServiceDashboardController(),
      builder: (controller) {
        return Obx(() {
          final isDark = themeController.isDark.value;

          // Pages and tabs are built from the same condition in the same build,
          // so the two lists always have the same length and a tab can never
          // point at the wrong page.
          final bool withMyTrips = _showsMyTrips(controller, serviceTypes);
          final List<Widget> pages = <Widget>[...serviceTypes.map(_dashboardForService), if (withMyTrips) const MyTripsScreen()];
          final List<BottomNavigationBarItem> items = <BottomNavigationBarItem>[
            ...serviceTypes.map(_navItemForService),
            if (withMyTrips) BottomNavigationBarItem(icon: const Icon(Icons.alt_route_outlined), activeIcon: const Icon(Icons.alt_route), label: 'My Trips'.tr),
          ];

          // If the grant lapsed while the driver was on the My Trips tab, the
          // stored index now points past the end. Clamp on read so an invalid
          // index is never handed to IndexedStack or BottomNavigationBar, and
          // put the stored value back in range after the frame.
          final int selected = CabBottomNavigation.safeTabIndex(controller.currentIndex.value, pages.length);
          if (selected != controller.currentIndex.value) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (controller.currentIndex.value >= pages.length) controller.currentIndex.value = 0;
            });
          }

          return Scaffold(
            // Lazy, not a plain IndexedStack.
            //
            // These children are whole service dashboards. A plain IndexedStack
            // builds all of them on the first frame, so entering this screen
            // started every section's GetX controller at once — each one
            // opening its own `users` listener, its own location stream and its
            // own order queries — for sections the driver may never open. A
            // multi-service driver paid for all of them to reach any of them.
            //
            // Lazy keeps the property that matters: a tab is built when it is
            // first selected and then kept, so going back to a section does not
            // re-run its queries over the network.
            body: LazyIndexedStack(
              index: selected,
              itemCount: pages.length,
              itemBuilder: (BuildContext context, int index) => pages[index],
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: selected,
              onTap: (index) {
                controller.currentIndex.value = index;
                // Reset each dashboard to home screen when switching tabs
                if (Get.isRegistered<DashBoardController>()) {
                  Get.find<DashBoardController>().drawerIndex.value = 0;
                }
                if (Get.isRegistered<CabDashBoardController>()) {
                  Get.find<CabDashBoardController>().drawerIndex.value = 0;
                }
                if (Get.isRegistered<ParcelDashboardController>()) {
                  Get.find<ParcelDashboardController>().drawerIndex.value = 0;
                }
                if (Get.isRegistered<RentalDashboardController>()) {
                  Get.find<RentalDashboardController>().drawerIndex.value = 0;
                }
              },
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppThemeData.primary300,
              unselectedItemColor: isDark ? AppThemeData.grey400 : AppThemeData.grey500,
              backgroundColor: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
              items: items,
            ),
          );
        });
      },
    );
  }
}
