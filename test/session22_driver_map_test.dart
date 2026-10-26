// Session 22: "the map is not loading on the driver screen".
//
// The measurement that settled it. The driver's own `users/<uid>.location` is
// written only when the platform location stream fires, and that stream is
// throttled to `settings/DriverNearBy.driverLocationUpdate` metres — 1000 on
// this project. Of the forty live driver documents, five have no `location`
// field at all and three hold the placeholder `0.01, 0.01`. Both home
// controllers read that field through `?? 0.0`, wrote the result straight into
// `current`, and `current` was what `FlutterMap.initialCenter` was built on.
//
// `0, 0` is Null Island, and `https://tile.openstreetmap.org/16/32768/32768.png`
// is 103 bytes: one flat #AAD3DF tile, standard deviation zero, at every zoom
// past nine. No coastline, no road, no label. That is the screen the client
// photographed. It could never recover either — `initialCenter` is read once,
// the only recentring call was guarded by `!= 0.0` exactly (so `0.01, 0.01`
// sailed through it), and the single `getCurrentPosition()` that could have
// rescued it ran once from `onInit`, which since session 20 keeps the home
// section alive is once per app launch rather than once per tab switch.
//
// Each group here pins one half of the fix: never draw an unreal point, and
// always have a real one.

import 'dart:io';

import 'package:driver/models/user_model.dart';
import 'package:driver/utils/driver_map_location.dart';
import 'package:driver/widget/osm_map/osm_tile_layer.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String cabHome = File('lib/app/cab_screen/cab_home_screen.dart').readAsStringSync();
  final String cabController = File('lib/controllers/cab_home_controller.dart').readAsStringSync();
  final String deliveryHome = File('lib/app/home_screen/home_screen.dart').readAsStringSync();
  final String deliveryController = File('lib/controllers/home_controller.dart').readAsStringSync();

  group('a coordinate has to be a place before anything draws it', () {
    test('the two shapes the live data actually holds are refused', () {
      // Five driver documents have no location: read with `?? 0.0` that is this.
      expect(isRealMapPoint(0.0, 0.0), isFalse);
      // Three hold this placeholder, and an `== 0.0` test lets it straight past.
      expect(isRealMapPoint(0.01, 0.01), isFalse);
    });

    test('nothing at all is not a location', () {
      expect(isRealMapPoint(null, null), isFalse);
      expect(isRealMapPoint(24.86, null), isFalse);
      expect(isRealMapPoint(null, 67.00), isFalse);
    });

    test('unusable numbers are refused', () {
      expect(isRealMapPoint(double.nan, double.nan), isFalse);
      expect(isRealMapPoint(double.infinity, 0.0), isFalse);
      expect(isRealMapPoint(91.0, 0.0), isFalse);
      expect(isRealMapPoint(0.0, 181.0), isFalse);
    });

    test('the places this app actually operates in are accepted', () {
      expect(isRealMapPoint(33.5889, 71.4429), isTrue); // Kohat, where the rides are
      expect(isRealMapPoint(24.8607, 67.0011), isTrue); // Karachi
      expect(isRealMapPoint(31.5204, 74.3587), isTrue); // Lahore
    });

    test('one axis is enough — the equator and the meridian are real places', () {
      expect(isRealMapPoint(0.0, 67.0011), isTrue);
      expect(isRealMapPoint(51.4778, 0.0), isTrue);
    });

    test('the margin is a band, not a point', () {
      // Wide enough to swallow the 0.01 placeholder, narrow enough that it only
      // ever covers empty Atlantic.
      expect(isRealMapPoint(0.04, 0.04), isFalse);
      expect(isRealMapPoint(0.06, 0.0), isTrue);
    });
  });

  group('reading a point off the objects this app holds', () {
    test('a driver document with no location yields nothing, not Null Island', () {
      expect(realMapPoint(UserLocation()), isNull);
      expect(realMapPoint(UserLocation(latitude: 0.0, longitude: 0.0)), isNull);
      expect(realMapPoint(UserLocation(latitude: 0.01, longitude: 0.01)), isNull);
      expect(realMapPoint(null), isNull);
    });

    test('a real driver location comes through unchanged', () {
      final LatLng? point = realMapPoint(UserLocation(latitude: 33.5889, longitude: 71.4429));
      expect(point, isNotNull);
      expect(point!.latitude, 33.5889);
      expect(point.longitude, 71.4429);
    });

    test('coordinates stored as strings are understood', () {
      // Some documents were written by the panel, which stringifies numbers.
      expect(realMapPoint(_Stringly('33.5889', '71.4429'))?.latitude, 33.5889);
      expect(realMapPoint(_Stringly('nonsense', '71.4429')), isNull);
    });

    test('an object with no coordinates at all does not throw', () {
      expect(realMapPoint(Object()), isNull);
    });
  });

  group('a point that arrives before the map is not lost', () {
    test('an unreal point is refused outright, and never becomes the last point', () {
      final centre = DriverMapCentre(flutter_map.MapController());
      expect(centre.moveTo(LatLng(0, 0)), isFalse);
      expect(centre.moveTo(LatLng(0.01, 0.01)), isFalse);
      expect(centre.lastPoint, isNull);
    });

    test('a real point is kept even though the map cannot take it yet', () {
      // `MapController.move` throws until the widget has been laid out. That
      // used to be swallowed by a bare `catch`, which is how a fix that landed
      // one frame early was thrown away for the rest of the session.
      final centre = DriverMapCentre(flutter_map.MapController());
      expect(centre.isReady, isFalse);
      expect(centre.moveTo(LatLng(33.5889, 71.4429)), isTrue);
      expect(centre.lastPoint, isNotNull);
      expect(centre.lastPoint!.latitude, 33.5889);
      expect(centre.mapReady, returnsNormally);
    });

    test('the newest real point wins', () {
      final centre = DriverMapCentre(flutter_map.MapController());
      centre.moveTo(LatLng(24.8607, 67.0011));
      centre.moveTo(LatLng(33.5889, 71.4429));
      expect(centre.lastPoint!.latitude, 33.5889);
    });

    test('an unreal point cannot undo a real one', () {
      final centre = DriverMapCentre(flutter_map.MapController());
      centre.moveTo(LatLng(33.5889, 71.4429));
      centre.moveTo(LatLng(0, 0));
      expect(centre.lastPoint!.latitude, 33.5889);
    });

    test('the Google camera is only ever offered a real point', () {
      final List<LatLng> seen = <LatLng>[];
      final centre = DriverMapCentre(flutter_map.MapController(), onGoogleCamera: seen.add);
      centre.moveTo(LatLng(0, 0));
      centre.moveTo(LatLng(0.01, 0.01));
      centre.moveTo(LatLng(33.5889, 71.4429));
      expect(seen.length, 1);
      expect(seen.single.latitude, 33.5889);
    });
  });

  group('the map is built on the seed, and moved by everything after it', () {
    test('both home screens centre on the resolved seed, not on a live read', () {
      // `initialCenter` is consumed once. Reading `current.value` there made the
      // whole screen a subscriber of every GPS tick and still could not move the
      // camera afterwards.
      for (final String screen in <String>[cabHome, deliveryHome]) {
        expect(screen.contains('initialCenter: controller.initialMapCentre'), isTrue);
        expect(screen.contains('initialCenter: controller.current.value'), isFalse);
        expect(screen.contains('initialZoom: controller.initialMapZoom'), isTrue);
      }
    });

    test('both home screens hand the map back when it is ready', () {
      for (final String screen in <String>[cabHome, deliveryHome]) {
        expect(screen.contains('onMapReady: controller.onMapReady'), isTrue);
      }
    });

    test('neither controller writes a document coordinate in unchecked', () {
      // The exact expression that put the map in the Atlantic.
      for (final String controller in <String>[cabController, deliveryController]) {
        expect(
          controller.contains('current.value = location.LatLng(latLng.latitude, latLng.longitude)'),
          isFalse,
          reason: 'the document location is being adopted without a check again',
        );
        expect(controller.contains('realMapPoint(driverModel.value.location)'), isTrue);
        expect(controller.contains('mapLocation.hasDeviceFix'), isTrue);
      }
    });

    test('the recentre button cannot move to an unreal point', () {
      for (final String controller in <String>[cabController, deliveryController]) {
        expect(
          controller.contains("osmMapController.move(location.LatLng(lat, lng), 16)"),
          isFalse,
          reason: 'animateToSource is moving to an unchecked coordinate again',
        );
      }
    });

    test('the recentre button can also restart a location fix that gave up', () {
      // `start()` bails when permission was never granted while it waited, and
      // nothing else in the app asks a second time. This is the way back.
      for (final String controller in <String>[cabController, deliveryController]) {
        expect(controller.contains('mapLocation.retryIfIdle()'), isTrue);
      }
    });

    test('the one-shot unbounded GPS call is gone from both controllers', () {
      for (final String controller in <String>[cabController, deliveryController]) {
        expect(controller.contains('Geolocator.getCurrentPosition'), isFalse);
        expect(controller.contains('mapLocation.start()'), isTrue);
      }
    });
  });

  group('the tiles themselves', () {
    test('one layer, with the User-Agent OSM answers to', () {
      // `tile.openstreetmap.org` serves a blank placeholder to clients it does
      // not recognise, so this string is the difference between a map and a
      // grey rectangle. flutter_map builds it from userAgentPackageName.
      final flutter_map.TileLayer layer = osmTileLayer();
      expect(layer.urlTemplate, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
      expect(layer.tileProvider, isA<CachedOsmTileProvider>());
    });

    test('tiles are kept on disk between launches', () {
      // flutter_map's default provider holds tiles in memory only, so every
      // open of the home screen paid for the same dozen tiles again.
      expect(osmTileLayer().tileProvider, isA<CachedOsmTileProvider>());
    });

    test('every driver map draws through it', () {
      for (final String path in <String>[
        'lib/app/cab_screen/cab_home_screen.dart',
        'lib/app/home_screen/home_screen.dart',
        'lib/app/cab_screen/cab_order_details.dart',
        'lib/app/parcel_screen/parcel_tracking_screen.dart',
        'lib/app/owner_screen/driver_location_screen.dart',
        'lib/widget/osm_map/map_picker_page.dart',
      ]) {
        final String source = File(path).readAsStringSync();
        expect(source.contains('osmTileLayer()'), isTrue, reason: '$path builds its own tile layer');
        expect(source.contains('tile.openstreetmap.org'), isFalse, reason: '$path still hardcodes the URL');
      }
    });
  });
}

/// A document whose coordinates were written as strings.
class _Stringly {
  const _Stringly(this.latitude, this.longitude);
  final String latitude;
  final String longitude;
}
