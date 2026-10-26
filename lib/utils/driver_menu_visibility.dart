/// Client-requested visibility switches for **driver-app menu entries**.
///
/// Session 4 carries two requirements that are purely about what the driver can
/// reach from the app:
///
/// * *"Hide Change Section — Driver App"*
/// * *"Hide Vehicle information — Driver App"*
///
/// Both are **navigation** requirements, not data requirements. The screens,
/// the controllers and - much more importantly - the underlying `vehicleDetails`
/// / `sectionIds` model fields stay exactly as they are, because live features
/// read them:
///
/// * `services/bidding_service.dart` puts the vehicle name, type and AC/Non-AC
///   flag on every bid the driver sends (Session 2).
/// * `services/driver_trip_service.dart` and `controllers/post_trip_controller.dart`
///   stamp the same vehicle information onto a published trip (Session 3).
/// * `controllers/rental_booking_search_controller.dart` matches rentals by the
///   driver's vehicle.
/// * `controllers/signup_controller.dart` and `controllers/driver_create_controller.dart`
///   are how vehicle details get **captured** in the first place - at signup, and
///   by a fleet owner adding a driver. Neither is the screen the client asked to
///   hide, and hiding either would make it impossible to onboard a driver.
///
/// So the flags below gate the drawer entries only. Flipping one back to `true`
/// restores the entry with no other change, which is the point of keeping the
/// screens compiled in rather than deleting them.
class DriverMenuVisibility {
  const DriverMenuVisibility._();

  /// The drawer entry titled **"Change Section"**, present in the cab, rental,
  /// parcel and delivery dashboards, which opens `ChangeSectionScreen`.
  ///
  /// Hidden per the client's Session 4 requirement. `ChangeSectionScreen` and
  /// `ChangeSectionController` are retained: a driver's section membership is
  /// still set at signup and still editable by an owner/admin, and the
  /// controller is the only code that knows how to rewrite `sectionNames` and
  /// `vehicleDetails` consistently when membership changes.
  static const bool showChangeSection = false;

  /// The drawer entry titled **"Vehicle Information"** in the cab and rental
  /// dashboards (drawer slot 6), which opens `VehicleInformationScreen`.
  ///
  /// Hidden per the client's Session 4 requirement. Everything that *displays*
  /// vehicle data - the cab home card, bid offers, Available Trips, the admin
  /// panel - is unaffected; this only removes the driver's self-service editor.
  static const bool showVehicleInformation = false;

  /// The drawer slot `VehicleInformationScreen` occupies in the cab and rental
  /// dashboards. Nothing writes this slot once [showVehicleInformation] is
  /// false - the drawer entry was its only writer - but it is named here so the
  /// body branch and the hidden entry can never drift apart.
  static const int vehicleInformationDrawerIndex = 6;
}
