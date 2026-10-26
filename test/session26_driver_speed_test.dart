import 'dart:async';
import 'dart:io';

import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/utils/app_image_cache.dart';
import 'package:driver/utils/network_timeout.dart';
import 'package:driver/utils/parallel.dart';
import 'package:driver/widget/lazy_indexed_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads a source file with its comments removed.
///
/// Every source-level assertion below has to look at code, not prose. The
/// explanatory comments this session added quote the very expressions the
/// tests forbid — "this used to be `45.521563`", "the old `for (final did in
/// driverIds)`" — so a check that matched raw text would fail on correct code,
/// or worse, pass on broken code because a comment mentioned the fix.
String sourceOf(String path) {
  final String raw = File(path).readAsStringSync();
  final String withoutBlocks = raw.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return withoutBlocks
      .split('\n')
      .map((String line) => line.trimLeft().startsWith('//') ? '' : line)
      .join('\n');
}

void main() {
  group('the map draws before the network, not after it', () {
    test('the delivery home screen no longer waits on a Firestore snapshot', () {
      final String controller = sourceOf('lib/controllers/home_controller.dart');

      // The defect: `isLoading` was dropped inside the `users` listener, and
      // only when that snapshot carried an id. Until then the body - which is
      // the map - was a spinner, and a read that never landed left it there.
      final int listenerIndex = controller.indexOf('_driverSub = FireStoreUtils');
      final int releaseIndex = controller.indexOf('isLoading.value = false');
      expect(listenerIndex, isNonNegative);
      expect(releaseIndex, isNonNegative);
      expect(
        controller.indexOf('isLoading.value = false', listenerIndex),
        -1,
        reason: 'the screen is being released from inside the driver listener again',
      );
    });

    test('no map screen opens on a hardcoded city any more', () {
      // Every one of these was a real coordinate a driver actually saw.
      const Map<String, String> banned = <String, String>{
        '45.521563': 'Portland, Oregon - the parcel tracking fallback',
        '-122.677433': 'Portland, Oregon - the parcel tracking fallback',
        '20.5937': 'the geographic centre of India - the OSM picker',
      };
      const List<String> screens = <String>[
        'lib/app/parcel_screen/parcel_tracking_screen.dart',
        'lib/app/owner_screen/driver_location_screen.dart',
      ];
      for (final String path in screens) {
        final String screen = sourceOf(path);
        banned.forEach((String coordinate, String where) {
          expect(screen.contains(coordinate), isFalse, reason: '$path still opens on $where');
        });
      }
    });

    test('the parcel tracking map is centred by the controller, once', () {
      final String screen = sourceOf('lib/app/parcel_screen/parcel_tracking_screen.dart');
      expect(screen.contains('initialCenter: controller.initialMapCentre'), isTrue);
      expect(screen.contains('onMapReady: controller.onMapReady'), isTrue);

      final String controller = sourceOf('lib/controllers/parcel_tracking_controller.dart');
      expect(controller.contains('DriverMapLocation'), isTrue);
      expect(controller.contains('mapLocation.dispose()'), isTrue,
          reason: 'the location stream outlives the screen again');
    });

    test('the parcel tracking screen cancels the driver listener before reopening it', () {
      final String controller = sourceOf('lib/controllers/parcel_tracking_controller.dart');
      final int reopen = controller.indexOf('driverSubscription =\n');
      expect(reopen, isNonNegative);
      // The cancel has to come first, in the same callback, or every order
      // update leaves another live listener behind.
      final String before = controller.substring(0, reopen);
      expect(before.trimRight().endsWith('driverSubscription?.cancel();'), isTrue,
          reason: 'the driver listener is being replaced without cancelling the old one');
    });

    test('the owner board can be moved after it is built', () {
      final String controller = sourceOf('lib/controllers/driver_location_controller.dart');
      expect(controller.contains('DriverMapCentre'), isTrue);
      // `current.value = ...` alone could never move a map whose initialCenter
      // had already been read.
      expect(controller.contains('mapCentre.moveTo'), isTrue);
      // And the fleet's own positions must go through the Null Island check.
      expect(controller.contains('realMapPoint(driver.location)'), isTrue);
      expect(controller.contains('first.location!.latitude!'), isFalse,
          reason: 'the force-unwrap that threw inside a snapshot callback is back');
    });

    test('the owner board is not recentred on every rebuild', () {
      final String screen = sourceOf('lib/app/owner_screen/driver_location_screen.dart');
      expect(screen.contains('addPostFrameCallback'), isFalse,
          reason: 'the camera is being snapped back on every repaint again');
    });
  });

  group('nothing on a screen-load path can wait for ever', () {
    test('every map, route and geocode request is bounded', () {
      const Map<String, int> expected = <String, int>{
        'lib/controllers/home_controller.dart': 1,
        'lib/controllers/cab_home_controller.dart': 1,
        'lib/controllers/parcel_tracking_controller.dart': 1,
        'lib/controllers/cab_order_details_controller.dart': 2,
        'lib/widget/osm_map/map_controller.dart': 2,
        'lib/constant/constant.dart': 1,
      };
      expected.forEach((String path, int count) {
        final String source = sourceOf(path);
        expect(
          'timeout(NetworkTimeout.mapRequest)'.allMatches(source).length,
          count,
          reason: '$path has an unbounded request on a map path',
        );
      });
    });

    test('payment requests are deliberately left unbounded', () {
      // Abandoning a slow gateway client-side risks a charge the app has
      // stopped waiting to hear about. This is a decision, so it is pinned.
      final String wallet = sourceOf('lib/controllers/wallet_controller.dart');
      expect(wallet.contains('NetworkTimeout'), isFalse,
          reason: 'a payment call has been given a client-side timeout');
    });

    test('the route lookup survives a routeless answer', () {
      final String controller = sourceOf('lib/controllers/home_controller.dart');
      // OSRM answers {"code":"NoRoute"} for points it cannot connect, and
      // `decoded['routes'][0]` threw straight into a `.then` with no onError.
      expect(controller.contains("routes.first['geometry']"), isTrue);
      expect(controller.contains("decoded['routes'][0]['geometry']['coordinates']"), isFalse);
    });

    test('the OSRM route in cab order details is not requested over cleartext', () {
      final String controller = sourceOf('lib/controllers/cab_order_details_controller.dart');
      expect(controller.contains('http://router.project-osrm.org'), isFalse,
          reason: 'cleartext is blocked by default on modern Android, so the route never drew');
    });

    test('a loader cannot block the screen for the rest of the session', () {
      expect(ShowToastDialog.loaderWatchdog, const Duration(seconds: 30));
      final String source = sourceOf('lib/constant/show_toast_dialog.dart');
      expect(source.contains('Timer(loaderWatchdog'), isTrue);
      expect(source.contains('_watchdog?.cancel()'), isTrue,
          reason: 'closeLoader must cancel the watchdog or it fires over a later screen');
    });
  });

  group('the driver location stream is not left running', () {
    const List<String> dashboards = <String>[
      'lib/controllers/cab_dashboard_controller.dart',
      'lib/controllers/dash_board_controller.dart',
      'lib/controllers/parcel_dashboard_controller.dart',
      'lib/controllers/rental_dashboard_controller.dart',
    ];

    test('every GPS listener is registered for cancellation', () {
      for (final String path in dashboards) {
        final String source = sourceOf(path);
        final int listeners = 'location.onLocationChanged.listen('.allMatches(source).length;
        final int registered =
            '_subscriptions.add(location.onLocationChanged.listen('.allMatches(source).length;
        expect(listeners, 2, reason: '$path: expected both permission branches');
        expect(registered, listeners,
            reason: '$path: a GPS listener is not registered, so it outlives the screen '
                'and every re-entry adds another read+write per movement');
      }
    });

    test('the dashboard does not wait for the permission dialog to show itself', () {
      for (final String path in dashboards) {
        final String source = sourceOf(path);
        expect(source.contains('await updateCurrentLocation()'), isFalse,
            reason: '$path: the users listener is behind a permission dialog again');
        expect(source.contains('unawaited(updateCurrentLocation())'), isTrue);
      }
    });
  });

  group('reads that were paid one row at a time', () {
    test('the first-order check reads two documents, not the whole history', () {
      final String source = sourceOf('lib/utils/fire_store_utils.dart');
      final int checks = "where('authorID', isEqualTo: orderModel.authorID)".allMatches(source).length;
      final int bounded =
          "where('authorID', isEqualTo: orderModel.authorID).limit(2)".allMatches(source).length;
      expect(checks, greaterThanOrEqualTo(4));
      expect(bounded, 4, reason: 'a first-order check is downloading a customer\'s whole history again');
    });

    test('the owner section queries no longer run one driver at a time', () {
      final String source = sourceOf('lib/utils/fire_store_utils.dart');
      expect(source.contains('for (final did in driverIds)'), isFalse,
          reason: 'the sequential per-driver loop is back');
      expect('Parallel.map<String, List<'.allMatches(source).length, 4,
          reason: 'all four section queries should fan out');
    });

    test('the verification screen loads both halves together', () {
      final String source = sourceOf('lib/controllers/verification_controller.dart');
      // Both futures must be created before either is awaited. Awaiting the
      // first call directly is what made the screen pay for both in series.
      expect(source.contains('await FireStoreUtils.getDocumentList'), isFalse,
          reason: 'the two independent reads are sequential again');
      expect(source.contains('await FireStoreUtils.getDocumentOfDriver'), isFalse,
          reason: 'the two independent reads are sequential again');
      final int startFirst = source.indexOf('FireStoreUtils.getDocumentList');
      final int startSecond = source.indexOf('FireStoreUtils.getDocumentOfDriver');
      final int firstAwait = source.indexOf('await requiredTypes');
      expect(startFirst, isNonNegative);
      expect(startSecond, isNonNegative);
      expect(startSecond, lessThan(firstAwait),
          reason: 'the second read is not started until the first has returned');
    });
  });

  group('Parallel', () {
    test('keeps results in the order of the inputs, whatever order they finish in', () async {
      final List<int> inputs = <int>[1, 2, 3, 4, 5];
      final List<int?> results = await Parallel.map<int, int>(inputs, (int i) async {
        // Later inputs finish first.
        await Future<void>.delayed(Duration(milliseconds: (6 - i) * 10));
        return i * 10;
      });
      expect(results, <int>[10, 20, 30, 40, 50]);
    });

    test('one failure yields null instead of losing the batch', () async {
      final List<int?> results = await Parallel.map<int, int>(<int>[1, 2, 3], (int i) async {
        if (i == 2) throw StateError('unreadable');
        return i;
      });
      expect(results, <int?>[1, null, 3]);
    });

    test('never runs more than the concurrency limit at once', () async {
      int running = 0;
      int peak = 0;
      await Parallel.map<int, int>(
        List<int>.generate(20, (int i) => i),
        (int i) async {
          running++;
          peak = running > peak ? running : peak;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          running--;
          return i;
        },
        concurrency: 4,
      );
      expect(peak, lessThanOrEqualTo(4));
      expect(peak, greaterThan(1), reason: 'it is not actually running in parallel');
    });

    test('an empty input does no work', () async {
      expect(await Parallel.map<int, int>(<int>[], (int i) async => i), isEmpty);
    });
  });

  group('AppImageCache', () {
    // Firebase Storage serves every upload on this project with
    // `cache-control: private, max-age=0`, which flutter_cache_manager reads as
    // "already stale" - so every image is re-fetched on every display.
    final DateTime now = DateTime.utc(2026, 9, 10, 12);

    test('a server that says "stale now" gets a usable freshness instead', () {
      final DateTime raised = AppImageCache.freshnessFor(now, now: now);
      expect(raised.isAfter(now), isTrue);
      expect(raised.difference(now), const Duration(days: 7));
    });

    test('a server that asks for the past is also raised', () {
      final DateTime raised =
          AppImageCache.freshnessFor(now.subtract(const Duration(hours: 3)), now: now);
      expect(raised, now.add(const Duration(days: 7)));
    });

    test('a real freshness from the server is obeyed untouched', () {
      final DateTime server = now.add(const Duration(hours: 2));
      expect(AppImageCache.freshnessFor(server, now: now), server);
    });
  });

  group('LazyIndexedStack', () {
    testWidgets('builds a page when it is first shown and not before', (WidgetTester tester) async {
      final List<int> built = <int>[];
      Widget stack(int index, int count) => MaterialApp(
            home: LazyIndexedStack(
              index: index,
              itemCount: count,
              itemBuilder: (BuildContext context, int i) {
                built.add(i);
                return Text('page $i');
              },
            ),
          );

      await tester.pumpWidget(stack(0, 3));
      expect(built, <int>[0], reason: 'a plain IndexedStack would have built all three');

      await tester.pumpWidget(stack(2, 3));
      expect(built, <int>[0, 2]);

      // Going back must not rebuild - that is the whole point of keeping them.
      await tester.pumpWidget(stack(0, 3));
      expect(built, <int>[0, 2]);
    });

    testWidgets('survives a tab appearing after the first build', (WidgetTester tester) async {
      // The multi-service dashboard gains and loses its My Trips tab with the
      // admin's grant. A fixed-length slot list threw a RangeError on the new
      // tab.
      Widget stack(int index, int count) => MaterialApp(
            home: LazyIndexedStack(
              index: index,
              itemCount: count,
              itemBuilder: (BuildContext context, int i) => Text('page $i'),
            ),
          );

      await tester.pumpWidget(stack(0, 2));
      await tester.pumpWidget(stack(2, 3));
      expect(tester.takeException(), isNull);
      expect(find.text('page 2'), findsOneWidget);

      // And losing one again drops only the tail.
      await tester.pumpWidget(stack(0, 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an index past the end draws nothing rather than throwing', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LazyIndexedStack(
          index: 5,
          itemCount: 2,
          itemBuilder: (BuildContext context, int i) => Text('page $i'),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    test('the multi-service dashboard uses it', () {
      final String screen = sourceOf('lib/app/multi_service/multi_service_dashboard_screen.dart');
      expect(screen.contains('LazyIndexedStack('), isTrue);
      expect(screen.contains('body: IndexedStack('), isFalse,
          reason: 'every service dashboard is being started up front again');
    });
  });

  group('the fleet owner order list', () {
    test('builds a page of rows at a time', () {
      final String screen = sourceOf('lib/app/owner_screen/owner_order_list.dart');
      expect('LoadMoreListener('.allMatches(screen).length, 4,
          reason: 'all four owner lists should page');
      expect(screen.contains('itemCount: orders.length,'), isFalse,
          reason: 'a list is building every order it fetched again');
    });

    test('a new section starts at the first page', () {
      final String controller = sourceOf('lib/controllers/owner_order_list_controller.dart');
      expect(controller.contains('resetVisibleRows()'), isTrue);
      expect(controller.contains('static const int rowsPerPage = 20'), isTrue);
    });
  });

  group('images are cached and decoded at the size they are drawn', () {
    test('every cached image draws through the app cache', () {
      const List<String> paths = <String>[
        'lib/utils/network_image_widget.dart',
        'lib/app/help_support_screen/help_support_screen.dart',
        'lib/app/owner_screen/owner_order_list.dart',
        'lib/app/rental_service/rental_order_list_screen.dart',
        'lib/app/verification_screen/verification_details_upload_screen.dart',
      ];
      for (final String path in paths) {
        final String source = sourceOf(path);
        final int images = 'CachedNetworkImage('.allMatches(source).length +
            'CachedNetworkImageProvider('.allMatches(source).length;
        final int wired = 'cacheManager: AppImageCache.manager'.allMatches(source).length;
        expect(wired, images, reason: '$path has an image bypassing the cache manager');
      }
    });

    test('the shared image widget caps its decode size', () {
      final String source = sourceOf('lib/utils/network_image_widget.dart');
      expect(source.contains('memCacheWidth'), isTrue);
      expect(source.contains('devicePixelRatioOf'), isTrue,
          reason: 'the cap has to be in device pixels or the image is drawn soft');
    });
  });
}
