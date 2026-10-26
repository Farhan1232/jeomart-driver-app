import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin-granted, time-limited permission for one driver to use **My Trips**.
///
/// Stored as a nested map on the driver's existing `users/{driverId}` document
/// under [fieldName], so no new collection and no new lookup is introduced:
/// every screen in the driver app already has that document in hand.
///
/// ```
/// users/{driverId}.myTripsAccess = {
///   granted:      true,
///   durationDays: 7,
///   grantedAt:    <server Timestamp>,
///   expiresAt:    <grantedAt + durationDays, computed from the SERVER value>,
///   grantedBy:    "<admin uid>",
///   revokedAt:    null,
/// }
/// ```
///
/// It is deliberately **not** a boolean. The client asked for 1 day, 2 days,
/// 10 days "or any duration up to 30 days", so the grant records how long it
/// was for, when it started and when it ends, and the app decides validity
/// from the end instant rather than from a flag somebody has to remember to
/// turn off.
///
/// `grantedAt` is written by the admin panel with
/// `FieldValue.serverTimestamp()`, and `expiresAt` is then derived from the
/// value the server resolved - never from the admin's browser clock and never
/// from the driver's device clock. The scheduled maintenance script closes
/// out expired grants on the server for the same reason; the checks in this
/// class are what make the app's UI react immediately.
class MyTripsAccess {
  const MyTripsAccess({
    this.granted = false,
    this.durationDays = 0,
    this.grantedAt,
    this.expiresAt,
    this.revokedAt,
    this.grantedBy,
  });

  /// The map field on `users/{driverId}`.
  static const String fieldName = 'myTripsAccess';

  /// The shortest and longest grant the admin may issue, as briefed.
  static const int minDurationDays = 1;
  static const int maxDurationDays = 30;

  /// No access at all. What a driver with no grant, an unreadable document or
  /// a malformed map reads as - so a failure can never open the feature up.
  static const MyTripsAccess none = MyTripsAccess();

  final bool granted;
  final int durationDays;
  final Timestamp? grantedAt;
  final Timestamp? expiresAt;
  final Timestamp? revokedAt;
  final String? grantedBy;

  /// Reads the map off a `users/{driverId}` document.
  ///
  /// Every field is defensive in the same way `BiddingSettings` is: this
  /// project stores numbers as strings in several older documents, and the
  /// admin panel is the only writer, so a hand-edited value must not throw.
  factory MyTripsAccess.fromUserJson(Map<String, dynamic>? userJson) {
    if (userJson == null) return none;
    return MyTripsAccess.fromJson(userJson[fieldName]);
  }

  factory MyTripsAccess.fromJson(Object? raw) {
    if (raw is! Map) return none;
    return MyTripsAccess(
      granted: _readBool(raw['granted']),
      durationDays: (_readNum(raw['durationDays']) ?? 0).round(),
      grantedAt: _readTimestamp(raw['grantedAt']),
      expiresAt: _readTimestamp(raw['expiresAt']),
      revokedAt: _readTimestamp(raw['revokedAt']),
      grantedBy: raw['grantedBy']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'granted': granted,
        'durationDays': durationDays,
        'grantedAt': grantedAt,
        'expiresAt': expiresAt,
        'revokedAt': revokedAt,
        'grantedBy': grantedBy,
      };

  /// Whether the driver may use My Trips right now.
  ///
  /// All four conditions have to hold: the grant exists, it was not revoked by
  /// hand, it carries an end instant, and that instant is still in the future.
  /// A grant whose `expiresAt` never got written (the admin panel's write was
  /// interrupted between its two steps) is treated as **not** valid.
  bool isValidAt(DateTime now) {
    if (!granted) return false;
    if (revokedAt != null) return false;
    final Timestamp? end = expiresAt;
    if (end == null) return false;
    return now.isBefore(end.toDate());
  }

  /// Granted at some point, but no longer usable.
  bool isExpiredAt(DateTime now) => granted && revokedAt == null && expiresAt != null && !now.isBefore(expiresAt!.toDate());

  /// Whether an admin revoked it by hand rather than it running out.
  bool get isRevoked => revokedAt != null;

  /// Whole days left, rounded up, or 0 once it has run out.
  int daysRemainingAt(DateTime now) {
    if (!isValidAt(now)) return 0;
    final Duration left = expiresAt!.toDate().difference(now);
    if (left.inSeconds <= 0) return 0;
    return (left.inSeconds / Duration.secondsPerDay).ceil();
  }

  /// Whether the admin may issue a grant of this length.
  ///
  /// 0 days and anything past 30 are refused, and so is a fractional value -
  /// the panel offers whole days only, and a "1.5 day" grant has no meaning
  /// in the expiry arithmetic.
  static bool isValidDuration(Object? days) {
    final num? value = _readNum(days);
    if (value == null) return false;
    if (value != value.roundToDouble()) return false;
    return value >= minDurationDays && value <= maxDurationDays;
  }

  /// The end instant of a grant of [durationDays] starting at [grantedAt].
  ///
  /// [grantedAt] is the value the **server** resolved, which is what keeps the
  /// window off both the admin's and the driver's clock.
  static Timestamp expiryFor({required DateTime grantedAt, required int durationDays}) =>
      Timestamp.fromDate(grantedAt.add(Duration(days: durationDays)));

  static bool _readBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) return raw.toLowerCase() == 'true' || raw == '1';
    return false;
  }

  static num? _readNum(Object? raw) {
    if (raw is num) return raw;
    if (raw is String) return num.tryParse(raw.trim());
    return null;
  }

  static Timestamp? _readTimestamp(Object? raw) {
    if (raw is Timestamp) return raw;
    if (raw is DateTime) return Timestamp.fromDate(raw);
    return null;
  }
}

/// The three places the My Trips grant is consulted, named.
///
/// The driver app asks these questions in three different files - the drawer
/// builds an entry, the dashboard decides whether to bounce the driver off the
/// screen, and the service decides whether a publish may reach Firestore. They
/// are collected here so all three answer identically and so the tests assert
/// the predicate the app actually calls rather than a copy of it.
class MyTripsGate {
  /// Whether the My Trips entry appears in the driver's navigation.
  static bool showsInNavigation(MyTripsAccess access, DateTime now, {bool openToAllDrivers = false}) =>
      _allowed(access, now, openToAllDrivers);

  /// Whether the driver may stay on the My Trips screen.
  static bool canOpenMyTrips(MyTripsAccess access, DateTime now, {bool openToAllDrivers = false}) =>
      _allowed(access, now, openToAllDrivers);

  /// Whether a publish attempt may reach Firestore at all.
  ///
  /// Both halves have to hold: permission, and a trip that passes validation.
  /// This is the function the write path consults, so a driver who may not
  /// post is refused by the write and not only by the button they cannot see.
  static bool canPublishTrip({
    required MyTripsAccess access,
    required DateTime now,
    required List<Object> validationErrors,
    bool openToAllDrivers = false,
  }) =>
      _allowed(access, now, openToAllDrivers) && validationErrors.isEmpty;

  /// The one rule, so the three questions above cannot drift apart.
  ///
  /// **OR, not AND.** The admin's global switch
  /// (`DriverTripSettings.openToAllDrivers`) opens the feature to every driver;
  /// a per-driver grant opens it to that driver. Either is sufficient, so:
  ///
  /// * switch off, grant valid -> allowed, exactly as before this existed;
  /// * switch off, no grant    -> refused, exactly as before this existed;
  /// * switch on,  grant valid -> allowed;
  /// * switch on,  no grant, or a grant that expired or was revoked -> allowed,
  ///   because the switch is the broader permission and an individual grant
  ///   running out was never meant to be a *ban*.
  ///
  /// [openToAllDrivers] defaults to false at every entry point, so a settings
  /// document that is missing, empty or unreadable leaves the gate shut rather
  /// than opening the feature to everybody.
  static bool _allowed(MyTripsAccess access, DateTime now, bool openToAllDrivers) =>
      openToAllDrivers || access.isValidAt(now);
}
