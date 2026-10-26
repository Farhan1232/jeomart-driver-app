import '../models/driver_trip_model.dart';
import 'driver_trip_state.dart';

/// Which of the driver's posted trips belongs on their main screen right now.
///
/// The client's requirement is that "the scheduled trip appears correctly on the
/// driver's main screen at the trip time". A trip lived only in My Trips before
/// this, so a driver who posted an intercity run for 6am had nothing on the
/// screen they actually sit on all day to remind them of it - the cab home
/// screen never read `driver_trips` at all.
///
/// A pure function, with the clock passed in, so the window is exercised by
/// tests rather than by waiting for a departure time to arrive.
class UpcomingTrip {
  /// How long before departure the trip starts being shown.
  ///
  /// Two hours: long enough that the driver sees an early-morning run when they
  /// open the app, short enough that a trip posted for next week is not sitting
  /// over the map for days. Trips further out are still in My Trips, which is
  /// the full list.
  static const Duration leadIn = Duration(hours: 2);

  /// How long after departure it keeps being shown.
  ///
  /// Six hours, which is `DEFAULT_COMPLETION_GRACE_HOURS` in
  /// `driverTripsMaintenance.js` - so the banner is on screen for exactly as
  /// long as the trip is still the driver's to finish, and disappears at about
  /// the moment the server sweep would have completed it anyway.
  static const Duration holdOver = Duration(hours: 6);

  /// Whether [trip] is inside its window at [now].
  ///
  /// A finished trip is never shown, whatever its time says: a cancelled or
  /// completed journey is history, and history belongs in My Trips. A trip with
  /// no departure time cannot have a window at all.
  static bool isCurrent(DriverTripModel trip, DateTime now) {
    if (DriverTripStatus.isFinished(trip.status)) return false;
    // `effectiveStatusAt` is what the rest of the app trusts over the stored
    // status: an active trip sitting past its visibility window is expired even
    // though the sweep has not said so yet, and an expired trip is not one the
    // driver is about to drive.
    if (DriverTripStatus.isFinished(trip.effectiveStatusAt(now))) return false;

    final DateTime? departure = trip.tripDateTime?.toDate();
    if (departure == null) return false;

    return !now.isBefore(departure.subtract(leadIn)) && !now.isAfter(departure.add(holdOver));
  }

  /// The one trip to put on the main screen, or null when there is none.
  ///
  /// The earliest departure inside the window wins, because that is the journey
  /// the driver is on or about to start. A booked trip is preferred over an
  /// unreserved one departing at the same instant - the booked one has a
  /// customer waiting, and it is the only one the driver can complete.
  static DriverTripModel? pick(Iterable<DriverTripModel> trips, DateTime now) {
    DriverTripModel? best;
    for (final DriverTripModel trip in trips) {
      if (!isCurrent(trip, now)) continue;
      if (best == null) {
        best = trip;
        continue;
      }
      final DateTime a = trip.tripDateTime!.toDate();
      final DateTime b = best.tripDateTime!.toDate();
      if (a.isBefore(b)) {
        best = trip;
      } else if (a.isAtSameMomentAs(b) &&
          trip.status == DriverTripStatus.booked &&
          best.status != DriverTripStatus.booked) {
        best = trip;
      }
    }
    return best;
  }

  /// How the banner describes the trip's timing at [now].
  ///
  /// Returned as a key plus a number rather than a formatted string so the
  /// screen owns the wording and `.tr` still applies to a whole phrase.
  static UpcomingTripTiming timingFor(DriverTripModel trip, DateTime now) {
    final DateTime? departure = trip.tripDateTime?.toDate();
    if (departure == null) return const UpcomingTripTiming(UpcomingTripWhen.due, 0);

    if (now.isBefore(departure)) {
      final int minutes = departure.difference(now).inMinutes;
      // Zero minutes left reads as due, not as "in 0 min".
      if (minutes <= 0) return const UpcomingTripTiming(UpcomingTripWhen.due, 0);
      if (minutes < 60) return UpcomingTripTiming(UpcomingTripWhen.inMinutes, minutes);
      return UpcomingTripTiming(UpcomingTripWhen.inHours, departure.difference(now).inHours);
    }

    final int sinceMinutes = now.difference(departure).inMinutes;
    if (sinceMinutes < 1) return const UpcomingTripTiming(UpcomingTripWhen.due, 0);
    return UpcomingTripTiming(UpcomingTripWhen.underway, sinceMinutes);
  }
}

/// The shape of the timing line on the banner.
enum UpcomingTripWhen {
  /// Departure is less than an hour away, and [UpcomingTripTiming.value] is
  /// that many minutes.
  inMinutes,

  /// Departure is an hour or more away, and the value is that many hours.
  inHours,

  /// Departure time has arrived, to the minute.
  due,

  /// Departure time has passed, and the value is how many minutes ago.
  underway,
}

class UpcomingTripTiming {
  const UpcomingTripTiming(this.when, this.value);

  final UpcomingTripWhen when;

  /// Minutes or hours, depending on [when]; zero when [when] is
  /// [UpcomingTripWhen.due].
  final int value;
}
