import 'cab_bottom_navigation.dart';
import 'driver_ride_counts.dart';

/// What the cab bottom bar draws on top of one tab's icon.
///
/// Two independent marks, because they answer two different questions:
///
/// * [count] - "how many things are waiting for you in here", a live number;
/// * [isNew] - "you have never opened this section", a one-off.
///
/// A tab can carry both, either, or neither.
class CabNavBadge {
  const CabNavBadge({this.count = 0, this.isNew = false});

  /// Nothing drawn at all.
  static const CabNavBadge none = CabNavBadge();

  /// The number on the red counter. Zero means no counter: a badge reading "0"
  /// is noise, and the driver reads "nothing to do" faster from an icon with
  /// nothing on it.
  final int count;

  /// Whether the green NEW ribbon is drawn.
  final bool isNew;

  bool get hasCount => count > 0;

  bool get isEmpty => !hasCount && !isNew;

  /// The text on the counter, capped so a busy driver's badge cannot grow wide
  /// enough to sit on top of the next tab. Shared with the ride-counts strip so
  /// the two never disagree about how 100+ is written.
  String get label => DriverRideCounts.badgeLabel(count);

  @override
  bool operator ==(Object other) => other is CabNavBadge && other.count == count && other.isNew == isNew;

  @override
  int get hashCode => Object.hash(count, isNew);

  @override
  String toString() => 'CabNavBadge(count: $count, isNew: $isNew)';
}

/// Which badge each tab of the cab bottom bar carries.
///
/// Pure, and kept out of the widget for the same reason [CabBottomNavigation]
/// is: what a badge says is a rule worth testing, and testing it through a
/// pumped `BottomNavigationBar` would need Firebase and GetX for no gain.
class CabNavBadges {
  /// The sections that carry a first-visit NEW ribbon.
  ///
  /// Bid and My Trips, because they are the two the driver did not have before
  /// and would otherwise have no reason to tap. Home and Orders have been there
  /// since the app shipped; marking them new would be a lie and would teach the
  /// driver to ignore the ribbon.
  static const Set<int> ribbonSections = <int>{
    CabBottomNavigation.bidDrawerIndex,
    CabBottomNavigation.myTripsDrawerIndex,
  };

  /// Where "this driver has opened that section" is remembered.
  ///
  /// One key per drawer slot, in the app's existing `SharedPreferences`. It is
  /// per device and that is the right scope: the ribbon points at something in
  /// the interface in front of them, not at anything on their account.
  static String seenKeyFor(int drawerIndex) => 'cabSectionSeen_$drawerIndex';

  /// The badge for [drawerIndex].
  ///
  /// [hasSeenSection] answers "has this driver opened that slot before" and is
  /// injected rather than read here, so this stays a pure function and the
  /// tests do not need a `SharedPreferences` binding.
  ///
  /// Only Orders carries a count. The Bid tab deliberately does not - the open
  /// offer count lives on `BiddingRequestController`, which is mounted and
  /// disposed with the screen that shows the offers, so read from the bar it
  /// would be present on two tabs and absent on the others and the same driver
  /// with the same offers would watch the number come and go as they moved
  /// around. My Trips does not either: a driver's own posted trips are not work
  /// waiting for them.
  static CabNavBadge badgeFor({
    required int drawerIndex,
    required int ongoingRides,
    required bool Function(int drawerIndex) hasSeenSection,
  }) {
    final bool isNew = ribbonSections.contains(drawerIndex) && !hasSeenSection(drawerIndex);
    if (drawerIndex == CabBottomNavigation.ordersDrawerIndex) {
      return CabNavBadge(count: ongoingRides < 0 ? 0 : ongoingRides, isNew: isNew);
    }
    return CabNavBadge(isNew: isNew);
  }

  /// Whether opening [drawerIndex] should be remembered.
  ///
  /// Only the ribboned sections are ever written, so navigating around the app
  /// does not turn every drawer tap into a preferences write.
  static bool marksSeen(int drawerIndex) => ribbonSections.contains(drawerIndex);
}
