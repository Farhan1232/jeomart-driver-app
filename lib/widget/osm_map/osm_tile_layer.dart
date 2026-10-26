import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// The OpenStreetMap tile layer every driver map draws.
///
/// One place, because the URL and the User-Agent are load-bearing:
/// `tile.openstreetmap.org` serves a **blank placeholder tile** to clients it
/// does not recognise and the real tile to ones it does, and `flutter_map`
/// builds that header out of `userAgentPackageName`. Getting it wrong looks
/// exactly like a map that will not load.
TileLayer osmTileLayer() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.jeomart.driver',
      tileProvider: CachedOsmTileProvider(),
      // A screen's worth of tiles either side, so a pan or a recentre draws
      // from memory instead of waiting on the network.
      keepBuffer: 4,
    );

/// A tile provider that keeps tiles on disk between launches.
///
/// `flutter_map`'s default holds tiles in memory only, so every time the
/// driver opened the home screen the same dozen tiles were downloaded again —
/// on a weak connection that is the whole wait the client describes, paid
/// afresh on every open. `cached_network_image` is already a dependency of
/// this app and its cache survives restarts, so the second open of a street
/// the driver has already seen paints immediately, and paints at all with no
/// signal.
class CachedOsmTileProvider extends TileProvider {
  CachedOsmTileProvider({super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      CachedNetworkImageProvider(
        getTileUrl(coordinates, options),
        // `TileLayer` injects the User-Agent here; without passing it on, OSM
        // sees an unidentified client and hands back the blank tile.
        headers: headers,
      );
}
