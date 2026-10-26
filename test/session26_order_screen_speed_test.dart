import 'dart:async';
import 'dart:io';

import 'package:driver/utils/firestore_paginator.dart';
import 'package:flutter_test/flutter_test.dart';

String sourceOf(String path) {
  final String raw = File(path).readAsStringSync();
  final String withoutBlocks = raw.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return withoutBlocks
      .split('\n')
      .map((String line) => line.trimLeft().startsWith('//') ? '' : line)
      .join('\n');
}

class Doc {
  Doc(this.id, this.status);
  final String id;
  final String status;
}

/// Counts page reads and can make each one take measurable time, so the cost of
/// waiting for the auto-fill is visible to the test.
class CountingSource extends PageSource<Doc> {
  CountingSource(this.docs, {this.perFetch = Duration.zero});

  final List<Doc> docs;
  final Duration perFetch;
  int fetchCalls = 0;

  @override
  Future<List<Doc>> fetch({required Doc? after, required int limit}) async {
    fetchCalls++;
    if (perFetch > Duration.zero) await Future<void>.delayed(perFetch);
    var start = 0;
    if (after != null) start = docs.indexWhere((Doc d) => d.id == after.id) + 1;
    return docs.skip(start).take(limit).toList();
  }

  @override
  String idOf(Doc doc) => doc.id;
}

/// 120 finished rides and not one current one — the ordinary state of a working
/// driver, and the state the "On Going" tab opens on.
List<Doc> historyOnly() =>
    List<Doc>.generate(120, (int i) => Doc('d$i', 'Order Completed'));

FirestorePaginator<Doc, Doc> paginatorOver(CountingSource source) =>
    FirestorePaginator<Doc, Doc>(
      source: source,
      mapper: (Doc d) => d,
      pageSize: 20,
      autoFillTarget: 10,
      filter: (Doc d) => d.status == 'Driver Accepted', // the "On Going" tab
    );

void main() {
  group('the Orders screen paints on its first page', () {
    test('waiting for the auto-fill costs six sequential reads', () async {
      final CountingSource source = CountingSource(historyOnly());
      final FirestorePaginator<Doc, Doc> p = paginatorOver(source);

      await p.refresh(); // the old behaviour, still the default

      // First page + autoFillMaxPages(5) more, every one of them a round trip
      // the driver waited through before the screen appeared at all.
      expect(source.fetchCalls, 6);
      expect(p.visibleItems, isEmpty, reason: 'no ongoing rides to find');
      p.dispose();
    });

    test('not waiting releases the screen while the top-up is still running', () async {
      // A measurable cost per read, so "returned early" is a fact and not a
      // race: with the top-up awaited this is six reads end to end.
      const Duration perFetch = Duration(milliseconds: 40);

      final CountingSource slow = CountingSource(historyOnly(), perFetch: perFetch);
      final FirestorePaginator<Doc, Doc> waited = paginatorOver(slow);
      final Stopwatch a = Stopwatch()..start();
      await waited.refresh();
      a.stop();
      expect(slow.fetchCalls, 6);

      final CountingSource fast = CountingSource(historyOnly(), perFetch: perFetch);
      final FirestorePaginator<Doc, Doc> notWaited = paginatorOver(fast);
      final Stopwatch b = Stopwatch()..start();
      await notWaited.refresh(awaitAutoFill: false);
      b.stop();

      expect(fast.fetchCalls, lessThan(6),
          reason: 'the screen was released before the top-up finished');
      expect(b.elapsed, lessThan(a.elapsed),
          reason: 'the driver waits for one read, not six');
      expect(notWaited.isToppingUp.value, isTrue);

      waited.dispose();
      notWaited.dispose();
    });

    test('and the top-up still happens, behind the list', () async {
      final CountingSource source = CountingSource(historyOnly());
      final FirestorePaginator<Doc, Doc> p = paginatorOver(source);

      await p.refresh(awaitAutoFill: false);
      expect(p.isToppingUp.value, isTrue, reason: 'it is still filling');

      // Let the unawaited top-up run to completion.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(source.fetchCalls, 6, reason: 'the same reads happen, just not in the way');
      expect(p.isToppingUp.value, isFalse);
      p.dispose();
    });

    test('the top-up flag clears even when there is nothing to fill', () async {
      // No filter and no target: `_autoFill` returns immediately. The flag must
      // not be left on, or a screen gating its empty state on it hangs.
      final CountingSource source = CountingSource(historyOnly());
      final FirestorePaginator<Doc, Doc> p = FirestorePaginator<Doc, Doc>(
        source: source,
        mapper: (Doc d) => d,
        pageSize: 20,
      );
      await p.refresh(awaitAutoFill: false);
      expect(p.isToppingUp.value, isFalse);
      p.dispose();
    });

    test('the rows that end up on screen are identical either way', () async {
      final List<Doc> mixed = <Doc>[
        for (int i = 0; i < 100; i++) Doc('h$i', 'Order Completed'),
        Doc('live1', 'Driver Accepted'),
      ];

      final CountingSource a = CountingSource(mixed);
      final FirestorePaginator<Doc, Doc> waited = paginatorOver(a);
      await waited.refresh();

      final CountingSource b = CountingSource(mixed);
      final FirestorePaginator<Doc, Doc> notWaited = paginatorOver(b);
      await notWaited.refresh(awaitAutoFill: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(notWaited.visibleItems.map((Doc d) => d.id).toList(),
          waited.visibleItems.map((Doc d) => d.id).toList());
      waited.dispose();
      notWaited.dispose();
    });
  });

  group('the list screens keep the fast first paint', () {
    const List<String> controllers = <String>[
      'lib/controllers/cab_order_list_controller.dart',
      'lib/controllers/parcel_order_list_controller.dart',
      'lib/controllers/rental_order_list_controller.dart',
      'lib/controllers/my_trips_controller.dart',
    ];

    test('every paged list screen releases on its first page', () {
      for (final String path in controllers) {
        final String source = sourceOf(path);
        expect(source.contains('refresh(awaitAutoFill: false)'), isTrue,
            reason: '$path holds its spinner through the whole top-up again');
      }
    });

    test('and each exposes the top-up signal its screen needs', () {
      for (final String path in controllers) {
        expect(sourceOf(path).contains('bool get isToppingUp'), isTrue, reason: path);
      }
    });

    const List<String> screens = <String>[
      'lib/app/cab_screen/cab_order_list_screen.dart',
      'lib/app/parcel_screen/parcel_order_list_screen.dart',
      'lib/app/rental_service/rental_order_list_screen.dart',
      'lib/app/cab_screen/my_trips_screen.dart',
    ];

    test('no screen claims "empty" while the list is still filling', () {
      for (final String path in screens) {
        expect(sourceOf(path).contains('controller.isToppingUp'), isTrue,
            reason: '$path can show "no orders found" over rows that are on the way');
      }
    });
  });
}
