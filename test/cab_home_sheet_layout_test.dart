// Geometry harness for the driver's ride-in-progress sheet.
//
// `CabHomeScreen` itself cannot be pumped in a unit test - it builds Firebase
// listeners and a platform map view through its GetX controllers - so this
// mirrors the sheet configuration from `_rideDetailsSheet` and checks the two
// things the client actually reported:
//
//   * the map is visible behind the sheet, at every snap point;
//   * the panel can be pulled down out of the way and back up.
//
// Before the change the panels were unconstrained siblings of an `Expanded`
// map inside a `Column`, so the map got whatever height they left it - 10-20%
// once a ride was underway.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The values `_rideDetailsSheet` is built with. Kept together so a change to
/// the screen that this test should follow is one obvious edit.
const double kInitialSize = 0.5;
const double kMinSize = 0.14;
const double kMaxSize = 0.88;

Widget harness() {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: ColoredBox(color: Color(0xFF90CAF9), child: Center(child: Text('MAP')))),
          Positioned.fill(
            child: DraggableScrollableSheet(
              initialChildSize: kInitialSize,
              minChildSize: kMinSize,
              maxChildSize: kMaxSize,
              expand: false,
              snap: true,
              snapSizes: const <double>[kInitialSize],
              builder: (BuildContext context, ScrollController scrollController) {
                return ColoredBox(
                  color: const Color(0xFFFFFFFF),
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    children: <Widget>[
                      const SizedBox(height: 22, child: Center(child: Text('HANDLE'))),
                      Column(children: List<Widget>.generate(20, (int i) => SizedBox(height: 60, child: Text('row $i')))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// Height of the sheet as a fraction of the screen.
double sheetFraction(WidgetTester tester) {
  final double screen = tester.getSize(find.byType(Scaffold)).height;
  final double top = tester.getRect(find.byType(ListView)).top;
  return (screen - top) / screen;
}

void main() {
  for (final Size size in <Size>[const Size(360, 640), const Size(412, 915)]) {
    group('${size.width.toInt()}x${size.height.toInt()}', () {
      testWidgets('opens at half, so map and panel share the screen', (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness());
        await tester.pumpAndSettle();

        expect(sheetFraction(tester), closeTo(kInitialSize, 0.02));
        // The whole point: the map is not covered.
        expect(find.text('MAP'), findsOneWidget);
        expect(tester.getRect(find.byType(ListView)).top, greaterThan(0));
      });

      testWidgets('drags down to the handle and exposes the full map', (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness());
        await tester.pumpAndSettle();

        await tester.drag(find.text('HANDLE'), Offset(0, size.height));
        await tester.pumpAndSettle();

        expect(sheetFraction(tester), closeTo(kMinSize, 0.02));
        // Collapsed, the map has the screen: 86% of it.
        expect(1 - sheetFraction(tester), greaterThan(0.8));
      });

      testWidgets('drags back up to expanded to read the details', (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness());
        await tester.pumpAndSettle();

        await tester.drag(find.text('HANDLE'), Offset(0, -size.height));
        await tester.pumpAndSettle();

        expect(sheetFraction(tester), closeTo(kMaxSize, 0.02));
        // Even expanded the sheet never takes the whole screen.
        expect(sheetFraction(tester), lessThan(1.0));
      });
    });
  }
}
