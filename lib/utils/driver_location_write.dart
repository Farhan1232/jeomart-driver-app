import 'package:driver/models/user_model.dart';

/// What a driver's position update writes, and which copy of the profile
/// decides whether it is written.
///
/// Every dashboard's GPS listener used to read the driver's whole profile -
/// from `UserCache` when a copy up to two minutes old was there - set the new
/// position on it and save the **whole** profile back with `updateUser`: a
/// read, a `set(merge)` and an `update` per movement. Whatever had changed on
/// the document in between was overwritten with the old copy: a ride request
/// the dispatcher had just offered was deleted, one it had taken back was put
/// back, a finished ride reappeared on `inProgressOrderID`, and the wallet
/// balance was rewritten from before the last credit.
///
/// A position update now writes the position and nothing else, in one
/// `update` - which also cannot re-create a document the admin has deleted.
class DriverLocationWrite {
  const DriverLocationWrite._();

  /// The fields a position update changes.
  ///
  /// Dotted paths, so the coordinates merge into `location` exactly as the old
  /// `set(merge)` merged them. `?? 0.0` and the missing heading are what the
  /// old save wrote: `removeNulls` dropped a null `rotation`.
  static Map<String, Object> fields({double? latitude, double? longitude, num? heading}) {
    return <String, Object>{
      'location.latitude': latitude ?? 0.0,
      'location.longitude': longitude ?? 0.0,
      if (heading != null) 'rotation': heading,
    };
  }

  /// The profile the "is this driver available?" check is made on.
  ///
  /// The dashboard's own `users` listener keeps [live] current, so it is used
  /// once it has delivered. Before that - a fix can arrive ahead of the first
  /// snapshot - the profile is [read] as it always was, so the first position
  /// of a session is not skipped.
  static Future<UserModel?> profileFor(UserModel live, Future<UserModel?> Function() read) async {
    if (live.id != null) return live;
    return read();
  }
}
