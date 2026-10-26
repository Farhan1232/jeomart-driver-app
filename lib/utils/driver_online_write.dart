/// The driver's Available Status, written the way the Admin Panel writes it.
///
/// The switch used to save the **whole** profile (`updateUser`), and so did the
/// launch, push-token and order paths. Whichever of those wrote last decided
/// the status, and one carrying an older copy silently put the driver back
/// offline seconds after they had gone online - while the Admin Panel, which
/// updates this single field, always stuck.
///
/// So the status is now one field, changed only by the switch (and by the two
/// account-creation paths, which still write the starting value).
library;

class DriverOnlineWrite {
  const DriverOnlineWrite._();

  /// The field the Admin Panel's own Online switch updates
  /// (`drivers/index.blade.php`: `update({'isActive': …})`).
  static const String field = 'isActive';

  /// The single-field update a status change sends.
  static Map<String, Object> fields({required bool isOnline}) {
    return <String, Object>{field: isOnline};
  }
}
