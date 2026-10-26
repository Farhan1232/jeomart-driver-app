/// How long the app is willing to wait for a plain HTTP request.
///
/// `package:http` has **no default timeout**. A request whose connection stalls
/// - a captive portal, a dropped mobile handover, a route server that accepts
/// the socket and never answers - leaves its `await` pending for as long as the
/// operating system keeps the socket open, which on Android can be minutes. On
/// this app every one of those awaits sits on a screen-load path: the driver
/// looks at a screen that never finishes arriving and reports that the app has
/// hung.
///
/// These are backstops, not latency targets. A request that needs longer than
/// its bound has already failed as far as the driver is concerned.
class NetworkTimeout {
  NetworkTimeout._();

  /// Route geometry, geocoding and marker artwork - anything a map screen waits
  /// on before it can finish drawing.
  static const Duration mapRequest = Duration(seconds: 15);

  /// Push-notification delivery. Longer, because nothing on screen is waiting
  /// for it, but still bounded so a queued send cannot pile up behind a stalled
  /// one.
  static const Duration notification = Duration(seconds: 20);

  // Payment gateways are deliberately **not** bounded, and there is no constant
  // here for them on purpose.
  //
  // A redirect that is slow because the bank is slow must still be allowed to
  // finish: abandoning it client-side risks a charge the app has stopped
  // waiting to hear about, with no way to reconcile it. Those calls keep their
  // original unbounded `await`.
}
