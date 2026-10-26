import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The driver's Bid section.
///
/// The client asked for it twice — "make another section for bid same like my
/// trips for drivers... in bottombar" — and until now bidding existed on the
/// driver side only as a card under the map on the cab home screen, visible to
/// an idle driver who happened to be looking at that one screen.
///
/// These are source tests, the same shape as the customer app's
/// `customer_bid_section_test.dart`. The screen needs GetX, a ThemeController,
/// Firebase Auth (through `Constant.isBiddingEnabled`) and a live Firestore
/// listener, so pumping it would test the mocks rather than the wiring. What is
/// pinned here is what a widget test could not reach anyway: that the section
/// exists, that navigation reaches it, that no existing drawer slot was
/// renumbered to make room, and that the card is shared rather than copied.
void main() {
  final String navigation = File('lib/utils/cab_bottom_navigation.dart').readAsStringSync();
  final String dashboard = File('lib/app/cab_screen/cab_dashboard_screen.dart').readAsStringSync();
  final String screen = File('lib/app/cab_screen/bidding_screen.dart').readAsStringSync();
  final String inbox = File('lib/app/cab_screen/bidding_requests_view.dart').readAsStringSync();
  final String card = File('lib/app/cab_screen/bidding_request_card.dart').readAsStringSync();

  group('the section exists and is reachable', () {
    test('the screen and the shared card are both real files', () {
      expect(File('lib/app/cab_screen/bidding_screen.dart').existsSync(), isTrue);
      expect(File('lib/app/cab_screen/bidding_request_card.dart').existsSync(), isTrue);
      expect(screen.contains('class BiddingScreen extends StatelessWidget'), isTrue);
      expect(card.contains('class BiddingRequestCard extends StatelessWidget'), isTrue);
    });

    test('the dashboard body renders it for the Bid slot', () {
      // Session 20 turned the body's chain of `?:` into two switches - the
      // sections the dashboard keeps alive, and the drawer pages it still
      // builds on demand - so that leaving a section stops throwing it away.
      // The Bid slot must still resolve to the Bid screen.
      final String kept = _methodBody(dashboard, 'Widget _sectionFor(int drawerIndex) {');
      expect(
        kept.contains('case CabBottomNavigation.bidDrawerIndex:'),
        isTrue,
        reason: 'the body must have a branch for the Bid slot',
      );
      expect(dashboard.contains('const BiddingScreen()'), isTrue);
      expect(dashboard.contains("import 'package:driver/app/cab_screen/bidding_screen.dart';"), isTrue);
    });

    test('the drawer has an entry that sends the driver there', () {
      expect(dashboard.contains("Text('Bid'.tr"), isTrue, reason: 'no Bid entry in the drawer');
      expect(
        dashboard.contains('controller.drawerIndex.value = CabBottomNavigation.bidDrawerIndex;'),
        isTrue,
        reason: 'the drawer entry must write the same slot constant the bar and the body use',
      );
    });

    test('the bar has an icon of its own for it', () {
      // Session 12 pinned this to Material's `Icons.sell` / `Icons.sell_outlined`.
      // Session 14 moved the bar to Font Awesome, because at 21 px Material's
      // outlined Bid and My Trips glyphs read as the same thin shape. What the
      // test is actually for is unchanged: the Bid slot must have a branch in
      // the bar's icon switch, and a glyph that is nothing else's.
      expect(dashboard.contains('case CabBottomNavigation.bidDrawerIndex:'), isTrue);
      expect(dashboard.contains('FontAwesomeIcons.gavel'), isTrue);
      // The drawer entry keeps the Material icon it has always had.
      expect(dashboard.contains('Icons.sell_outlined'), isTrue);
      // No two tabs share a glyph.
      final List<String> glyphs = <String>[
        'FontAwesomeIcons.house',
        'FontAwesomeIcons.clipboardList',
        'FontAwesomeIcons.gavel',
        'FontAwesomeIcons.route',
      ];
      for (final String glyph in glyphs) {
        expect(dashboard.contains(glyph), isTrue, reason: '$glyph is missing from the bar');
        expect(
          RegExp(RegExp.escape(glyph) + r'\b').allMatches(dashboard).length,
          1,
          reason: '$glyph is used more than once, so two tabs look alike',
        );
      }
    });
  });

  group('no existing drawer slot was renumbered', () {
    // Renumbering is the failure this whole feature could have caused: the
    // drawer, the bar, DriverMenuVisibility and the body switch all address
    // screens by the same integer, and there is no type to catch a shift.
    test('Bid took the first free slot, 12', () {
      expect(navigation.contains('static const int bidDrawerIndex = 12;'), isTrue);
    });

    test('every slot that existed before still renders the screen it did', () {
      // Same guarantee as before session 20 rebuilt the body, read off the two
      // switches that replaced the chain of `?:`.
      final String kept = _methodBody(dashboard, 'Widget _sectionFor(int drawerIndex) {');
      final String pages = _methodBody(dashboard, 'Widget _drawerPageFor(int drawerIndex) {');

      const Map<String, String> keptSlots = <String, String>{
        'CabBottomNavigation.ordersDrawerIndex': 'CabOrderListScreen()',
        'CabBottomNavigation.bidDrawerIndex': 'BiddingScreen()',
        'CabBottomNavigation.myTripsDrawerIndex': 'MyTripsScreen()',
      };
      keptSlots.forEach((String label, String widget) {
        _expectCaseRenders(kept, 'case $label:', widget, label);
      });

      // Slot 0 is the fall-through: home is what the dashboard shows when the
      // section is none of the others.
      final int fallThrough = kept.indexOf('default:');
      expect(fallThrough, greaterThan(-1), reason: 'the kept sections lost their default');
      expect(kept.indexOf('CabHomeScreen()'), greaterThan(fallThrough), reason: 'slot 0 no longer renders CabHomeScreen');

      const Map<int, String> drawerSlots = <int, String>{
        2: 'WalletScreen(isAppBarShow: false)',
        3: 'WithdrawMethodSetupScreen()',
        4: 'VerificationScreen()',
        5: 'DriverInboxScreen()',
        7: 'ChangeLanguageScreen()',
      };
      drawerSlots.forEach((int slot, String widget) {
        _expectCaseRenders(pages, 'case $slot:', widget, 'slot $slot');
      });
    });

    test('the drawer still writes the slots it always wrote', () {
      for (final int slot in <int>[0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11]) {
        expect(dashboard.contains('controller.drawerIndex.value = $slot;'), isTrue, reason: 'drawer no longer reaches slot $slot');
      }
    });
  });

  group('the card is shared, not copied', () {
    test('both the home inbox and the Bid screen render BiddingRequestCard', () {
      expect(inbox.contains('BiddingRequestCard('), isTrue);
      expect(screen.contains('BiddingRequestCard('), isTrue);
    });

    test('neither of them still holds a card of its own', () {
      // The accept / counter-offer / withdraw rules must exist once. A second
      // copy is two sets of money rules to keep in step.
      for (final String source in <String>[inbox, screen]) {
        expect(source.contains('Widget _requestCard('), isFalse);
        expect(source.contains('_openCounterOfferSheet'), isFalse);
        expect(source.contains('acceptOfferedFare'), isFalse);
      }
      expect(card.contains('acceptOfferedFare'), isTrue);
      expect(card.contains('sendCounterOffer'), isTrue);
      expect(card.contains('controller.withdraw('), isTrue);
    });

    test('the behaviour the client signed off on survived the move', () {
      expect(card.contains('BiddingRequestController.quickRaises'), isTrue, reason: 'the +20/+50/+100/+200 chips');
      expect(card.contains('controller.raiseCounterOffer(step)'), isTrue, reason: 'raises must stay additive');
      expect(card.contains('controller.inFlight.contains(request.id)'), isTrue, reason: 'the duplicate-tap guard');
      expect(card.contains('walletBlocker(driver: driver, owner: owner)'), isTrue);
      expect(card.contains("request.distanceKm.toStringAsFixed(2)} \${'KM'.tr}"), isTrue,
          reason: 'true kilometres, not the display unit, which reads Miles on some installs');
      expect(card.contains('controller.minimumFareFor(request)'), isTrue, reason: 'the minimum-fare line');
    });
  });

  group('the release-blank-screen bug cannot come back', () {
    // A GetX builder that subscribes to no observable throws mid-build, and a
    // release build draws that as an empty body or an error box. It bit the
    // customer app twice: the signed-out Bid screen, then the bidding pay
    // button. It is not enough for the body to read an observable somewhere -
    // the branch actually taken has to.
    test('the builder reads an observable before it branches', () {
      final int builder = screen.indexOf('builder: (BiddingRequestController controller) {');
      expect(builder, greaterThan(-1));

      final int loading = screen.indexOf('controller.isLoading.value', builder);
      final int busy = screen.indexOf('controller.isBusyOnRide.value', builder);
      final int firstBranch = screen.indexOf('if (', builder);

      expect(loading, greaterThan(-1), reason: 'the builder never reads isLoading');
      expect(busy, greaterThan(-1), reason: 'the builder never reads isBusyOnRide');
      expect(loading, lessThan(firstBranch == -1 ? screen.length : firstBranch),
          reason: 'the observable read must come before the first branch, not inside one');
      expect(busy, lessThan(firstBranch == -1 ? screen.length : firstBranch));
    });

    test('the states with nothing to list still read an observable', () {
      // Both are passed in as plain bools computed above the branch, which is
      // what makes the subscription unconditional.
      expect(screen.contains('required bool loading'), isTrue);
      expect(screen.contains('required bool busy'), isTrue);
    });

    test('every empty state says something instead of drawing nothing', () {
      for (final String title in <String>[
        'Bidding is currently unavailable',
        'You are on a ride',
        'No ride offers right now',
      ]) {
        expect(screen.contains(title), isTrue, reason: 'missing state: $title');
      }
      expect(screen.contains('SizedBox.shrink()'), isFalse, reason: 'a blank body is indistinguishable from a crash');
    });

    test('the switched-off state is decided before start() is called', () {
      // `start()` clears observables when bidding is off, and clearing one from
      // inside a builder marks an already-built subtree dirty.
      final int check = screen.indexOf('if (!Constant.isBiddingEnabled)');
      final int start = screen.indexOf('controller.start();');
      expect(check, greaterThan(-1));
      expect(start, greaterThan(-1));
      expect(check, lessThan(start));
    });
  });

  group('the tab is not behind the My Trips grant', () {
    test('Bid is in the bar on both branches of destinationsFor', () {
      expect(navigation.contains('<CabNavDestination>[home, orders, bid]'), isTrue);
      expect(navigation.contains('<CabNavDestination>[home, orders, bid, myTrips]'), isTrue);
    });

    test('the drawer entry carries no access condition', () {
      final int entry = dashboard.indexOf("Text('Bid'.tr");
      expect(entry, greaterThan(-1));
      // The My Trips entry two blocks down is prefixed with an `if`. This one
      // must not be: bidding is one global admin switch, not a per-driver grant,
      // and the screen explains itself when that switch is off.
      final int listTile = dashboard.lastIndexOf('ListTile(', entry);
      final String preamble = dashboard.substring(listTile - 400, listTile);
      expect(preamble.contains('MyTripsGate.showsInNavigation'), isFalse);
      expect(preamble.trimRight().endsWith('if'), isFalse);
    });
  });

  group('translations', () {
    test('every new string is in all nine language files', () {
      const List<String> keys = <String>[
        'Bid',
        'Ride Offers',
        'Bidding is currently unavailable',
        'Ride offers are switched off for now. Your ordinary ride requests are not affected.',
        'You are on a ride',
        'New ride offers will appear here once your current ride is finished.',
        'No ride offers right now',
        'When a customer names their own fare for a trip near you, it will show up here.',
      ];
      for (final String code in <String>['en', 'ar', 'de', 'fr', 'hi', 'ja', 'pt', 'ru', 'zh']) {
        final String lang = File('lib/lang/app_$code.dart').readAsStringSync();
        for (final String key in keys) {
          expect(lang.contains("'$key':"), isTrue, reason: '$code is missing "$key"');
        }
      }
    });
  });

  group('the owner a fleet driver is billed against', () {
    final String controller = File('lib/controllers/bidding_request_controller.dart').readAsStringSync();

    test('the controller follows the owner, because CabHomeController is not mounted here', () {
      // walletBlocker() compares the OWNER's balance for a driver who has one.
      // A default UserModel would carry a null wallet and refuse every offer.
      expect(controller.contains('final Rx<UserModel> owner'), isTrue);
      expect(screen.contains('controller.owner.value'), isTrue);
    });

    test('it opens nothing for a driver with no owner', () {
      expect(controller.contains("if (ownerId == null || ownerId.isEmpty) return;"), isTrue);
    });

    test('it is cancelled with everything else the controller opens', () {
      final int stopAll = controller.indexOf('void _stopAll() {');
      expect(stopAll, greaterThan(-1));
      final String body = controller.substring(stopAll, stopAll + 400);
      expect(body.contains('_ownerSub?.cancel();'), isTrue);
      expect(body.contains('_ownerSub = null;'), isTrue);
    });
  });
}

/// The source of one method, from its signature to the line that closes it.
String _methodBody(String source, String signature) {
  final int start = source.indexOf(signature);
  expect(start, greaterThan(-1), reason: '$signature is gone');
  final int end = source.indexOf('\n  }', start);
  expect(end, greaterThan(start), reason: '$signature does not close');
  return source.substring(start, end);
}

/// One `case` in a switch renders one screen, and it is the next screen named
/// after that case rather than one several branches down.
void _expectCaseRenders(String body, String label, String widget, String what) {
  final int branch = body.indexOf(label);
  expect(branch, greaterThan(-1), reason: '$what lost its branch');
  final int target = body.indexOf(widget, branch);
  expect(target, greaterThan(-1), reason: '$what no longer renders $widget');
  final int nextBranch = body.indexOf('case ', branch + 1);
  expect(target < (nextBranch == -1 ? body.length : nextBranch), isTrue, reason: '$what renders the wrong screen');
}
