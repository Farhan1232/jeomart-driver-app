import 'package:driver/constant/constant.dart';

/// The two figures the cab bottom navigation shows the driver: how much work is
/// still open, and how much has been finished.
///
/// The status strings live here rather than in the screen so the badge on the
/// bar, the "On Going" tab of the orders list and the Firestore query behind
/// both can never drift apart - a badge that says 2 above a tab that lists 3 is
/// worse than no badge at all. `CabOrderListController.tabStatuses` reads its
/// On Going and Completed rows from these lists, and a test asserts it.
class DriverRideCounts {
  DriverRideCounts._();

  /// A ride the driver still has to do something about.
  ///
  /// Firestore serves `driverId == uid AND status IN [...]` from its automatic
  /// single-field indexes - verified against the live project - so counting
  /// these needs no new composite index and nothing to deploy.
  static const List<String> ongoingStatuses = <String>[
    Constant.orderPlaced,
    Constant.orderAccepted,
    Constant.driverAccepted,
    Constant.driverPending,
    Constant.orderShipped,
    Constant.orderInTransit,
  ];

  /// A ride that is finished and paid attention to no longer.
  static const List<String> completedStatuses = <String>[Constant.orderCompleted];

  /// Rides that ended without being driven. Counted in neither figure.
  static const List<String> cancelledStatuses = <String>[Constant.orderRejected, Constant.orderCancelled, Constant.driverRejected];

  static bool isOngoing(String? status) => status != null && ongoingStatuses.contains(status);

  static bool isCompleted(String? status) => status != null && completedStatuses.contains(status);

  /// Upper bound on the live "ongoing" listener.
  ///
  /// A driver can only be on one ride at a time, so this is generous already;
  /// it exists so that a data problem - every ride left in `Order Placed`, say -
  /// cannot turn a bar badge into an unbounded read of the rides collection.
  static const int ongoingWatchLimit = 25;

  /// What the badge prints. Past the cap the exact number stops mattering and
  /// the width of the bar starts to.
  static String badgeLabel(int count) => count > 99 ? '99+' : '$count';
}
