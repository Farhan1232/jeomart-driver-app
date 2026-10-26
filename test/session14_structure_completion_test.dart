import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/utils/cab_bottom_navigation.dart';
import 'package:driver/utils/cab_nav_badges.dart';
import 'package:driver/utils/driver_trip_settings.dart';
import 'package:driver/utils/driver_trip_state.dart';
import 'package:driver/utils/my_trips_access.dart';

/// Session 14 — the driver side of four structural changes.
///
/// 2. A booked trip can finish: `DriverTripStatus.completed` exists, counts as
///    finished, and has a tab of its own in My Trips.
/// 3. The My Trips access gate is switchable rather than removed. A driver may
///    post trips when they hold a valid grant **or** when the admin has turned
///    on the global switch.
///
/// Plus the bar's icons and badges.
void main() {
  final DateTime now = DateTime(2026, 9, 8, 12);

  String source(String path) {
    final File file = File(path);
    if (!file.existsSync()) throw StateError('$path is missing');
    return file.readAsStringSync();
  }

  MyTripsAccess grantOf({
    required int days,
    bool granted = true,
    DateTime? grantedAt,
    DateTime? revokedAt,
  }) {
    final DateTime start = grantedAt ?? now;
    return MyTripsAccess(
      granted: granted,
      durationDays: days,
      grantedAt: Timestamp.fromDate(start),
      expiresAt: Timestamp.fromDate(start.add(Duration(days: days))),
      revokedAt: revokedAt == null ? null : Timestamp.fromDate(revokedAt),
      grantedBy: 'admin1',
    );
  }

  // =========================================================================
  // ITEM 2 — a booked trip can finish
  // =========================================================================
  group('Item 2: a trip that has run is completed, not booked for ever', () {
    test('completed exists, is in `all`, and is finished', () {
      expect(DriverTripStatus.completed, 'completed');
      expect(DriverTripStatus.all, <String>['active', 'booked', 'completed', 'expired', 'cancelled']);
      expect(DriverTripStatus.isFinished(DriverTripStatus.completed), isTrue);
    });

    test('the other states keep exactly the meaning they had', () {
      expect(DriverTripStatus.isFinished(DriverTripStatus.expired), isTrue);
      expect(DriverTripStatus.isFinished(DriverTripStatus.cancelled), isTrue);
      expect(DriverTripStatus.isFinished(DriverTripStatus.active), isFalse);
      expect(DriverTripStatus.isFinished(DriverTripStatus.booked), isFalse);
      expect(DriverTripStatus.acceptsReservation(DriverTripStatus.completed), isFalse);
      expect(DriverTripStatus.acceptsReservation(DriverTripStatus.active), isTrue);
    });

    test('a completed trip has a tab to land in — it cannot vanish from My Trips', () {
      // `MyTripsController.tripsForTab` matches `effectiveStatusAt(now) == tab`.
      // A status with no tab is simply never drawn, so the tab list has to be
      // the status list and not a copy of it.
      final String controller = source('lib/controllers/my_trips_controller.dart');
      expect(controller.contains('tabKeys = DriverTripStatus.all'), isTrue,
          reason: 'the tabs must be driven off DriverTripStatus.all');

      final String screen = source('lib/app/cab_screen/my_trips_screen.dart');
      expect(screen.contains('case DriverTripStatus.completed:'), isTrue);
      expect(screen.contains("return 'Completed'.tr;"), isTrue);
    });

    test('the Call and Chat buttons close on a completed trip, by the existing rule', () {
      // The card hides them when `DriverTripStatus.isFinished(...)` is true.
      // Because `completed` joined that set, no second rule was written - which
      // is what keeps cancelled, expired and completed behaving identically.
      final String screen = source('lib/app/cab_screen/my_trips_screen.dart');
      expect(screen.contains('final bool ended = DriverTripStatus.isFinished('), isTrue);
      expect(screen.contains('if (!ended) ...<Widget>['), isTrue);
      expect(DriverTripStatus.isFinished(DriverTripStatus.completed), isTrue);
    });

    test('the passenger block itself stays, as history', () {
      // `_passengerBlock` is drawn whenever the trip has a reservation; only
      // the two buttons are behind `ended`. A completed trip therefore still
      // shows who took it.
      final String screen = source('lib/app/cab_screen/my_trips_screen.dart');
      expect(screen.contains('if (trip.hasReservation) _passengerBlock('), isTrue);
    });

    test('a completed trip can no longer be cancelled', () {
      final String screen = source('lib/app/cab_screen/my_trips_screen.dart');
      expect(
        screen.contains('final bool canCancel = status == DriverTripStatus.active || status == DriverTripStatus.booked;'),
        isTrue,
      );
    });

    test('the driver writes the status too now, and only from the ledger', () {
      // Session 14 made completion server-only and this test pinned that: no
      // file but the state definition and the tab list could even name the
      // status. The client has since asked for a Complete Ride button - "it
      // must be saved correctly in the database and appear in completed ride
      // history for both Driver and Customer apps" - so the driver app is now a
      // writer as well.
      //
      // The rule that replaces "nobody writes it" is "one place writes it":
      // `DriverTripLedger.completeTrip`, inside a transaction, exactly as
      // cancellation is. A status assigned anywhere else would be a second
      // opinion about whether a trip ran.
      const List<String> mayAssign = <String>['lib/utils/driver_trip_ledger.dart'];

      for (final FileSystemEntity entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final String text = entity.readAsStringSync();
        final bool assigns = text.contains('DriverTripFields.status: DriverTripStatus.completed');
        if (assigns) {
          expect(mayAssign, contains(entity.path),
              reason: '${entity.path} assigns the completed status; only the ledger may');
        }
      }

      // The one writer really is there, and it is transactional.
      final String ledger = source('lib/utils/driver_trip_ledger.dart');
      expect(ledger, contains('DriverTripFields.status: DriverTripStatus.completed'));
      expect(ledger, contains('return runner.run<CompleteTripResult>((TripTransactionContext ctx) async {'));

      // The screen still only ever compares, never assigns - it asks the
      // controller, which asks the service, which asks the ledger.
      final String screen = source('lib/app/cab_screen/my_trips_screen.dart');
      expect(screen.contains('status: DriverTripStatus.completed'), isFalse);
      expect(screen.contains('DriverTripStatus.completed,'), isFalse);
    });

    test('the server sweep is still the backstop, and cannot collide', () {
      // The sweep reads `where status == 'booked'` and nothing else, so a trip
      // the driver has already completed is invisible to it. Whichever writer
      // gets there first decides; the ledger refuses a trip that is already
      // finished, so the reverse order is safe too.
      final String ledger = source('lib/utils/driver_trip_ledger.dart');
      final int finished = ledger.indexOf('if (DriverTripStatus.isFinished(trip.status)) return CompleteTripResult.alreadyFinished;');
      final int write = ledger.indexOf('DriverTripFields.status: DriverTripStatus.completed');
      expect(finished, greaterThan(-1), reason: 'an already-finished trip must be refused');
      expect(finished, lessThan(write), reason: 'and refused before anything is written');

      expect(DriverTripStatus.acceptsCompletion(DriverTripStatus.booked), isTrue,
          reason: 'the same state the sweep completes from');
    });
  });

  // =========================================================================
  // ITEM 3 — the gate is switchable, not removed
  // =========================================================================
  group('Item 3: the My Trips gate, all four combinations', () {
    test('grant valid, switch OFF -> allowed (unchanged behaviour)', () {
      expect(MyTripsGate.showsInNavigation(grantOf(days: 7), now, openToAllDrivers: false), isTrue);
      expect(MyTripsGate.canOpenMyTrips(grantOf(days: 7), now, openToAllDrivers: false), isTrue);
    });

    test('no grant, switch OFF -> refused (unchanged behaviour)', () {
      expect(MyTripsGate.showsInNavigation(MyTripsAccess.none, now, openToAllDrivers: false), isFalse);
      expect(MyTripsGate.canOpenMyTrips(MyTripsAccess.none, now, openToAllDrivers: false), isFalse);
    });

    test('grant valid, switch ON -> allowed', () {
      expect(MyTripsGate.showsInNavigation(grantOf(days: 7), now, openToAllDrivers: true), isTrue);
      expect(MyTripsGate.canOpenMyTrips(grantOf(days: 7), now, openToAllDrivers: true), isTrue);
    });

    test('no grant, switch ON -> allowed', () {
      expect(MyTripsGate.showsInNavigation(MyTripsAccess.none, now, openToAllDrivers: true), isTrue);
      expect(MyTripsGate.canOpenMyTrips(MyTripsAccess.none, now, openToAllDrivers: true), isTrue);
    });

    test('a grant that EXPIRED while the switch is on -> still allowed', () {
      // The switch is the broader permission. A per-driver grant running out
      // was never meant to be a ban, so it must not override the global "every
      // driver may post" the admin has just turned on.
      final MyTripsAccess lapsed = grantOf(days: 1, grantedAt: now.subtract(const Duration(days: 5)));
      expect(lapsed.isValidAt(now), isFalse, reason: 'fixture must actually be expired');
      expect(MyTripsGate.showsInNavigation(lapsed, now, openToAllDrivers: false), isFalse);
      expect(MyTripsGate.showsInNavigation(lapsed, now, openToAllDrivers: true), isTrue);
    });

    test('a grant that was REVOKED while the switch is on -> still allowed', () {
      final MyTripsAccess revoked = grantOf(days: 30, revokedAt: now.subtract(const Duration(hours: 1)));
      expect(revoked.isValidAt(now), isFalse, reason: 'fixture must actually be revoked');
      expect(MyTripsGate.showsInNavigation(revoked, now, openToAllDrivers: false), isFalse);
      expect(MyTripsGate.showsInNavigation(revoked, now, openToAllDrivers: true), isTrue);
    });

    test('the publish path answers the same way, and still needs a valid trip', () {
      expect(
        MyTripsGate.canPublishTrip(
          access: MyTripsAccess.none,
          now: now,
          validationErrors: const <Object>[],
          openToAllDrivers: true,
        ),
        isTrue,
      );
      // The switch grants permission, never a pass on validation.
      expect(
        MyTripsGate.canPublishTrip(
          access: grantOf(days: 7),
          now: now,
          validationErrors: const <Object>['dateInPast'],
          openToAllDrivers: true,
        ),
        isFalse,
      );
      expect(
        MyTripsGate.canPublishTrip(
          access: MyTripsAccess.none,
          now: now,
          validationErrors: const <Object>[],
          openToAllDrivers: false,
        ),
        isFalse,
      );
    });

    test('every entry point defaults to closed', () {
      // A caller that has not read the settings yet, or cannot, gets the
      // grant-only behaviour. This is the property that makes a settings
      // outage safe.
      expect(MyTripsGate.showsInNavigation(MyTripsAccess.none, now), isFalse);
      expect(MyTripsGate.canOpenMyTrips(MyTripsAccess.none, now), isFalse);
      expect(
        MyTripsGate.canPublishTrip(access: MyTripsAccess.none, now: now, validationErrors: const <Object>[]),
        isFalse,
      );
      expect(CabBottomNavigation.hasMyTrips(MyTripsAccess.none, now), isFalse);
    });
  });

  group('Item 3: the settings field behind the switch', () {
    test('it defaults to off, and so does an absent or empty document', () {
      expect(DriverTripSettings.defaultOpenToAllDrivers, isFalse);
      expect(DriverTripSettings.defaults.openToAllDrivers, isFalse);
      expect(DriverTripSettings.fromJson(null).openToAllDrivers, isFalse);
      expect(DriverTripSettings.fromJson(<String, dynamic>{}).openToAllDrivers, isFalse);
    });

    test('only a deliberate true opens it', () {
      expect(DriverTripSettings.fromJson(<String, dynamic>{'tripOpenToAllDrivers': true}).openToAllDrivers, isTrue);
      expect(DriverTripSettings.fromJson(<String, dynamic>{'tripOpenToAllDrivers': 'true'}).openToAllDrivers, isTrue);
      expect(DriverTripSettings.fromJson(<String, dynamic>{'tripOpenToAllDrivers': 1}).openToAllDrivers, isTrue);
    });

    test('anything unreadable leaves it shut rather than widening access', () {
      for (final Object? raw in <Object?>[null, false, 'false', '', '  ', 'yes', 0, 2, <String>[], <String, dynamic>{}]) {
        expect(
          DriverTripSettings.fromJson(<String, dynamic>{'tripOpenToAllDrivers': raw}).openToAllDrivers,
          isFalse,
          reason: '$raw must not open the feature',
        );
      }
    });

    test('the other two settings are untouched by it', () {
      final DriverTripSettings s = DriverTripSettings.fromJson(<String, dynamic>{
        'tripVisibilityHours': 6,
        'tripRadiusKm': 25,
        'tripOpenToAllDrivers': true,
      });
      expect(s.visibilityHours, 6);
      expect(s.radiusKm, 25);
      expect(s.openToAllDrivers, isTrue);
      expect(s.toJson()['tripOpenToAllDrivers'], isTrue);
    });

    test('the switch survives a document that has only it', () {
      final DriverTripSettings s = DriverTripSettings.fromJson(<String, dynamic>{'tripOpenToAllDrivers': true});
      expect(s.openToAllDrivers, isTrue);
      expect(s.visibilityHours, DriverTripSettings.defaultVisibilityHours);
      expect(s.radiusKm, DriverTripSettings.defaultRadiusKm);
    });
  });

  group('Item 3: the bar reflects the switch, and Bid is untouched by it', () {
    List<String> labelsOf(List<CabNavDestination> destinations) =>
        destinations.map((CabNavDestination d) => d.labelKey).toList();

    test('a grantless driver gets the My Trips tab once the switch is on', () {
      expect(labelsOf(CabBottomNavigation.destinationsFor(MyTripsAccess.none, now)),
          <String>['Home', 'Orders', 'Bid']);
      expect(labelsOf(CabBottomNavigation.destinationsFor(MyTripsAccess.none, now, openToAllDrivers: true)),
          <String>['Home', 'Orders', 'Bid', 'My Trips']);
    });

    test('Bid stays unconditional in every combination', () {
      for (final MyTripsAccess access in <MyTripsAccess>[
        MyTripsAccess.none,
        grantOf(days: 7),
        grantOf(days: 1, grantedAt: now.subtract(const Duration(days: 5))),
        grantOf(days: 30, revokedAt: now),
      ]) {
        for (final bool open in <bool>[false, true]) {
          final List<CabNavDestination> bar =
              CabBottomNavigation.destinationsFor(access, now, openToAllDrivers: open);
          expect(labelsOf(bar), contains('Bid'));
          expect(bar.first.drawerIndex, CabBottomNavigation.homeDrawerIndex);
          // Bid keeps its slot, so no stored index is repointed.
          expect(bar[2].drawerIndex, CabBottomNavigation.bidDrawerIndex);
        }
      }
    });

    test('My Trips is appended last, so no other tab moves when it appears', () {
      final List<CabNavDestination> withTab =
          CabBottomNavigation.destinationsFor(MyTripsAccess.none, now, openToAllDrivers: true);
      expect(withTab.last.drawerIndex, CabBottomNavigation.myTripsDrawerIndex);
      expect(withTab.length, 4);
    });

    test('the drawer fallback follows the switch too', () {
      expect(
        CabBottomNavigation.safeDrawerIndexFor(
          access: MyTripsAccess.none,
          now: now,
          drawerIndex: CabBottomNavigation.myTripsDrawerIndex,
        ),
        CabBottomNavigation.homeDrawerIndex,
      );
      expect(
        CabBottomNavigation.safeDrawerIndexFor(
          access: MyTripsAccess.none,
          now: now,
          drawerIndex: CabBottomNavigation.myTripsDrawerIndex,
          openToAllDrivers: true,
        ),
        CabBottomNavigation.myTripsDrawerIndex,
      );
    });

    test('the app reads the switch from the settings the panel writes', () {
      expect(source('lib/constant/constant.dart')
          .contains('openToAllDrivers: driverTripSettings.openToAllDrivers'), isTrue);
      expect(source('lib/services/driver_trip_service.dart')
          .contains('openToAllDrivers: Constant.driverTripSettings.openToAllDrivers'), isTrue);
      expect(source('lib/app/cab_screen/cab_dashboard_screen.dart')
          .contains('openToAllDrivers: Constant.driverTripSettings.openToAllDrivers'), isTrue);
    });
  });

  // =========================================================================
  // The bar's icons and badges
  // =========================================================================
  group('the cab bar badges', () {
    bool seenNothing(int _) => false;
    bool seenEverything(int _) => true;

    test('Orders carries the live ongoing count', () {
      final CabNavBadge badge = CabNavBadges.badgeFor(
        drawerIndex: CabBottomNavigation.ordersDrawerIndex,
        ongoingRides: 3,
        hasSeenSection: seenEverything,
      );
      expect(badge.hasCount, isTrue);
      expect(badge.count, 3);
      expect(badge.label, '3');
      expect(badge.isNew, isFalse);
    });

    test('zero draws nothing — a badge reading 0 is noise', () {
      final CabNavBadge badge = CabNavBadges.badgeFor(
        drawerIndex: CabBottomNavigation.ordersDrawerIndex,
        ongoingRides: 0,
        hasSeenSection: seenEverything,
      );
      expect(badge.hasCount, isFalse);
      expect(badge.isEmpty, isTrue);
    });

    test('a negative count cannot reach the badge', () {
      expect(
        CabNavBadges.badgeFor(
          drawerIndex: CabBottomNavigation.ordersDrawerIndex,
          ongoingRides: -4,
          hasSeenSection: seenEverything,
        ).count,
        0,
      );
    });

    test('the count is capped, so it cannot sit on top of the next tab', () {
      expect(
        CabNavBadges.badgeFor(
          drawerIndex: CabBottomNavigation.ordersDrawerIndex,
          ongoingRides: 250,
          hasSeenSection: seenEverything,
        ).label,
        '99+',
      );
    });

    test('Bid and My Trips carry NEW until the driver opens them', () {
      for (final int slot in CabNavBadges.ribbonSections) {
        expect(
          CabNavBadges.badgeFor(drawerIndex: slot, ongoingRides: 0, hasSeenSection: seenNothing).isNew,
          isTrue,
          reason: 'slot $slot should start marked new',
        );
        expect(
          CabNavBadges.badgeFor(drawerIndex: slot, ongoingRides: 0, hasSeenSection: seenEverything).isNew,
          isFalse,
          reason: 'slot $slot should clear once opened',
        );
      }
      expect(CabNavBadges.ribbonSections, <int>{
        CabBottomNavigation.bidDrawerIndex,
        CabBottomNavigation.myTripsDrawerIndex,
      });
    });

    test('Home and Orders are never marked NEW — they have always been there', () {
      for (final int slot in <int>[CabBottomNavigation.homeDrawerIndex, CabBottomNavigation.ordersDrawerIndex]) {
        expect(
          CabNavBadges.badgeFor(drawerIndex: slot, ongoingRides: 0, hasSeenSection: seenNothing).isNew,
          isFalse,
        );
        expect(CabNavBadges.marksSeen(slot), isFalse, reason: 'slot $slot should not be written to preferences');
      }
    });

    test('a tab can carry both marks at once', () {
      // Not reachable today - Orders is not ribboned - but the rule has to
      // compose, because which sections are ribboned is a one-line change.
      const CabNavBadge both = CabNavBadge(count: 2, isNew: true);
      expect(both.hasCount, isTrue);
      expect(both.isNew, isTrue);
      expect(both.isEmpty, isFalse);
    });

    test('Home carries nothing', () {
      expect(
        CabNavBadges.badgeFor(
          drawerIndex: CabBottomNavigation.homeDrawerIndex,
          ongoingRides: 9,
          hasSeenSection: seenNothing,
        ),
        CabNavBadge.none,
      );
    });

    test('the seen key is stable per slot, so a ribbon does not come back', () {
      expect(CabNavBadges.seenKeyFor(CabBottomNavigation.bidDrawerIndex), 'cabSectionSeen_12');
      expect(CabNavBadges.seenKeyFor(CabBottomNavigation.myTripsDrawerIndex), 'cabSectionSeen_11');
      expect(
        CabNavBadges.seenKeyFor(CabBottomNavigation.bidDrawerIndex),
        isNot(CabNavBadges.seenKeyFor(CabBottomNavigation.myTripsDrawerIndex)),
      );
    });

    test('the bar draws them with the badges package and Font Awesome glyphs', () {
      final String screen = source('lib/app/cab_screen/cab_dashboard_screen.dart');
      expect(screen.contains("import 'package:badges/badges.dart' as badges;"), isTrue);
      expect(screen.contains("import 'package:font_awesome_flutter/font_awesome_flutter.dart';"), isTrue);
      expect(screen.contains('badges.BadgeShape.circle'), isTrue);
      expect(screen.contains('FontAwesomeIcons.clipboardList'), isTrue);
      expect(screen.contains('FontAwesomeIcons.gavel'), isTrue);
      expect(screen.contains('FontAwesomeIcons.route'), isTrue);
      expect(screen.contains('FontAwesomeIcons.house'), isTrue);
      // and the hand-rolled Stack it replaced is gone
      expect(screen.contains('_withOngoingBadge'), isFalse);
    });

    test('opening a ribboned section is what clears it', () {
      final String controller = source('lib/controllers/cab_dashboard_controller.dart');
      expect(controller.contains('ever<int>(drawerIndex, markSectionSeen)'), isTrue,
          reason: 'every route into a section is a write to drawerIndex; that is the one hook');
      expect(controller.contains('Preferences.setBoolean(CabNavBadges.seenKeyFor(index), true)'), isTrue);
    });
  });
}
