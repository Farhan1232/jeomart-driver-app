import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pagination coverage for the driver app.
///
/// Every Firestore-backed list the driver sees is already paged. What this
/// guards is that it stays that way: a screen added later would otherwise slip
/// past a hand-written list of names, and the symptom - a list that loads its
/// whole collection, or a tab that shows "no orders found" while its rows sit
/// one page down - is exactly what the client keeps reporting.
void main() {
  group('no list screen reads a whole collection', () {
    /// Screens whose list is Firestore-backed but deliberately not paged.
    ///
    /// Every entry here is a driver's *current work*, not a history list: the
    /// active job queue, the open bid requests, the fleet owner's live board.
    /// Those are bounded by how much a driver can be doing at once, and paging
    /// them would hide work rather than reveal it.
    const Map<String, String> exempt = <String, String>{
      'lib/app/cab_screen/bidding_requests_view.dart': 'live open bid requests',
      'lib/app/cab_screen/bidding_screen.dart': 'live open bid requests',
      'lib/app/home_screen/home_screen_multiple_order.dart': 'the active job queue',
      'lib/app/owner_screen/owner_home_screen.dart': 'the fleet owner live board',
      'lib/app/parcel_screen/parcel_home_screen.dart': 'the active job queue',
      'lib/app/rental_service/rental_home_screen.dart': 'the active job queue',

      // Surfaced once the check started following `FireStoreUtils` calls. Each
      // was read before being listed here; none of them is a history list.
      'lib/app/owner_screen/view_all_drivers.dart':
          'the fleet owner live board, the same roster as owner_home_screen',
      'lib/app/verification_screen/verification_screen.dart':
          'the document types the admin configured - a fixed, short list',
      'lib/app/parcel_screen/parcel_order_details.dart':
          'the photographs attached to one parcel',
      'lib/app/home_screen/pickup_order_screen.dart':
          'the products inside one order',
      'lib/app/home_screen/deliver_order_screen.dart':
          'the products inside one order',
      'lib/app/parcel_screen/parcel_search_screen.dart':
          'open jobs inside the search radius - bounded by what is unclaimed '
              'nearby, and a geohash query has no cursor to page with',
      'lib/app/rental_service/rental_booking_search_screen.dart':
          'open jobs inside the search radius - bounded by what is unclaimed '
              'nearby, and a geohash query has no cursor to page with',
    };

    /// Strips `//` line comments and `/* */` blocks.
    ///
    /// Both checks below ask whether a *source* does something, and a comment
    /// that merely mentions the thing is not the thing. This was not academic:
    /// a controller whose doc comment explained that it pages "through the same
    /// [LoadMoreListener] the paginated list screens use" satisfied the paging
    /// check on the strength of the sentence alone, so a planted probe that
    /// removed the real widget still passed.
    String stripComments(String source) {
      final String withoutBlocks = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
      return withoutBlocks
          .split('\n')
          .map((String line) => line.trimLeft().startsWith('//') ? '' : line)
          .join('\n');
    }

    /// Maps every `GetxController` subclass to the file that declares it, so a
    /// screen can be judged together with the controller that feeds it.
    Map<String, String> controllerSources(Map<String, String> sources) {
      final Map<String, String> byName = <String, String>{};
      final RegExp declaration = RegExp(r'class\s+(\w+)\s+extends\s+GetxController');
      sources.forEach((String path, String source) {
        for (final RegExpMatch match in declaration.allMatches(source)) {
          byName[match.group(1)!] = path;
        }
      });
      return byName;
    }

    test('every Firestore-backed list screen pages', () {
      final Map<String, String> sources = <String, String>{};
      for (final FileSystemEntity entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        sources[entity.path] = entity.readAsStringSync();
      }
      final Map<String, String> controllers = controllerSources(sources);

      const List<String> lazyLists = <String>[
        'ListView.builder',
        'ListView.separated',
        'GridView.builder',
      ];
      const List<String> pagingMarkers = <String>[
        'LoadMoreListener',
        'FirestorePaginator',
        'FirestorePagination', // the bundled package widget
      ];

      final List<String> offenders = <String>[];
      final RegExp controllerReference = RegExp(r'\b(\w+Controller)\b');

      sources.forEach((String path, String rawScreen) {
        if (exempt.containsKey(path)) return;
        final String screen = stripComments(rawScreen);
        if (!lazyLists.any(screen.contains)) return;

        // The screen AND every controller it names are judged as one unit.
        //
        // The old version asked whether the *screen file* contained `.get()`
        // or `.snapshots()` and skipped it when it did not - but every screen
        // here delegates its fetching to a controller, so almost nothing was
        // ever examined and a new whole-collection screen would have passed.
        final List<String> unit = <String>[screen];
        for (final RegExpMatch match in controllerReference.allMatches(screen)) {
          final String? source = controllers[match.group(1)];
          if (source != null) unit.add(stripComments(sources[source]!));
        }

        // A screen reaches Firestore either directly, or — far more often in
        // this app — by calling a `FireStoreUtils` helper that does.
        //
        // Looking only for a literal `.get()`/`.snapshots()` in the screen and
        // its controllers still missed a whole class of list screen. The fleet
        // owner's order list is the example that motivated this: its controller
        // contains **zero** literal Firestore calls, because every read goes
        // through `FireStoreUtils.getCabOrdersBySection` and its siblings. The
        // test skipped the screen entirely and reported it as fine while it was
        // downloading four collections' worth of orders unpaged.
        final bool readsFirestore = unit.any(
          (String s) =>
              s.contains('.snapshots()') ||
              s.contains('.get()') ||
              s.contains('FireStoreUtils.'),
        );
        if (!readsFirestore) return;

        final bool paged = unit.any((String s) => pagingMarkers.any(s.contains));
        if (!paged) offenders.add(path);
      });

      expect(
        offenders,
        isEmpty,
        reason: 'these list screens reach Firestore without paging:\n  '
            '${offenders.join('\n  ')}\n'
            'Either page the list, or add it to `exempt` with the reason.',
      );
    });

    test('the exempt list has no stale entries', () {
      for (final String path in exempt.keys) {
        expect(File(path).existsSync(), isTrue, reason: '$path no longer exists; drop it from `exempt`');
      }
    });
  });

  group('a swiped tab pages like a tapped one', () {
    // TabBar(onTap:) fires on taps only - a swipe moves the TabController
    // without it. That callback is what tells the paginator which tab is on
    // screen, so a swiped-to tab kept the previous tab's filter and showed
    // nothing. Every tabbed paginated screen wraps its TabBarView in
    // TabSelectionListener for that reason.
    const List<String> tabbedScreens = <String>[
      'lib/app/cab_screen/cab_order_list_screen.dart',
      'lib/app/parcel_screen/parcel_order_list_screen.dart',
      'lib/app/rental_service/rental_order_list_screen.dart',
    ];

    for (final String path in tabbedScreens) {
      test('${path.split('/').last} listens for the swipe', () {
        final String source = File(path).readAsStringSync();
        expect(source.contains('TabBarView'), isTrue, reason: '$path no longer has tabs; drop it from this list');
        expect(source.contains('TabSelectionListener'), isTrue,
            reason: '$path has a TabBarView the paginator is not told about');
      });
    }

    test('an empty tab can still be pulled to refresh', () {
      // The empty state used to be a bare Center, which scrolls nowhere - so a
      // tab that looked empty offered no way to ask again and no load-more.
      for (final String path in tabbedScreens) {
        final String source = File(path).readAsStringSync();
        expect(source.contains('AlwaysScrollableScrollPhysics'), isTrue, reason: '$path has an unscrollable empty state');
      }
    });
  });
}
