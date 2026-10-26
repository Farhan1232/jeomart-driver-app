import 'dart:async';
import 'dart:developer';

import 'package:driver/constant/constant.dart';
import 'package:driver/utils/map_start_location.dart';
import 'package:driver/utils/preferences.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// How far from `0, 0` a coordinate has to be before it counts as a place.
///
/// 0.05 degrees is roughly five kilometres of open Atlantic south of Ghana.
/// Nothing legitimate is ever there, and it has to be a band rather than an
/// exact-zero test because the placeholder this project writes is
/// `0.01, 0.01`, which an `== 0.0` check waves straight through.
const double _nullIslandMargin = 0.05;

/// Whether a coordinate is somewhere a driver could actually be.
///
/// **This is the bug the whole file exists for.** A driver's own
/// `users/<uid>.location` is written only when the platform location stream
/// fires, and that stream is throttled to `settings/DriverNearBy`'s
/// `driverLocationUpdate` metres — **1000** on this project. A driver who has
/// not travelled a kilometre with the app open therefore has no location on
/// their document at all: five of the forty live driver documents have no
/// `location` field, and three more hold the placeholder `0.01, 0.01`.
///
/// Read through `?? 0.0` those become `0, 0` and `0.01, 0.01`. Both are open
/// ocean, and `FlutterMap` centred there draws **one flat `#AAD3DF` tile at
/// every zoom past nine** — no coastline, no road, no label, standard deviation
/// zero. That is precisely the screen the client reports as "the map is not
/// loading", and because `MapOptions.initialCenter` is read once it could never
/// recover.
///
/// So nothing centres a map, places a marker or draws a route on a point that
/// does not pass this.
bool isRealMapPoint(num? latitude, num? longitude) {
  if (latitude == null || longitude == null) return false;
  final double lat = latitude.toDouble();
  final double lng = longitude.toDouble();
  if (!lat.isFinite || !lng.isFinite) return false;
  if (lat.abs() > 90 || lng.abs() > 180) return false;
  return lat.abs() > _nullIslandMargin || lng.abs() > _nullIslandMargin;
}

/// The point held by anything with `latitude` and `longitude` — a `UserLocation`,
/// a `LocationData`, an order's source — or `null` when it is not a real place.
///
/// Deliberately takes `dynamic`: the four shapes this is called with share no
/// supertype, and every one of them was previously unpacked with its own
/// `?? 0.0`, which is what turned "no location" into Null Island.
LatLng? realMapPoint(dynamic holder) {
  if (holder == null) return null;
  try {
    final num? lat = _asNumber(holder.latitude);
    final num? lng = _asNumber(holder.longitude);
    if (!isRealMapPoint(lat, lng)) return null;
    return LatLng(lat!.toDouble(), lng!.toDouble());
  } catch (error) {
    // The holder has no latitude/longitude at all.
    return null;
  }
}

num? _asNumber(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

/// Points a `flutter_map` at a coordinate, including when the coordinate
/// arrives before the map does.
///
/// `MapController.move` throws until the `FlutterMap` has been laid out once.
/// Both driver home controllers wrapped that call in `try { } catch (_) { }`,
/// so a fix that landed a frame too early was **silently dropped** and the map
/// kept whatever `initialCenter` had guessed. This holds the point instead and
/// applies it from `MapOptions.onMapReady`.
class DriverMapCentre {
  DriverMapCentre(this._osm, {this.onGoogleCamera});

  final flutter_map.MapController _osm;

  /// Google Maps keeps its own camera, so it is moved alongside. Only called
  /// with points that have already passed [isRealMapPoint].
  final void Function(LatLng point)? onGoogleCamera;

  bool _ready = false;
  LatLng? _pending;
  LatLng? _last;
  double _zoom = 16;

  /// The freshest real point this has been given, whether or not the map has
  /// drawn it yet. This is what `initialCenter` should be built on.
  LatLng? get lastPoint => _last;

  /// Whether the map has been laid out and will accept a move.
  bool get isReady => _ready;

  /// Wired to `MapOptions.onMapReady`.
  void mapReady() {
    _ready = true;
    _apply();
  }

  /// Shows [point], now or as soon as the map exists.
  ///
  /// Returns false, and does nothing at all, for a point that is not a real
  /// place — the single check that keeps the Atlantic off the screen.
  bool moveTo(LatLng point, {double zoom = 16}) {
    if (!isRealMapPoint(point.latitude, point.longitude)) return false;
    _last = point;
    _pending = point;
    _zoom = zoom;
    _apply();
    onGoogleCamera?.call(point);
    return true;
  }

  void _apply() {
    final LatLng? target = _pending;
    if (target == null || !_ready) return;
    try {
      _osm.move(target, _zoom);
      _pending = null;
    } catch (error) {
      // Still not laid out. Kept, not dropped: onMapReady will run it.
      log('DriverMapCentre: map not ready for $target :: $error');
    }
  }
}

/// Where the driver actually is, for the map to follow.
///
/// Replaces a single un-retried `Geolocator.getCurrentPosition()` fired from
/// `onInit`. That call had no permission check, no timeout and no fallback, and
/// since the home section is kept alive across tab switches its controller is
/// never rebuilt — so when it threw (the permission dialog is still open at
/// that moment, because the dashboard is only just raising it) the screen had
/// no location for the rest of the session. Switching tabs used to rebuild the
/// controller and quietly retry, which is why the map "worked once a ride came
/// in" and stopped working when the sections were made to survive.
/// The best coordinate available **without awaiting anything**, for any screen
/// that needs one before its first frame.
///
/// Both sources are synchronous: this session's own fix, then the one saved on
/// disk last run. Screens that hold a [DriverMapLocation] reach this through
/// `seed()`; the ones that only need a starting point — the location pickers —
/// call it directly rather than constructing a location stream they will never
/// use.
LatLng? driverMapSeed() {
  final LatLng? live = realMapPoint(Constant.locationDataFinal);
  if (live != null) return live;

  final MapStartLocation? saved = MapStartLocationStore(
    read: Preferences.getString,
    write: Preferences.setString,
  ).saved();
  if (saved != null && isRealMapPoint(saved.latitude, saved.longitude)) {
    return LatLng(saved.latitude, saved.longitude);
  }
  return null;
}

class DriverMapLocation {
  DriverMapLocation({required this.onFix});

  /// Called for every position worth drawing, the seed included. Never called
  /// with a point that fails [isRealMapPoint].
  final void Function(LatLng point) onFix;

  StreamSubscription<Position>? _stream;
  bool _started = false;

  /// Whether a real device position has arrived. Once it has, a stale
  /// Firestore document must not pull the map back.
  bool get hasDeviceFix => _hasDeviceFix;
  bool _hasDeviceFix = false;

  MapStartLocationStore get _store => MapStartLocationStore(
        read: Preferences.getString,
        write: Preferences.setString,
      );

  /// The best coordinate available **without awaiting anything**.
  ///
  /// Read before the first frame, because `initialCenter` is read once and a
  /// future — even one that completes immediately — resolves a frame too late.
  /// Both sources are synchronous: this session's own fix, then the one saved
  /// on disk last run.
  LatLng? seed() => driverMapSeed();

  /// Seeds the map, then keeps it on the driver.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    final LatLng? seeded = seed();
    if (seeded != null) onFix(seeded);

    if (!await _waitForPermission()) return;

    await _publishLastKnown();
    _listen();
    unawaited(_publishFirstFix());
  }

  /// Tries again after a [start] that gave up.
  ///
  /// [start] gives up in one case: permission was never granted while it was
  /// waiting. Nothing else in the app would ever ask again, so the driver's
  /// "my location" button routes here — it is the one control they will press
  /// when the map is not where they are, and it should be able to fix it.
  Future<void> retryIfIdle() async {
    if (_hasDeviceFix || _stream != null) return;
    _started = false;
    await start();
  }

  Future<void> dispose() async {
    await _stream?.cancel();
    _stream = null;
  }

  /// Waits for the permission the dashboard is already asking for.
  ///
  /// Deliberately *checks* first rather than asking: `CabDashBoardController`
  /// raises its own dialog at the same moment, and two simultaneous requests
  /// make Android throw `PermissionRequestInProgressException` at whichever
  /// arrives second. Only if nobody has asked after twenty seconds does this
  /// ask itself, so the map still works on any path that skips the dashboard.
  Future<bool> _waitForPermission() async {
    for (int attempt = 0; attempt < 10; attempt++) {
      if (await _granted()) return true;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    try {
      final LocationPermission asked = await Geolocator.requestPermission();
      return asked == LocationPermission.always || asked == LocationPermission.whileInUse;
    } catch (error) {
      log('DriverMapLocation: permission request failed :: $error');
      return false;
    }
  }

  Future<bool> _granted() async {
    try {
      final LocationPermission permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
    } catch (error) {
      log('DriverMapLocation: permission check failed :: $error');
      return false;
    }
  }

  /// The platform's cached fix. Returns immediately and does not turn the GPS
  /// on, so this is what puts a first-run driver on their own street in the
  /// same second the screen opens.
  Future<void> _publishLastKnown() async {
    try {
      final Position? position = await Geolocator.getLastKnownPosition();
      if (position != null) _publish(position);
    } catch (error) {
      log('DriverMapLocation: last known failed :: $error');
    }
  }

  /// A real fix. Bounded, because indoors this never returns at all — and an
  /// unbounded one was the previous behaviour.
  Future<void> _publishFirstFix() async {
    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      _publish(position);
    } catch (error) {
      // Not fatal any more: the stream below is already running.
      log('DriverMapLocation: first fix failed :: $error');
    }
  }

  void _listen() {
    _stream?.cancel();
    _stream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(
      _publish,
      onError: (Object error) => log('DriverMapLocation: position stream :: $error'),
      cancelOnError: false,
    );
  }

  void _publish(Position position) {
    if (!isRealMapPoint(position.latitude, position.longitude)) return;
    _hasDeviceFix = true;
    // So the next cold start opens here before the GPS has said anything.
    unawaited(_store.remember(position.latitude, position.longitude));
    onFix(LatLng(position.latitude, position.longitude));
  }
}
