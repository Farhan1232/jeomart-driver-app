import 'dart:async';

import 'package:driver/constant/constant.dart';
import 'package:driver/utils/driver_map_location.dart';
import 'package:driver/utils/driver_verification_gate.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Master switch for the on-screen map diagnostics.
///
/// **`true` only in a diagnostic build.** Flip to `false` before cutting a
/// release: this panel is a debugging instrument, not a feature.
const bool kMapDiagnostics = false;

/// Prints, on the device, every value that decides whether a map is drawn.
///
/// The map has been reported missing repeatedly, and it could not be reproduced
/// here: this project has no web build (several of its plugins have no web
/// implementation) and this machine has no KVM, so no emulator either. Rather
/// than keep guessing, this makes the running app state the reason out loud, so
/// one screenshot settles it.
///
/// Every line is one branch that can end with no map on screen.
class MapDiagnosticsOverlay extends StatefulWidget {
  const MapDiagnosticsOverlay({
    super.key,
    required this.screen,
    required this.isLoading,
    this.mapCentre,
  });

  /// Which screen is hosting this, so a screenshot names its own source.
  final String screen;

  /// The host controller's `isLoading` at build time — if this is true the
  /// whole body is a spinner and no map exists yet.
  final bool isLoading;

  /// Where the map was told to open, if the host knows.
  final String? mapCentre;

  @override
  State<MapDiagnosticsOverlay> createState() => _MapDiagnosticsOverlayState();
}

class _MapDiagnosticsOverlayState extends State<MapDiagnosticsOverlay> {
  String _tile = 'checking…';
  String _permission = 'checking…';
  String _position = 'checking…';
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_probeTile());
    unawaited(_probeLocation());
  }

  /// Fetches one real OSM tile with the app's own User-Agent.
  ///
  /// This is the check that cannot be done from a desktop: it proves whether
  /// *this device, on this network* can reach the tile server at all, and
  /// whether OSM is handing it the real tile or the blank placeholder it serves
  /// to clients it does not recognise.
  Future<void> _probeTile() async {
    const String url = 'https://tile.openstreetmap.org/14/11576/6679.png';
    try {
      final http.Response r = await http
          .get(Uri.parse(url), headers: <String, String>{'User-Agent': 'flutter_map (com.jeomart.driver)'})
          .timeout(const Duration(seconds: 20));
      final String blocked = r.headers['x-blocked'] == null ? '' : '  BLOCKED';
      if (mounted) {
        setState(() => _tile = 'HTTP ${r.statusCode}  ${r.bodyBytes.length}B$blocked');
      }
    } catch (e) {
      if (mounted) setState(() => _tile = 'FAILED: $e');
    }
  }

  Future<void> _probeLocation() async {
    try {
      final LocationPermission p = await Geolocator.checkPermission();
      final bool service = await Geolocator.isLocationServiceEnabled();
      if (mounted) setState(() => _permission = '$p  service=$service');
      final Position? last = await Geolocator.getLastKnownPosition();
      if (mounted) {
        setState(() => _position = last == null
            ? 'no last-known fix'
            : '${last.latitude.toStringAsFixed(5)}, ${last.longitude.toStringAsFixed(5)}');
      }
    } catch (e) {
      if (mounted) setState(() => _position = 'FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kMapDiagnostics) return const SizedBox.shrink();

    final MapChoice choice = Constant.mapChoice;
    final bool gated = driverAwaitsDocumentVerification(Constant.userModel);
    final String seed = driverMapSeed()?.toString() ?? 'none';

    String verdict;
    if (widget.isLoading) {
      verdict = 'NO MAP — screen still isLoading';
    } else if (gated) {
      verdict = 'NO MAP — documents screen is showing instead';
    } else if (!choice.isInApp) {
      verdict = 'NO MAP — mapType is "${Constant.mapType}", not "inappmap"';
    } else if (!choice.isOsm) {
      verdict = 'GOOGLE MAP branch — needs a billed API key';
    } else {
      verdict = 'OSM MAP is being drawn';
    }

    if (_collapsed) {
      return Positioned(
        top: 40,
        left: 8,
        child: GestureDetector(
          onTap: () => setState(() => _collapsed = false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: Colors.black87,
            child: const Text('diagnostics',
                style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    return Positioned(
      top: 40,
      left: 8,
      right: 8,
      child: GestureDetector(
        onTap: () => setState(() => _collapsed = true),
        child: Container(
          padding: const EdgeInsets.all(10),
          color: Colors.black.withValues(alpha: 0.85),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(verdict,
                  style: const TextStyle(
                      color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold, height: 1.3)),
              const SizedBox(height: 6),
              _row('screen', widget.screen),
              _row('uid', FireStoreUtils.getCurrentUid()),
              _row('isLoading', '${widget.isLoading}'),
              _row('docVerify', '${Constant.userModel?.isDocumentVerify}'),
              _row('autoVerify', '${Constant.userModel?.isAutoVerify}'),
              _row('admin requires', 'driver=${Constant.isDriverVerification} owner=${Constant.isOwnerVerification}'),
              _row('gated', '$gated'),
              _row('mapType', '${Constant.mapType}'),
              _row('selectedMapType', Constant.selectedMapType),
              _row('map centre', widget.mapCentre ?? '—'),
              _row('seed', seed),
              _row('permission', _permission),
              _row('last fix', _position),
              _row('OSM tile', _tile),
              const SizedBox(height: 4),
              const Text('tap to collapse',
                  style: TextStyle(color: Colors.white38, fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Text('$label: $value',
            style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.25)),
      );
}

/// Lays [child] under a [MapDiagnosticsOverlay].
///
/// Wraps the whole screen rather than one branch of it, so the panel is on
/// screen even when the branch that renders is the spinner or the documents
/// screen — which are the two cases we most need named.
Widget withMapDiagnostics(
  Widget child, {
  required String screen,
  required bool isLoading,
  String? mapCentre,
}) {
  if (!kMapDiagnostics) return child;
  return Stack(
    children: <Widget>[
      child,
      MapDiagnosticsOverlay(screen: screen, isLoading: isLoading, mapCentre: mapCentre),
    ],
  );
}
