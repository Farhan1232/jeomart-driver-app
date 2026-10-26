import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String sourceOf(String path) {
  final String raw = File(path).readAsStringSync();
  final String withoutBlocks = raw.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return withoutBlocks
      .split('\n')
      .map((String line) => line.trimLeft().startsWith('//') ? '' : line)
      .join('\n');
}

/// The exact shape of the cab home screen's body: a `Stack` in a `Scaffold`
/// body, holding a `Positioned.fill` map and one non-positioned child that is
/// empty while there is no ride.
Widget layout({required bool expand, required bool rideInProgress}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        fit: expand ? StackFit.expand : StackFit.loose,
        children: <Widget>[
          const Positioned.fill(child: ColoredBox(color: Color(0xFF00FF00), key: Key('map'))),
          // `_rideDetailsSheet`: `Positioned.fill` during a ride, a bare
          // `SizedBox.shrink()` when there is none.
          if (rideInProgress)
            const Positioned.fill(child: SizedBox(key: Key('sheet')))
          else
            const SizedBox.shrink(key: Key('sheet')),
        ],
      ),
    ),
  );
}

void main() {
  group('the cab home map has to be given a size', () {
    testWidgets('REPRODUCES the bug: a loose Stack collapses when idle', (WidgetTester tester) async {
      await tester.pumpWidget(layout(expand: false, rideInProgress: false));

      // A Scaffold body is handed `minHeight: 0`, and a Stack sizes itself to
      // its largest NON-positioned child. The only one here is the empty sheet.
      expect(
        tester.getSize(find.byKey(const Key('map'))),
        Size.zero,
        reason: 'this is the defect: the map is built, and it is 0x0',
      );
    });

    testWidgets('and why it looked fixed the moment a ride arrived', (WidgetTester tester) async {
      await tester.pumpWidget(layout(expand: false, rideInProgress: true));

      // With the sheet positioned there is no non-positioned child left, so
      // `size = constraints.biggest` and the map fills the screen. Same code,
      // opposite outcome - which is exactly what made this so hard to pin down.
      final Size map = tester.getSize(find.byKey(const Key('map')));
      expect(map.width, greaterThan(0));
      expect(map.height, greaterThan(0));
    });

    testWidgets('the fix: StackFit.expand fills regardless of the sheet', (WidgetTester tester) async {
      for (final bool ride in <bool>[false, true]) {
        await tester.pumpWidget(layout(expand: true, rideInProgress: ride));
        final Size map = tester.getSize(find.byKey(const Key('map')));
        expect(map.width, greaterThan(0), reason: 'ride=$ride');
        expect(map.height, greaterThan(0), reason: 'ride=$ride');
      }
    });
  });

  group('the screen keeps the fix', () {
    test('the cab home screen stack expands', () {
      final String screen = sourceOf('lib/app/cab_screen/cab_home_screen.dart');
      expect(screen.contains('fit: StackFit.expand'), isTrue,
          reason: 'without this the map collapses to 0x0 whenever there is no ride');
    });

    test('the idle sheet is still allowed to be empty', () {
      // The fix must not depend on the sheet returning something sized - that
      // coupling is what made the bug invisible in review.
      final String screen = sourceOf('lib/app/cab_screen/cab_home_screen.dart');
      expect(screen.contains('return const SizedBox.shrink();'), isTrue);
    });
  });
}
