import 'dart:async';

/// Runs the same asynchronous read over a list of inputs without waiting for
/// each one to come back before starting the next.
///
/// ## Why the app needed this
///
/// The driver app has loops shaped like
///
/// ```dart
/// for (final id in driverIds) {
///   final snapshot = await query(id).get();
/// }
/// ```
///
/// Every one of those costs one network round trip **per row, in series**. The
/// fleet owner's order list is the worst case: it runs one query per driver in
/// the fleet before it can show anything, so a twenty-driver owner waited on
/// twenty round trips laid end to end. None of those reads depends on the one
/// before it — they are sequential only because a `for` loop with an `await` in
/// it is the easiest thing to write.
///
/// ## What it guarantees
///
/// * **Order is preserved.** The result at index *i* is the result for the
///   input at index *i*, whatever order the network answered in. The call sites
///   concatenate these into a list that is then sorted and rendered, so a
///   shuffled result would quietly change what the owner sees.
/// * **Concurrency is bounded.** Firing twenty queries into a phone's radio at
///   once is its own kind of slow and starves whatever else the screen is
///   waiting for. [defaultConcurrency] is a compromise: enough to collapse the
///   round-trip chain, few enough to stay polite.
/// * **One failure does not lose the batch.** `Future.wait` rejects the whole
///   batch on the first error, which would turn one unreadable document into an
///   empty screen. Each task is guarded and a failed one yields `null`, which
///   is what the sequential code it replaces did when its own error handler
///   fired.
class Parallel {
  Parallel._();

  /// How many reads are allowed to be in flight at once.
  static const int defaultConcurrency = 8;

  /// Maps [items] through [task], at most [concurrency] at a time.
  ///
  /// The returned list is the same length as [items] and in the same order. An
  /// entry is `null` where that task threw.
  static Future<List<R?>> map<T, R>(
    Iterable<T> items,
    Future<R?> Function(T item) task, {
    int concurrency = defaultConcurrency,
  }) async {
    final List<T> inputs = items.toList(growable: false);
    if (inputs.isEmpty) return <R?>[];

    final List<R?> results = List<R?>.filled(inputs.length, null);
    final int limit = concurrency < 1 ? 1 : concurrency;
    int next = 0;

    Future<void> worker() async {
      while (true) {
        final int index = next;
        if (index >= inputs.length) return;
        next++;
        try {
          results[index] = await task(inputs[index]);
        } catch (_) {
          results[index] = null;
        }
      }
    }

    final int workers = limit < inputs.length ? limit : inputs.length;
    await Future.wait(List<Future<void>>.generate(workers, (_) => worker()));
    return results;
  }

  /// [map], with the `null`s — failed or absent — dropped.
  static Future<List<R>> mapNotNull<T, R>(
    Iterable<T> items,
    Future<R?> Function(T item) task, {
    int concurrency = defaultConcurrency,
  }) async {
    final List<R?> results = await map<T, R>(items, task, concurrency: concurrency);
    return results.whereType<R>().toList();
  }
}
