import 'package:flutter_test/flutter_test.dart';

import 'package:driver/constant/constant.dart';
import 'package:driver/controllers/cab_order_list_controller.dart';
import 'package:driver/utils/driver_ride_counts.dart';

void main() {
  group('what counts as ongoing and what counts as completed', () {
    test('every status a driver can still act on is ongoing', () {
      for (final String status in <String>[
        Constant.orderPlaced,
        Constant.orderAccepted,
        Constant.driverAccepted,
        Constant.driverPending,
        Constant.orderShipped,
        Constant.orderInTransit,
      ]) {
        expect(DriverRideCounts.isOngoing(status), isTrue, reason: status);
        expect(DriverRideCounts.isCompleted(status), isFalse, reason: status);
      }
    });

    test('a finished ride is completed and not ongoing', () {
      expect(DriverRideCounts.isCompleted(Constant.orderCompleted), isTrue);
      expect(DriverRideCounts.isOngoing(Constant.orderCompleted), isFalse);
    });

    test('a ride that never happened is in neither figure', () {
      for (final String status in <String>[Constant.orderRejected, Constant.orderCancelled, Constant.driverRejected]) {
        expect(DriverRideCounts.isOngoing(status), isFalse, reason: status);
        expect(DriverRideCounts.isCompleted(status), isFalse, reason: status);
      }
    });

    test('an unknown or missing status is counted as nothing rather than guessed at', () {
      expect(DriverRideCounts.isOngoing(null), isFalse);
      expect(DriverRideCounts.isCompleted(null), isFalse);
      expect(DriverRideCounts.isOngoing('Something The Panel Invented'), isFalse);
    });

    test('the three sets do not overlap', () {
      final Set<String> ongoing = DriverRideCounts.ongoingStatuses.toSet();
      final Set<String> completed = DriverRideCounts.completedStatuses.toSet();
      final Set<String> cancelled = DriverRideCounts.cancelledStatuses.toSet();
      expect(ongoing.intersection(completed), isEmpty);
      expect(ongoing.intersection(cancelled), isEmpty);
      expect(completed.intersection(cancelled), isEmpty);
    });
  });

  group('the badge and the tab it points at', () {
    test('the On Going tab lists exactly what the badge counts', () {
      // If these ever diverge the driver sees a badge reading one number over a
      // tab listing another, which is worse than showing no badge.
      expect(CabOrderListController.tabStatuses['On Going'], DriverRideCounts.ongoingStatuses);
      expect(CabOrderListController.tabStatuses['Completed'], DriverRideCounts.completedStatuses);
      expect(CabOrderListController.tabStatuses['Cancelled'], DriverRideCounts.cancelledStatuses);
    });

    test('the ongoing query stays inside the Firestore whereIn limit', () {
      // `where(status, whereIn: ...)` is what makes the live count possible
      // without a new composite index; Firestore caps that list at 30.
      expect(DriverRideCounts.ongoingStatuses.length, lessThanOrEqualTo(30));
      expect(DriverRideCounts.ongoingStatuses, isNotEmpty);
    });

    test('the live listener is bounded so a bad data state cannot become a big read', () {
      expect(DriverRideCounts.ongoingWatchLimit, greaterThan(0));
      expect(DriverRideCounts.ongoingWatchLimit, lessThanOrEqualTo(50));
    });
  });

  group('the badge label', () {
    test('shows the number while it still fits', () {
      expect(DriverRideCounts.badgeLabel(1), '1');
      expect(DriverRideCounts.badgeLabel(12), '12');
      expect(DriverRideCounts.badgeLabel(99), '99');
    });

    test('caps rather than stretching the bar', () {
      expect(DriverRideCounts.badgeLabel(100), '99+');
      expect(DriverRideCounts.badgeLabel(4000), '99+');
    });
  });
}
