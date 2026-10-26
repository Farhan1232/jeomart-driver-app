/// Who may change the ride request the dispatcher leaves on a driver's `users`
/// document (`ordercabRequestData`).
///
/// The dispatcher is that field's owner. It puts an offer there, takes it back
/// when nobody answers, and clears it only while it is still the offer it
/// meant (`clearDriverOffer` in `cabScheduleRide.js`).
///
/// The app used to save the field from whatever copy of the profile it held,
/// and both directions went wrong:
///
///  * a copy **with** a request wrote that request back - including one the
///    dispatcher had already taken back. The driver then counted as "already
///    has a request", was skipped for every new ride, and stayed that way until
///    the ten-minute sweep freed them. The live dispatcher log shows exactly
///    that on 14 Sep: a request taken back at 18:11 was being held again when
///    the sweep ran at 18:21;
///  * a copy **without** one deleted the field - including an offer that had
///    landed after the copy was read, so the request vanished from the
///    driver's screen and the ride sat out the whole accept window.
///
/// So the app never writes a request, and deletes one only when the copy being
/// saved was read holding a request that the caller has since let go of -
/// accepting, rejecting, completing or ending that ride.
class CabRequestSlot {
  const CabRequestSlot._();

  /// Whether saving a profile whose request is now [current], and which was
  /// read with ([loadedWithRequest]) or without a request on it, should delete
  /// the field.
  static bool shouldClear({required Object? current, required bool loadedWithRequest}) => current == null && loadedWithRequest;
}
