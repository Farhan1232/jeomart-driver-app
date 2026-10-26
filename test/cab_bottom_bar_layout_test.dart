import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/themes/app_them_data.dart';
import 'package:driver/utils/cab_bottom_navigation.dart';

/// The driver's cab bottom bar went from two or three items to three or four
/// when the Bid section was added, so the labels have to be measured rather
/// than assumed — "My Trips" is not a short word and 320 dp is a real phone.
///
/// The bar is rebuilt here rather than pumped from `CabDashboardScreen`,
/// because that screen constructs every page and those need Firebase. What is
/// under test is the thing that actually changed: four labels at the bar's own
/// font size on a narrow phone. `flutter_test` turns a `RenderFlex` overflow
/// into an exception, so an overflow anywhere in it fails the test.
void main() {
  /// The four labels, taken from the navigation data itself so this test cannot
  /// drift from the bar it is checking.
  final List<String> fourLabels = <String>[
    CabBottomNavigation.home.labelKey,
    CabBottomNavigation.orders.labelKey,
    CabBottomNavigation.bid.labelKey,
    CabBottomNavigation.myTrips.labelKey,
  ];

  final List<String> threeLabels = <String>[
    CabBottomNavigation.home.labelKey,
    CabBottomNavigation.orders.labelKey,
    CabBottomNavigation.bid.labelKey,
  ];

  /// Mirrors `CabDashboardScreen._bottomNavigationBar`: fixed type, the app's
  /// own selected/unselected colours, and one 24 px Material icon per item.
  Widget bar(List<String> labels) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppThemeData.primary300,
          unselectedItemColor: AppThemeData.grey500,
          currentIndex: 0,
          items: <BottomNavigationBarItem>[
            for (final String label in labels)
              BottomNavigationBarItem(
                icon: const Icon(Icons.circle_outlined),
                activeIcon: const Icon(Icons.circle),
                label: label,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> pumpAt(WidgetTester tester, Size size, List<String> labels) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(bar(labels));
    await tester.pumpAndSettle();
  }

  group('the driver cab bottom bar fits', () {
    testWidgets('four items on a 320 dp phone — the narrowest in common use', (WidgetTester tester) async {
      await pumpAt(tester, const Size(320, 640), fourLabels);
      expect(tester.takeException(), isNull);
    });

    testWidgets('four items on a 360 dp phone', (WidgetTester tester) async {
      await pumpAt(tester, const Size(360, 800), fourLabels);
      expect(tester.takeException(), isNull);
    });

    testWidgets('three items — the driver with no My Trips grant', (WidgetTester tester) async {
      await pumpAt(tester, const Size(320, 640), threeLabels);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every label is rendered, not silently dropped', (WidgetTester tester) async {
      await pumpAt(tester, const Size(320, 640), fourLabels);
      for (final String label in fourLabels) {
        expect(find.text(label), findsWidgets, reason: '$label is missing from the bar');
      }
    });

    testWidgets('no label is wider than the slot it gets', (WidgetTester tester) async {
      // The check the overflow exception alone would not make: a fixed
      // BottomNavigationBar can fade a label out rather than throw.
      await pumpAt(tester, const Size(320, 640), fourLabels);
      final double slot = 320 / fourLabels.length;
      for (final String label in fourLabels) {
        final Size size = tester.getSize(find.text(label).first);
        expect(size.width, lessThanOrEqualTo(slot), reason: '$label is ${size.width}px in a ${slot}px slot');
      }
    });
  });
}
