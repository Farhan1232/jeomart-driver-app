import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/app/cab_screen/my_trips_screen.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/models/driver_trip_model.dart';
import 'package:driver/services/driver_trip_service.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/utils/driver_trip_state.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/upcoming_trip.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// The driver's scheduled trip, on the screen they actually sit on.
///
/// The cab home screen never read `driver_trips`, so a trip the driver posted
/// existed only inside My Trips: at 6am, on the screen that was open, there was
/// nothing to say a trip was due. This puts the one trip that is current - see
/// [UpcomingTrip] for the window - over the map, and taps through to My Trips.
///
/// Costs nothing for a driver who cannot post trips: [Constant.hasMyTripsAccess]
/// is checked before the listener is opened, and the widget renders an empty box
/// with no read at all.
///
/// Renders [SizedBox.shrink] whenever there is no current trip, which is what
/// lets it be dropped into the map overlay without taking any height - the
/// lesson of the home screen's `Stack`, which collapses to nothing if it is
/// asked to size itself to its children.
class UpcomingTripBanner extends StatefulWidget {
  const UpcomingTripBanner({super.key, required this.isDark});

  final bool isDark;

  /// How many of the driver's most recent trips to watch.
  ///
  /// The query is `myTripsQuery` unchanged - one equality plus the existing
  /// sort - so this needs no index My Trips does not already use. Twenty is the
  /// same page size My Trips loads, and a trip inside its window is by
  /// definition a recent one.
  static const int watchLimit = 20;

  @override
  State<UpcomingTripBanner> createState() => _UpcomingTripBannerState();
}

class _UpcomingTripBannerState extends State<UpcomingTripBanner> {
  static final DateFormat _timeFormat = DateFormat('dd MMM, hh:mm a');

  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;

  /// Redraws the banner as the clock moves, so a trip appears when its window
  /// opens and the "in 25 min" line stays true without the driver touching
  /// anything. One minute is the finest unit the banner shows.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _followTrips();
    // The clock ticks whether or not the driver may post trips today.
    //
    // It is what keeps the "in 25 min" line true, and it is also how the banner
    // notices an access granted - or put back by the server's safety net -
    // while this screen was already open. The access used to be read once here,
    // so a driver who was granted access with the app open saw nothing until
    // the screen was built again; on 16 September that looked like the banner
    // had disappeared. A driver who cannot post trips still reads nothing from
    // Firestore: the tick only re-checks a value already in memory.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(_followTrips);
    });
  }

  /// Opens the trip stream while the driver may post trips, and lets it go when
  /// they may not.
  ///
  /// The rule is unchanged - [Constant.hasMyTripsAccess], the same one the My
  /// Trips tab uses - it is simply re-read instead of read once. The stream is
  /// created only when there is none, so a rebuild never re-subscribes.
  void _followTrips() {
    final String uid = FireStoreUtils.getCurrentUid();
    final bool allowed = uid.isNotEmpty && Constant.hasMyTripsAccess;
    if (allowed && _stream == null) {
      _stream = DriverTripService.myTripsQuery(uid).limit(UpcomingTripBanner.watchLimit).snapshots();
    } else if (!allowed && _stream != null) {
      _stream = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tick = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-checked as the screen draws as well, so the banner is there the moment
    // the access is, without waiting for the next tick.
    _followTrips();
    final Stream<QuerySnapshot<Map<String, dynamic>>>? stream = _stream;
    if (stream == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot) {
        final QuerySnapshot<Map<String, dynamic>>? data = snapshot.data;
        if (data == null) return const SizedBox.shrink();

        final List<DriverTripModel> trips = <DriverTripModel>[];
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in data.docs) {
          try {
            trips.add(DriverTripModel.fromJson(doc.data()));
          } catch (error) {
            // One unreadable trip must not take the banner - or the map - down.
            log('UpcomingTripBanner: skipping trip ${doc.id} :: $error');
          }
        }

        final DriverTripModel? trip = UpcomingTrip.pick(trips, DateTime.now());
        if (trip == null) return const SizedBox.shrink();

        return _banner(trip);
      },
    );
  }

  Widget _banner(DriverTripModel trip) {
    final bool isDark = widget.isDark;
    final UpcomingTripTiming timing = UpcomingTrip.timingFor(trip, DateTime.now());
    final bool booked = trip.status == DriverTripStatus.booked;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 10, right: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Get.to(() => const MyTripsScreen()),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppThemeData.grey800 : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: booked ? AppThemeData.success400 : AppThemeData.primary300, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                Icon(
                  booked ? Icons.event_available : Icons.schedule,
                  size: 22,
                  color: booked ? AppThemeData.success400 : AppThemeData.primary300,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _headline(timing, booked),
                        style: AppThemeData.semiBoldTextStyle(
                          fontSize: 14,
                          color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "${trip.fromAddress ?? ''} → ${trip.toAddress ?? ''}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppThemeData.regularTextStyle(
                          fontSize: 12,
                          color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                        ),
                      ),
                      Text(
                        trip.tripDateTime == null ? '' : _timeFormat.format(trip.tripDateTime!.toDate()),
                        style: AppThemeData.regularTextStyle(
                          fontSize: 12,
                          color: isDark ? AppThemeData.grey400 : AppThemeData.grey500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 22, color: isDark ? AppThemeData.grey400 : AppThemeData.grey500),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The timing line, assembled from whole translatable phrases rather than
  /// from fragments concatenated around a number.
  String _headline(UpcomingTripTiming timing, bool booked) {
    final String subject = booked ? "Your booked trip".tr : "Your posted trip".tr;
    switch (timing.when) {
      case UpcomingTripWhen.inMinutes:
        return "$subject · ${'in'.tr} ${timing.value} ${'min'.tr}";
      case UpcomingTripWhen.inHours:
        return "$subject · ${'in'.tr} ${timing.value} ${'h'.tr}";
      case UpcomingTripWhen.due:
        return "$subject · ${'starting now'.tr}";
      case UpcomingTripWhen.underway:
        return "$subject · ${'departed'.tr} ${timing.value} ${'min ago'.tr}";
    }
  }
}
