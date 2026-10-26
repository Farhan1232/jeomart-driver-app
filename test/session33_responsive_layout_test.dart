// Session 33 - the new cab screens, at sizes other than the one they were
// drawn on.
//
// Every case here mirrors a piece of a real screen rather than pumping it:
// `CabOrderDetails`, `CabOrderListScreen` and `CabDashboardScreen` all build
// Firebase listeners through their GetX controllers, so they cannot be pumped
// in a unit test - the same reason `cab_home_sheet_layout_test.dart` mirrors
// the ride sheet instead of opening it.
//
// Two shapes were wrong, and they fail in opposite directions:
//
//   * a **fixed pixel width** inside a box that is wider than it. The route
//     divider on the ride cards was `SizedBox(width: 295)`. On a phone the
//     column clamps it and it looks right; on a tablet the column is 600 px
//     wide and the dashed line stops less than half way across. This is the
//     "looks broken on a big screen" report.
//
//   * an **inflexible child of a Row**. A horizontal Flex lays its inflexible
//     children out with *unbounded* width, so nothing shortens them: the row
//     goes wider than the card and Flutter draws the overflow stripes. Long
//     customer names, long tax titles and translated labels all do it.

import 'package:driver/app/cab_screen/my_trips_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] on a display [width] logical pixels across.
Future<void> pumpAt(WidgetTester tester, double width, Widget child) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

/// The ride card's route block: an icon rail, then the addresses and the dashed
/// divider between them. Mirrors `cab_order_details.dart` and
/// `cab_order_list_screen.dart`.
Widget routeBlock({required double dividerWidth}) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(width: 20, height: 55),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Pickup'),
              SizedBox(key: const Key('divider'), width: dividerWidth, height: 3),
              const Text('Destination'),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The source-address row with the status chip beside it.
Widget statusRow({required bool flexible}) {
  final Widget chip = Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    child: const Text('Order Completed', overflow: TextOverflow.ellipsis),
  );
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: <Widget>[
        const Expanded(child: Text('221B Baker Street, Marylebone', maxLines: 2, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        if (flexible) Flexible(child: chip) else chip,
      ],
    ),
  );
}

/// One line of the Order Summary panel.
Widget summaryTile({required bool flexible}) {
  const String label = 'Admin Commission (10%) on the booking amount';
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (flexible) const Expanded(child: Text(label)) else const Text(label),
        const SizedBox(width: 12),
        const Text('PKR 1,250.00'),
      ],
    ),
  );
}

/// The distance / duration / fare strip.
Widget iconTiles({required bool flexible}) {
  Widget tile(String value, String title) => Column(
        children: <Widget>[
          const SizedBox(width: 28, height: 28),
          Text(value, textAlign: TextAlign.center),
          Text(title, textAlign: TextAlign.center),
        ],
      );
  final List<Widget> tiles = <Widget>[
    tile('1245.75 KM', 'Distance'),
    tile('18 hours 40 mins', 'Duration'),
    tile('PKR 12,450.00', 'Cash on delivery'),
  ];
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: flexible ? tiles.map((Widget t) => Expanded(child: t)).toList() : tiles,
    ),
  );
}

/// The Ongoing / Completed strip above the cab bottom bar.
Widget rideCountsStrip({required bool flexible}) {
  Widget tile(String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.local_taxi_outlined, size: 18),
          const SizedBox(width: 6),
          const Text('1284'),
          const SizedBox(width: 4),
          flexible ? Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)) : Text(label),
        ],
      );
  final List<Widget> tiles = <Widget>[tile('Ongoing rides'), tile('Completed rides')];
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        flexible ? Flexible(child: tiles[0]) : tiles[0],
        Container(width: 1, height: 22, color: const Color(0xFFCCCCCC)),
        flexible ? Flexible(child: tiles[1]) : tiles[1],
      ],
    ),
  );
}

void main() {
  group('the route divider fills the card it is in', () {
    testWidgets('a fixed 295 stops short on a tablet', (WidgetTester tester) async {
      await pumpAt(tester, 800, routeBlock(dividerWidth: 295));
      // 800 - 32 card padding - 20 rail - 12 gap = 736 available, and the
      // dashed line drew 295 of it.
      expect(tester.getSize(find.byKey(const Key('divider'))).width, 295);
    });

    testWidgets('double.infinity fills it, at both sizes', (WidgetTester tester) async {
      await pumpAt(tester, 800, routeBlock(dividerWidth: double.infinity));
      expect(tester.getSize(find.byKey(const Key('divider'))).width, 736);

      await pumpAt(tester, 360, routeBlock(dividerWidth: double.infinity));
      expect(tester.getSize(find.byKey(const Key('divider'))).width, 296);
    });
  });

  group('rows shorten their contents instead of overflowing', () {
    // The chip is a guard rather than an observed break: every status this
    // project ships is short enough to fit beside the address on a 320 px
    // phone. It is here because the chip is the one part of that row a
    // translation or an admin-renamed status can lengthen, and an inflexible
    // child of a Row has nothing to give.
    testWidgets('status chip shortens itself, address keeps the rest', (WidgetTester tester) async {
      await pumpAt(tester, 320, statusRow(flexible: true));
      expect(tester.takeException(), isNull);
      expect(find.text('Order Completed'), findsOneWidget);
      expect(tester.getSize(find.text('221B Baker Street, Marylebone')).width, greaterThan(0));
    });

    testWidgets('order summary line', (WidgetTester tester) async {
      await pumpAt(tester, 320, summaryTile(flexible: false));
      expect(tester.takeException(), isNotNull);

      await pumpAt(tester, 320, summaryTile(flexible: true));
      expect(tester.takeException(), isNull);
    });

    testWidgets('distance / duration / fare tiles', (WidgetTester tester) async {
      await pumpAt(tester, 320, iconTiles(flexible: false));
      expect(tester.takeException(), isNotNull);

      await pumpAt(tester, 320, iconTiles(flexible: true));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the ride counts strip', (WidgetTester tester) async {
      await pumpAt(tester, 280, rideCountsStrip(flexible: false));
      expect(tester.takeException(), isNotNull);

      await pumpAt(tester, 280, rideCountsStrip(flexible: true));
      expect(tester.takeException(), isNull);
    });
  });

  group('My Trips tab strip follows the system font size', () {
    testWidgets('unchanged at the default size', (WidgetTester tester) async {
      late double height;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (BuildContext context) {
            height = MyTripsScreen.tabStripHeight(context);
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(height, 52, reason: 'the value the strip has always had');
    });

    testWidgets('grows with a large accessibility font', (WidgetTester tester) async {
      late double height;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Builder(builder: (BuildContext context) {
              height = MyTripsScreen.tabStripHeight(context);
              return const SizedBox.shrink();
            }),
          ),
        ),
      );
      // 32 px of padding plus a doubled 14 px label: the chips fit instead of
      // being cut off by a flat 52.
      expect(height, greaterThan(70));
    });
  });
}
