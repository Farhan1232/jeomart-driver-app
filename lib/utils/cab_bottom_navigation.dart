import 'my_trips_access.dart';

/// One destination in the cab section's bottom navigation.
///
/// A destination names the **`drawerIndex` it renders**, not the position it
/// happens to occupy in the bar. That is the whole point: the My Trips entry
/// is conditional, so a bar built by position would re-map every tab the moment
/// a grant is issued or revoked. Keying by `drawerIndex` means the bar and the
/// drawer drive the same single piece of navigation state and no index can
/// shift under either of them.
class CabNavDestination {
  const CabNavDestination({required this.drawerIndex, required this.labelKey});

  /// The value written to `CabDashBoardController.drawerIndex` when this tab is
  /// tapped, and the value that makes this tab the selected one.
  final int drawerIndex;

  /// The untranslated label, rendered through `.tr` by the widget - the same
  /// strings the drawer already uses.
  final String labelKey;
}

/// The cab section's bottom navigation, as data.
///
/// Kept out of the widget so the conditional-tab behaviour - which tabs exist,
/// which one is selected, and where a tap goes - is unit-testable without
/// pumping a Scaffold.
///
/// **Every driver gets the bar**, the way every customer does in the customer
/// app. Home, Orders and Bid are always on it; My Trips joins them for a driver
/// holding a valid grant - or for every driver at once, when the admin turns on
/// `DriverTripSettings.openToAllDrivers` - and leaves again when neither holds.
///
/// It was previously built only for granted drivers, which is why the client
/// reported that the driver app "is not showing bottom bar" - no driver on the
/// live project holds a grant, so in practice the bar existed for nobody. The
/// drawer is untouched and still reaches every screen it always did; the bar is
/// a second view of the same `drawerIndex`, not a replacement.
class CabBottomNavigation {
  /// Drawer slots these destinations render. `home` and `orders` are the cab
  /// dashboard's two primary screens and already existed; `myTrips` is the slot
  /// appended in Session 3.
  static const int homeDrawerIndex = 0;
  static const int ordersDrawerIndex = 1;
  static const int myTripsDrawerIndex = 11;

  /// The Bid section's slot.
  ///
  /// **Appended, never inserted.** Slots 0-9 and 11 are taken and 10 is the
  /// drawer's Change Password fall-through, so 12 is the first free one.
  /// Renumbering to put Bid next to Home would silently repoint the drawer,
  /// `DriverMenuVisibility` and every stored index at a different screen.
  static const int bidDrawerIndex = 12;

  static const CabNavDestination home = CabNavDestination(drawerIndex: homeDrawerIndex, labelKey: 'Home');
  static const CabNavDestination orders = CabNavDestination(drawerIndex: ordersDrawerIndex, labelKey: 'Orders');
  static const CabNavDestination bid = CabNavDestination(drawerIndex: bidDrawerIndex, labelKey: 'Bid');
  static const CabNavDestination myTrips = CabNavDestination(drawerIndex: myTripsDrawerIndex, labelKey: 'My Trips');

  /// Whether this driver may use My Trips right now.
  ///
  /// Delegates to [MyTripsGate] so the bar, the drawer entry, the screen and
  /// the publish path all answer the same question the same way - including
  /// the admin's global [openToAllDrivers] switch, which grants access to every
  /// driver alongside, not instead of, the per-driver grant. It defaults to
  /// false here so a caller that has not read the settings yet gets the
  /// grant-only behaviour rather than an open door.
  static bool hasMyTrips(MyTripsAccess access, DateTime now, {bool openToAllDrivers = false}) =>
      MyTripsGate.showsInNavigation(access, now, openToAllDrivers: openToAllDrivers);

  /// Whether the bottom navigation bar is rendered at all.
  ///
  /// Always, now. Kept as a named question rather than inlined `true` because
  /// the screen and the tests both ask it, and because the embedded case (this
  /// dashboard nested inside the multi-service bar, which already has a bar of
  /// its own) is answered in the widget.
  static bool isVisible(MyTripsAccess access, DateTime now, {bool openToAllDrivers = false}) =>
      destinationsFor(access, now, openToAllDrivers: openToAllDrivers).isNotEmpty;

  /// The tabs to show, in order.
  ///
  /// Home, Orders and Bid are unconditional. My Trips is appended only while
  /// the grant is valid, so issuing or revoking one adds or removes the last
  /// tab without moving the three the driver is used to.
  ///
  /// **Bid is not behind a grant.** It is the client's own requirement - "make
  /// another section for bid same like my trips for drivers... in bottombar" -
  /// and unlike My Trips, bidding is governed by one global admin switch rather
  /// than per driver. With that switch off the tab stays where it is and the
  /// screen says why it is empty; a tab that comes and goes under the driver's
  /// thumb is worse than one that explains itself. That is also how the
  /// customer app's Bid tab behaves, so the two apps agree.
  static List<CabNavDestination> destinationsFor(MyTripsAccess access, DateTime now, {bool openToAllDrivers = false}) {
    if (!hasMyTrips(access, now, openToAllDrivers: openToAllDrivers)) {
      return const <CabNavDestination>[home, orders, bid];
    }
    return const <CabNavDestination>[home, orders, bid, myTrips];
  }

  /// Which tab is selected, given the drawer slot currently on screen.
  ///
  /// The drawer can reach screens the bar does not carry - Wallet, Inbox,
  /// Verification, the legal pages. Those resolve to 0 so `currentIndex` is
  /// always a valid position: `BottomNavigationBar` asserts on an out-of-range
  /// index, and the body keeps showing whatever the drawer chose.
  static int currentIndexFor(List<CabNavDestination> destinations, int drawerIndex) {
    if (destinations.isEmpty) return 0;
    for (int i = 0; i < destinations.length; i++) {
      if (destinations[i].drawerIndex == drawerIndex) return i;
    }
    return 0;
  }

  /// Where a tap on tab [position] should send the drawer.
  ///
  /// Out-of-range positions fall back to Home rather than throwing, so a tap
  /// that races a revocation cannot crash the screen.
  static int drawerIndexFor(List<CabNavDestination> destinations, int position) {
    if (position < 0 || position >= destinations.length) return homeDrawerIndex;
    return destinations[position].drawerIndex;
  }

  /// The tab index that is safe to render, given a stored index and how many
  /// tabs currently exist.
  ///
  /// Used by the multi-service bar, whose selected tab **is** stored state: if
  /// the grant lapses while the driver is on the My Trips tab, the stored index
  /// points past the end, and both `IndexedStack` and `BottomNavigationBar`
  /// assert on that. Falling back to the first tab keeps the driver on a valid
  /// screen instead of crashing.
  static int safeTabIndex(int storedIndex, int tabCount) {
    if (tabCount <= 0) return 0;
    if (storedIndex < 0 || storedIndex >= tabCount) return 0;
    return storedIndex;
  }

  /// The drawer slot to fall back to when the current one is no longer allowed.
  static int safeDrawerIndexFor({
    required MyTripsAccess access,
    required DateTime now,
    required int drawerIndex,
    bool openToAllDrivers = false,
  }) {
    if (drawerIndex == myTripsDrawerIndex && !hasMyTrips(access, now, openToAllDrivers: openToAllDrivers)) {
      return homeDrawerIndex;
    }
    return drawerIndex;
  }
}
