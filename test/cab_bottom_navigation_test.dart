import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/utils/cab_bottom_navigation.dart';
import 'package:driver/utils/my_trips_access.dart';

/// The conditional My Trips tab in the driver's cab bottom navigation.
///
/// These assert the real data the widget builds from: which tabs exist, which
/// one is selected for a given drawer slot, and where a tap goes. Keeping that
/// logic out of the widget is what makes "no index-shifting bug when the tab
/// appears or disappears" something that can be proved rather than eyeballed.
void main() {
  /// A local clock: `Timestamp.toDate()` returns a local `DateTime`, and Dart's
  /// `DateTime ==` compares the UTC flag as well as the instant.
  final DateTime now = DateTime(2026, 9, 5, 10, 0);

  MyTripsAccess grantOf({required int days, DateTime? grantedAt, bool granted = true, DateTime? revokedAt}) {
    final DateTime start = grantedAt ?? now;
    return MyTripsAccess.fromJson(<String, dynamic>{
      'granted': granted,
      'durationDays': days,
      'grantedAt': Timestamp.fromDate(start),
      'expiresAt': MyTripsAccess.expiryFor(grantedAt: start, durationDays: days),
      'revokedAt': revokedAt == null ? null : Timestamp.fromDate(revokedAt),
      'grantedBy': 'admin1',
    });
  }

  List<int> slotsOf(List<CabNavDestination> destinations) => destinations.map((CabNavDestination d) => d.drawerIndex).toList();

  List<String> labelsOf(List<CabNavDestination> destinations) => destinations.map((CabNavDestination d) => d.labelKey).toList();

  group('driver WITH a valid grant', () {
    test('the bottom navigation bar is shown', () {
      expect(CabBottomNavigation.isVisible(grantOf(days: 7), now), isTrue);
    });

    test('My Trips is one of its tabs', () {
      final List<CabNavDestination> destinations = CabBottomNavigation.destinationsFor(grantOf(days: 7), now);
      expect(labelsOf(destinations), <String>['Home', 'Orders', 'Bid', 'My Trips']);
      expect(slotsOf(destinations), <int>[0, 1, 12, 11]);
    });

    test('the My Trips tab points at the existing My Trips drawer slot', () {
      final List<CabNavDestination> destinations = CabBottomNavigation.destinationsFor(grantOf(days: 7), now);
      expect(destinations.last.drawerIndex, CabBottomNavigation.myTripsDrawerIndex);
      // The same slot the Session 3 drawer entry and the dashboard body switch
      // already use, so the tab opens the existing screen and controller.
      expect(CabBottomNavigation.myTripsDrawerIndex, 11);
    });

    test('a 1-day, a 10-day and a 30-day grant all show the tab', () {
      for (final int days in <int>[1, 10, 30]) {
        expect(labelsOf(CabBottomNavigation.destinationsFor(grantOf(days: days), now)), contains('My Trips'), reason: '$days-day grant');
      }
    });

    test('tapping each tab sends the drawer to that tab\'s own slot', () {
      final List<CabNavDestination> destinations = CabBottomNavigation.destinationsFor(grantOf(days: 7), now);
      expect(CabBottomNavigation.drawerIndexFor(destinations, 0), 0);
      expect(CabBottomNavigation.drawerIndexFor(destinations, 1), 1);
      expect(CabBottomNavigation.drawerIndexFor(destinations, 2), 12);
      expect(CabBottomNavigation.drawerIndexFor(destinations, 3), 11);
    });

    test('the selected tab follows the drawer slot on screen', () {
      final List<CabNavDestination> destinations = CabBottomNavigation.destinationsFor(grantOf(days: 7), now);
      expect(CabBottomNavigation.currentIndexFor(destinations, 0), 0);
      expect(CabBottomNavigation.currentIndexFor(destinations, 1), 1);
      expect(CabBottomNavigation.currentIndexFor(destinations, 12), 2);
      expect(CabBottomNavigation.currentIndexFor(destinations, 11), 3);
    });

    test('a drawer-only screen selects a valid tab rather than an out-of-range one', () {
      // Wallet (2), Withdrawal (3), Verification (4), Inbox (5), Vehicle (6),
      // Language (7), the legal pages (8, 9) and Change Password (10) are
      // reachable from the drawer but are not tabs. BottomNavigationBar asserts
      // on an out-of-range currentIndex, so each must still resolve. Slot 12 is
      // deliberately absent from this list: it is the Bid tab.
      final List<CabNavDestination> destinations = CabBottomNavigation.destinationsFor(grantOf(days: 7), now);
      for (final int slot in <int>[2, 3, 4, 5, 6, 7, 8, 9, 10]) {
        final int index = CabBottomNavigation.currentIndexFor(destinations, slot);
        expect(index, inInclusiveRange(0, destinations.length - 1), reason: 'drawer slot $slot');
      }
    });
  });

  group('driver WITHOUT a grant', () {
    test('the bar is still there - Home, Orders and Bid do not depend on a grant', () {
      // This is the client's "driver app ... is not showing bottom bar". The
      // bar used to be built only for granted drivers, and no driver on the
      // live project holds a grant, so it existed for nobody.
      expect(CabBottomNavigation.isVisible(MyTripsAccess.none, now), isTrue);
      final List<CabNavDestination> destinations = CabBottomNavigation.destinationsFor(MyTripsAccess.none, now);
      expect(labelsOf(destinations), <String>['Home', 'Orders', 'Bid']);
    });

    test('My Trips is not among the destinations', () {
      expect(labelsOf(CabBottomNavigation.destinationsFor(MyTripsAccess.none, now)), isNot(contains('My Trips')));
    });

    test('resolving an index against an empty bar cannot throw', () {
      expect(CabBottomNavigation.currentIndexFor(const <CabNavDestination>[], 11), 0);
      expect(CabBottomNavigation.drawerIndexFor(const <CabNavDestination>[], 2), 0);
    });
  });

  group('the grant ends while the app is running', () {
    test('an expired grant removes the tab but leaves the bar standing', () {
      final MyTripsAccess access = grantOf(days: 1);
      final DateTime later = now.add(const Duration(days: 2));
      expect(labelsOf(CabBottomNavigation.destinationsFor(access, now)), contains('My Trips'));
      expect(labelsOf(CabBottomNavigation.destinationsFor(access, later)), <String>['Home', 'Orders', 'Bid']);
      expect(CabBottomNavigation.isVisible(access, later), isTrue, reason: 'the driver still needs Home and Orders');
    });

    test('a revoked grant removes the tab immediately, even inside its window', () {
      final MyTripsAccess access = grantOf(days: 30, revokedAt: now);
      final DateTime later = now.add(const Duration(minutes: 1));
      expect(CabBottomNavigation.hasMyTrips(access, later), isFalse);
      expect(labelsOf(CabBottomNavigation.destinationsFor(access, later)), isNot(contains('My Trips')));
    });

    test('a driver sitting on My Trips is sent back to Home, not left on a dead slot', () {
      final MyTripsAccess expired = grantOf(days: 1);
      final DateTime later = now.add(const Duration(days: 2));
      expect(CabBottomNavigation.safeDrawerIndexFor(access: expired, now: later, drawerIndex: 11), CabBottomNavigation.homeDrawerIndex);
    });

    test('a driver on any other screen is left where they are', () {
      final MyTripsAccess expired = grantOf(days: 1);
      final DateTime later = now.add(const Duration(days: 2));
      for (final int slot in <int>[0, 1, 2, 5, 6]) {
        expect(CabBottomNavigation.safeDrawerIndexFor(access: expired, now: later, drawerIndex: slot), slot);
      }
    });

    test('a valid grant leaves a driver on My Trips exactly where they are', () {
      expect(CabBottomNavigation.safeDrawerIndexFor(access: grantOf(days: 7), now: now, drawerIndex: 11), 11);
    });

    test('the tab disappearing never re-maps the tabs that remain', () {
      // The bar is keyed by drawer slot, not by position, so Home and Orders
      // keep their meaning whether or not My Trips is present.
      final List<CabNavDestination> withTab = CabBottomNavigation.destinationsFor(grantOf(days: 7), now);
      expect(CabBottomNavigation.drawerIndexFor(withTab, 0), CabBottomNavigation.homeDrawerIndex);
      expect(CabBottomNavigation.drawerIndexFor(withTab, 1), CabBottomNavigation.ordersDrawerIndex);
      expect(CabBottomNavigation.drawerIndexFor(withTab, 2), CabBottomNavigation.bidDrawerIndex);

      // And an index left over from the wider bar cannot address a page that is
      // no longer there.
      final List<CabNavDestination> withoutTab = CabBottomNavigation.destinationsFor(MyTripsAccess.none, now);
      expect(CabBottomNavigation.drawerIndexFor(withoutTab, 0), CabBottomNavigation.homeDrawerIndex);
      expect(CabBottomNavigation.drawerIndexFor(withoutTab, 1), CabBottomNavigation.ordersDrawerIndex);
      expect(CabBottomNavigation.drawerIndexFor(withoutTab, 2), CabBottomNavigation.bidDrawerIndex);
      expect(CabBottomNavigation.drawerIndexFor(withoutTab, 3), CabBottomNavigation.homeDrawerIndex);
    });
  });

  group('the multi-service bar, whose selected tab is stored state', () {
    test('a stored index inside range is used as it is', () {
      expect(CabBottomNavigation.safeTabIndex(0, 3), 0);
      expect(CabBottomNavigation.safeTabIndex(2, 3), 2);
    });

    test('the index left behind by a removed My Trips tab falls back to the first tab', () {
      // Two services plus My Trips = 3 tabs; the driver was on tab 2. The grant
      // lapses, the tab count drops to 2, and IndexedStack would otherwise be
      // handed an out-of-range index.
      expect(CabBottomNavigation.safeTabIndex(2, 2), 0);
    });

    test('a negative or wildly out-of-range index cannot escape', () {
      expect(CabBottomNavigation.safeTabIndex(-1, 3), 0);
      expect(CabBottomNavigation.safeTabIndex(99, 3), 0);
      expect(CabBottomNavigation.safeTabIndex(0, 0), 0);
    });
  });

  group('the bar and the rest of the feature answer the same question', () {
    test('the bar uses the Session 3 gate, so it cannot disagree with the drawer or the write path', () {
      for (final MyTripsAccess access in <MyTripsAccess>[MyTripsAccess.none, grantOf(days: 1), grantOf(days: 30, revokedAt: now), grantOf(days: 30, granted: false)]) {
        // The My Trips *tab* is the thing the gate governs. The bar itself is
        // not, and must not be - Home and Orders belong to every driver.
        expect(CabBottomNavigation.hasMyTrips(access, now), MyTripsGate.showsInNavigation(access, now));
        expect(labelsOf(CabBottomNavigation.destinationsFor(access, now)).contains('My Trips'), MyTripsGate.canOpenMyTrips(access, now));
        expect(CabBottomNavigation.isVisible(access, now), isTrue);
        // Bid is not what the gate governs. Every driver has it, granted or not.
        expect(labelsOf(CabBottomNavigation.destinationsFor(access, now)), contains('Bid'));
      }
    });
  });

  group('the Bid tab', () {
    test('every driver has it, granted or not, expired or revoked', () {
      for (final MyTripsAccess access in <MyTripsAccess>[
        MyTripsAccess.none,
        grantOf(days: 7),
        grantOf(days: 1, grantedAt: now.subtract(const Duration(days: 5))),
        grantOf(days: 30, revokedAt: now),
        grantOf(days: 30, granted: false),
      ]) {
        expect(labelsOf(CabBottomNavigation.destinationsFor(access, now)), contains('Bid'));
      }
    });

    test('it renders drawer slot 12 - appended, so nothing else moved', () {
      // 0-9 were taken, 10 is the drawer's Change Password fall-through and 11
      // is My Trips. Inserting Bid anywhere lower would have repointed the
      // drawer, DriverMenuVisibility and every stored index at another screen.
      expect(CabBottomNavigation.bidDrawerIndex, 12);
      expect(CabBottomNavigation.bid.drawerIndex, CabBottomNavigation.bidDrawerIndex);
      expect(CabBottomNavigation.homeDrawerIndex, 0);
      expect(CabBottomNavigation.ordersDrawerIndex, 1);
      expect(CabBottomNavigation.myTripsDrawerIndex, 11);
    });

    test('its position is the same whether or not My Trips is there', () {
      // The whole point of keying the bar by drawer slot: a driver who is
      // granted My Trips mid-session must not find Bid where Orders used to be.
      final List<CabNavDestination> granted = CabBottomNavigation.destinationsFor(grantOf(days: 7), now);
      final List<CabNavDestination> ungranted = CabBottomNavigation.destinationsFor(MyTripsAccess.none, now);
      expect(granted.indexOf(CabBottomNavigation.bid), 2);
      expect(ungranted.indexOf(CabBottomNavigation.bid), 2);
      expect(CabBottomNavigation.drawerIndexFor(granted, 2), CabBottomNavigation.bidDrawerIndex);
      expect(CabBottomNavigation.drawerIndexFor(ungranted, 2), CabBottomNavigation.bidDrawerIndex);
    });

    test('a driver sitting on Bid is never bounced off it', () {
      // safeDrawerIndexFor exists for the My Trips grant lapsing. Bid has no
      // grant, so it must be left alone in every access state.
      for (final MyTripsAccess access in <MyTripsAccess>[MyTripsAccess.none, grantOf(days: 7), grantOf(days: 30, revokedAt: now)]) {
        expect(
          CabBottomNavigation.safeDrawerIndexFor(access: access, now: now, drawerIndex: CabBottomNavigation.bidDrawerIndex),
          CabBottomNavigation.bidDrawerIndex,
        );
      }
    });

    test('the four-tab bar round-trips every slot it carries', () {
      final List<CabNavDestination> destinations = CabBottomNavigation.destinationsFor(grantOf(days: 7), now);
      expect(destinations.length, 4);
      for (int position = 0; position < destinations.length; position++) {
        final int slot = CabBottomNavigation.drawerIndexFor(destinations, position);
        expect(CabBottomNavigation.currentIndexFor(destinations, slot), position, reason: 'position $position');
      }
    });

    test('a stored four-tab index cannot escape a three-tab bar', () {
      // The multi-service bar stores its selected tab. A driver on My Trips
      // (position 3) whose grant lapses drops to a three-tab bar.
      expect(CabBottomNavigation.safeTabIndex(3, 4), 3);
      expect(CabBottomNavigation.safeTabIndex(3, 3), 0);
    });
  });
}
