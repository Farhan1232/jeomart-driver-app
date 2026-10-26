/// Per-city vehicle types.
///
/// The admin panel can tick the cities (published `zone` documents) a cab or
/// rental vehicle type is offered in; they are saved as `zoneIds`. Nothing
/// ticked - and every vehicle type saved before this existed - means every
/// city, which is how the app has always behaved.
///
/// A driver's city is the zone on their profile. When it is not known yet the
/// list is left exactly as it was read.
class CityFilter {
  const CityFilter._();

  /// `zoneIds` as saved by the panel, or null when there is none.
  static List<String>? parseZoneIds(dynamic raw) {
    if (raw is! List) return null;
    return raw.whereType<String>().where((String id) => id.isNotEmpty).toList();
  }

  /// Is an item with these [zoneIds] offered in [zoneId]?
  static bool allows(List<String>? zoneIds, String? zoneId) {
    if (zoneIds == null || zoneIds.isEmpty) return true;
    if (zoneId == null || zoneId.isEmpty) return true;
    return zoneIds.contains(zoneId);
  }

  /// The items offered in [zoneId]. The one with [keepId] - the vehicle a
  /// driver already has saved - always stays, so nobody loses their vehicle
  /// because the admin changed the cities later.
  static List<T> keep<T>(List<T> items, String? zoneId, {required List<String>? Function(T) zoneIdsOf, required String? Function(T) idOf, String? keepId}) {
    if (zoneId == null || zoneId.isEmpty) return items;
    return items.where((T item) => allows(zoneIdsOf(item), zoneId) || (keepId != null && keepId.isNotEmpty && idOf(item) == keepId)).toList();
  }
}
