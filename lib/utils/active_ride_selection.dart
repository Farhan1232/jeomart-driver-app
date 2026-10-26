import 'package:driver/constant/constant.dart';

/// Which ride the cab home screen follows, decided from the driver's own
/// document and from what the screen has already seen end.
///
/// Pulled out of `CabHomeController.getCurrentOrder` so the stale-ride cases
/// can be exercised without Firebase.
class ActiveRideSelection {
  const ActiveRideSelection({required this.rideId, required this.endedStillListed});

  /// The ride to follow, or null for none.
  final String? rideId;

  /// Rides still on `inProgressOrderID` that the screen has already seen end.
  /// They are not followed; the caller takes them off the document.
  final List<String> endedStillListed;

  /// Statuses after which a ride is never in progress again.
  static const List<String> endedStatuses = <String>[
    Constant.orderCompleted,
    Constant.orderCancelled,
    Constant.orderRejected,
  ];

  static bool hasEnded(Object? status) => endedStatuses.contains(status?.toString());

  /// The first in-progress ride the screen has not seen end; failing that,
  /// the request waiting on the driver's document.
  ///
  /// The rule used to be "the first in-progress ride, whatever it is". So a
  /// ride that had already ended but was written back onto the document - by
  /// a write built from a copy read before it ended - was followed again, and
  /// because the screen was "already following" it nothing else was looked
  /// at: not the empty screen, and not a new request the dispatcher had just
  /// put on the same document. The driver looked free and was never shown
  /// the ride, until an app restart re-read the ride and noticed it was over.
  static ActiveRideSelection select({
    required List<dynamic>? inProgress,
    required String? pendingRequestId,
    Set<String> endedRideIds = const <String>{},
  }) {
    final List<String> listed = <String>[
      for (final dynamic entry in inProgress ?? const <dynamic>[])
        if (entry != null && entry.toString().isNotEmpty) entry.toString(),
    ];
    final List<String> ended = listed.where(endedRideIds.contains).toList();
    final List<String> live = listed.where((String id) => !endedRideIds.contains(id)).toList();

    String? rideId;
    if (live.isNotEmpty) {
      rideId = live.first;
    } else if (pendingRequestId != null && pendingRequestId.isNotEmpty && !endedRideIds.contains(pendingRequestId)) {
      // A request for a ride already seen ending is a leftover, not a request:
      // following it would re-open a listener on every snapshot of the
      // driver's document just to be told again that the ride is over.
      rideId = pendingRequestId;
    }
    return ActiveRideSelection(rideId: rideId, endedStillListed: ended);
  }
}
