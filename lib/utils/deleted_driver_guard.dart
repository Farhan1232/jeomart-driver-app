import 'dart:async';

/// A driver the Admin Panel has deleted stays deleted on this phone too.
///
/// The panel records every driver it deletes in `deleted_drivers/{uid}` before
/// it removes their `users` document. This app saves the driver's whole
/// in-memory profile with `set(..., merge: true)` - from the location stream,
/// the online switch and the ride screens - and on a document that is gone
/// that call creates it again. An app left open after the deletion therefore
/// put the driver straight back into Live Tracking and the dispatchers' pool.
///
/// `FireStoreUtils.updateUser` asks this guard before every save. The guard
/// follows the signed-in driver's own deletion record with one listener - one
/// read when it opens, nothing per save - and once the record exists it
/// refuses the save and ends the session through `onDeleted`.
///
/// Fails open: if the record cannot be read, saves go ahead exactly as before,
/// and the server-side trigger still removes anything written back.
class DeletedDriverGuard {
  DeletedDriverGuard._();

  /// The collection the Admin Panel writes (`public/js/driver-deletion.js`).
  static const String collection = 'deleted_drivers';

  static String? _followedUid;
  static StreamSubscription<bool>? _subscription;
  static final Set<String> _deletedUids = <String>{};

  /// Whether [uid] has been seen with a deletion record in this app session.
  ///
  /// Kept per uid, so a stream still holding the deleted driver's profile
  /// cannot write it back after someone else signs in on the same phone.
  static bool isDeleted(String? uid) => uid != null && _deletedUids.contains(uid);

  /// Follows `deleted_drivers/{uid}`. Calling it again for the same uid does
  /// nothing, so it is cheap to call before every save.
  static void follow(
    String uid, {
    required Stream<bool> Function(String uid) recordExists,
    required void Function(String uid) onDeleted,
  }) {
    if (uid.isEmpty || uid == _followedUid) return;
    _subscription?.cancel();
    _followedUid = uid;
    _subscription = recordExists(uid).listen(
      (bool exists) {
        if (exists) {
          if (_deletedUids.add(uid)) onDeleted(uid);
        } else {
          // The admin restored the driver by removing the record.
          _deletedUids.remove(uid);
        }
      },
      onError: (Object _) {},
    );
  }

  /// Stops following and forgets everything. For tests.
  static Future<void> reset() async {
    await _subscription?.cancel();
    _subscription = null;
    _followedUid = null;
    _deletedUids.clear();
  }
}
