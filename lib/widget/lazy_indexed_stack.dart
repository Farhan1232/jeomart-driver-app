import 'package:flutter/material.dart';

/// An [IndexedStack] that builds a page the first time it is shown, and keeps
/// it from then on.
///
/// The dashboards chose their body with a chain of `?:`, so leaving a section
/// threw that section away: its GetX controller reached `onClose`, its
/// Firestore listeners were cancelled, and coming back re-ran every query over
/// the network. That is the "when you go back from any section it loads all
/// things again from internet" report, and on a slow connection it is the
/// whole wait, paid again every time.
///
/// A plain [IndexedStack] fixes that by building *every* page up front, which
/// is the opposite problem: every section's listeners would open at launch
/// whether or not the driver ever goes there. This one builds nothing until it
/// is asked for, and never builds the same page twice.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.itemCount,
    required this.itemBuilder,
  });

  /// Which page is on top.
  final int index;

  /// How many pages this stack can hold.
  final int itemCount;

  /// Builds one page. Called once per page, when it is first shown.
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  /// One slot per page, `null` until that page has been visited.
  ///
  /// Growable, and reconciled against [LazyIndexedStack.itemCount] on every
  /// build. It used to be `List.filled` sized once, which is fine for a bar
  /// whose tabs are fixed but wrong for the multi-service dashboard: its My
  /// Trips tab appears and disappears with the admin's grant, so the count can
  /// rise after the first build and `_pages[index]` would have thrown a
  /// RangeError on the new tab. Pages already built are kept across the
  /// change — that is the whole point of this widget — and only the tail is
  /// dropped when the count falls.
  final List<Widget?> _pages = <Widget?>[];

  void _fitTo(int itemCount) {
    while (_pages.length < itemCount) {
      _pages.add(null);
    }
    if (_pages.length > itemCount) {
      _pages.removeRange(itemCount, _pages.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    _fitTo(widget.itemCount);
    if (widget.index < 0 || widget.index >= widget.itemCount) {
      // A caller that has not clamped yet. Draw nothing rather than throw.
      return const SizedBox.shrink();
    }
    _pages[widget.index] ??= widget.itemBuilder(context, widget.index);
    return IndexedStack(
      index: widget.index,
      sizing: StackFit.expand,
      children: <Widget>[
        for (int i = 0; i < widget.itemCount; i++) _pages[i] ?? const SizedBox.shrink(),
      ],
    );
  }
}
