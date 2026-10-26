// Session 20: the three things the client reported on 9 September.
//
//   * the driver's home screen showed no map at all - a white rectangle where
//     the road should be - until a ride came in;
//   * a ride request had to be accepted without its price being shown;
//   * leaving a section and coming back reloaded everything from the network.
//
// Each group here pins the fix for one of them.

import 'dart:io';

import 'package:driver/app/cab_screen/cab_home_screen.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/models/cab_order_model.dart';
import 'package:driver/models/tax_model.dart';
import 'package:driver/utils/preferences.dart';
import 'package:driver/widget/lazy_indexed_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String cabHome = File('lib/app/cab_screen/cab_home_screen.dart').readAsStringSync();
  final String dashboard = File('lib/app/cab_screen/cab_dashboard_screen.dart').readAsStringSync();
  final String settings = File('lib/utils/fire_store_utils.dart').readAsStringSync();
  final String entryPoint = File('lib/main.dart').readAsStringSync();

  group('the home screen always has a map to draw', () {
    // What went wrong: `settings/DriverNearBy` says `selectedMapType: osm`, but
    // that document is read over the network at launch and the home screen
    // picked its map from a plain static before the read landed. The compiled-in
    // default was Google, and this project's Google Maps key is rejected -
    // billing is off on its Cloud project - so the Android map view drew
    // literally nothing. Pure white, no tiles, no Google logo, no zoom buttons.
    // Nothing re-read the setting afterwards, so the screen stayed white until
    // an unrelated rebuild, which in practice meant until a ride arrived.

    test('the fallback map needs no API key', () {
      // OpenStreetMap draws on any project. Google draws on a billed one.
      expect(Constant.mapChoice.isOsm, isTrue);
      expect(Constant.mapChoice.isInApp, isTrue);
    });

    test('the screen picks its map through the reactive reading', () {
      // `mapChoice` carries `settingsRevision`, so the build that reads it is
      // subscribed to the settings load and redraws when it lands.
      expect(cabHome.contains('final MapChoice mapChoice = Constant.mapChoice;'), isTrue);
      expect(cabHome.contains('child: mapChoice.isInApp'), isTrue);
      expect(cabHome.contains('mapChoice.isOsm'), isTrue);
      // ...and no longer off the bare statics, which cannot announce a change.
      expect(
        cabHome.contains('Constant.mapType == "inappmap"\n'),
        isFalse,
        reason: 'the map branch is reading the static again',
      );
      expect(
        cabHome.contains('Constant.selectedMapType == "osm"'),
        isFalse,
        reason: 'the map branch is reading the static again',
      );
    });

    test('the configuration is restored before the first frame', () {
      final int restore = entryPoint.indexOf('Constant.restoreMapSettings();');
      final int firstFrame = entryPoint.indexOf('runApp(');
      expect(restore, greaterThan(-1), reason: 'main() no longer restores the map settings');
      expect(restore, lessThan(firstFrame), reason: 'restored too late to matter');
    });

    test('a settings read remembers what it applied', () {
      expect(settings.contains('Constant.rememberMapSettings();'), isTrue);
    });

    test('remembering, then restoring, round-trips - and wakes the screens', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await Preferences.initPref();

      final int before = Constant.settingsRevision.value;
      Constant.mapType = 'inappmap';
      Constant.selectedMapType = 'osm';
      Constant.rememberMapSettings();
      expect(Constant.settingsRevision.value, before + 1, reason: 'the screens were not told');

      // A fresh launch, with the statics back at something else.
      Constant.mapType = 'google';
      Constant.selectedMapType = 'google';
      Constant.restoreMapSettings();

      expect(Constant.selectedMapType, 'osm');
      expect(Constant.mapType, 'inappmap');
      expect(Constant.mapChoice.isOsm, isTrue);
    });

    test('nothing to restore leaves the working default alone', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await Preferences.initPref();

      Constant.selectedMapType = 'osm';
      Constant.mapType = 'inappmap';
      Constant.restoreMapSettings();

      expect(Constant.selectedMapType, 'osm');
      expect(Constant.mapType, 'inappmap');
    });
  });

  group('the driver is told what a ride pays', () {
    CabOrderModel order({String? subTotal, String? discount, List<TaxModel>? taxes}) {
      return CabOrderModel()
        ..subTotal = subTotal
        ..discount = discount
        ..taxSetting = taxes;
    }

    test('fare, less discount, plus tax', () {
      final CabOrderModel ride = order(
        subTotal: '500',
        discount: '100',
        taxes: <TaxModel>[TaxModel(enable: true, type: 'percentage', tax: '10')],
      );
      // (500 - 100) + 10% of 400
      expect(CabHomeScreen.rideTotal(ride), 440.0);
    });

    test('a fixed tax is added as it stands', () {
      final CabOrderModel ride = order(
        subTotal: '500',
        taxes: <TaxModel>[TaxModel(enable: true, type: 'fix', tax: '25')],
      );
      expect(CabHomeScreen.rideTotal(ride), 525.0);
    });

    test('an order with no money on it is zero, not a crash', () {
      // `double.parse(null.toString())` threw here, which took the panel down
      // rather than leaving a number out.
      expect(CabHomeScreen.rideTotal(order()), 0.0);
      expect(CabHomeScreen.rideTotal(order(subTotal: '', discount: '')), 0.0);
    });

    test('the label is declared in all nine language files', () {
      for (final String code in <String>['en', 'ar', 'de', 'fr', 'hi', 'ja', 'pt', 'ru', 'zh']) {
        expect(
          File('lib/lang/app_$code.dart').readAsStringSync().contains('"Ride Fare":'),
          isTrue,
          reason: '$code is missing "Ride Fare"',
        );
      }
    });

    test('the price is on the panel that has the Accept button', () {
      final int fare = cabHome.indexOf('"Ride Fare".tr');
      final int accept = cabHome.indexOf('"Accept".tr');
      expect(fare, greaterThan(-1), reason: 'no fare on the request panel');
      expect(accept, greaterThan(-1));
      expect(fare, lessThan(accept), reason: 'the price must be readable before the button');
    });

    test('and on an accepted ride whatever it is paid with', () {
      // It used to appear only on a cash ride, as "Collect payment from
      // customer", so a card or wallet ride never showed a number at all.
      // Once on the request panel, once on the accepted-ride panel.
      expect(RegExp(r'"Ride Fare"\.tr').allMatches(cabHome).length, 2);
      // And the cash line is no longer the only place a number appears.
      expect(cabHome.contains('"Collect Payment from customer".tr'), isTrue);
    });
  });

  group('a section is not thrown away when it is left', () {
    test('the four bar sections are the ones kept', () {
      expect(dashboard.contains('static const List<int> _keptSections'), isTrue);
      for (final String slot in <String>[
        'CabBottomNavigation.homeDrawerIndex',
        'CabBottomNavigation.ordersDrawerIndex',
        'CabBottomNavigation.bidDrawerIndex',
        'CabBottomNavigation.myTripsDrawerIndex',
      ]) {
        expect(dashboard.contains(slot), isTrue, reason: '$slot is not kept');
      }
      expect(dashboard.contains('LazyIndexedStack('), isTrue);
    });

    test('the kept sections survive a visit to a drawer page', () {
      // The stack stays mounted underneath, rather than being swapped out for
      // the drawer page, or leaving the drawer would dispose all four.
      expect(dashboard.contains('offstage: !inKeptSection'), isTrue);
      expect(dashboard.contains('if (!inKeptSection) _drawerPageFor(drawerIndex)'), isTrue);
    });

    testWidgets('a page is built once, however often it is shown', (WidgetTester tester) async {
      final Map<int, int> builds = <int, int>{};
      Widget stack(int index) {
        return MaterialApp(
          home: LazyIndexedStack(
            index: index,
            itemCount: 3,
            itemBuilder: (BuildContext context, int i) {
              builds[i] = (builds[i] ?? 0) + 1;
              return Text('page $i', textDirection: TextDirection.ltr);
            },
          ),
        );
      }

      await tester.pumpWidget(stack(0));
      await tester.pumpWidget(stack(1));
      await tester.pumpWidget(stack(0));
      await tester.pumpWidget(stack(1));

      expect(builds[0], 1, reason: 'coming back rebuilt the page - the reload the client reported');
      expect(builds[1], 1);
      // ...and a section nobody has opened has not been built at all, so its
      // listeners are not running.
      expect(builds.containsKey(2), isFalse);
    });

    testWidgets('a page keeps its state while another is on top', (WidgetTester tester) async {
      Widget stack(int index) {
        return MaterialApp(
          home: LazyIndexedStack(
            index: index,
            itemCount: 2,
            itemBuilder: (BuildContext context, int i) => i == 0 ? const _Counter() : const Text('other'),
          ),
        );
      }

      await tester.pumpWidget(stack(0));
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      await tester.pumpWidget(stack(1));
      await tester.pumpWidget(stack(0));
      expect(find.text('1'), findsOneWidget, reason: 'the section was rebuilt from scratch');
    });
  });

  group('settings are not re-downloaded on every launch', () {
    test('each one is read from the device first, then the server', () {
      expect(settings.contains('GetOptions(source: Source.cache)'), isTrue);
      expect(settings.contains('GetOptions(source: Source.server)'), isTrue);
      expect(settings.contains('if (!servedFromCache) await fromServer;'), isTrue);
    });

    test('the terms and the privacy policy are not part of startup', () {
      // 51 KB and 69 KB, on live listeners, on every launch, for two screens
      // most drivers never open.
      expect(
        settings.contains('doc("privacyPolicy").snapshots()'),
        isFalse,
        reason: 'the privacy policy is being pulled down at startup again',
      );
      expect(
        settings.contains('doc("termsAndConditions").snapshots()'),
        isFalse,
        reason: 'the terms are being pulled down at startup again',
      );
      expect(settings.contains('static Future<String> legalDocument('), isTrue);
    });
  });
}

/// A page with state to lose.
class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text('$_taps', textDirection: TextDirection.ltr),
        TextButton(onPressed: () => setState(() => _taps++), child: const Text('tap')),
      ],
    );
  }
}
