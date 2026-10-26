import 'package:flutter_test/flutter_test.dart';

import 'package:driver/models/vehicle_type.dart';
import 'package:driver/utils/bidding_fare_rules.dart';
import 'package:driver/utils/bidding_settings.dart';
import 'package:driver/utils/ride_bidding_state.dart';

/// Session 16: every vehicle type the admin adds has to work.
///
/// The driver app reads the same `vehicle_type` collection as the customer app
/// and from the same model file, kept identical between the two on purpose.
/// This is the driver-side half of that contract: a document the panel saved
/// in a shape this class did not expect used to throw while being read, and a
/// driver registering a motorcycle or an auto rickshaw would find the vehicle
/// simply missing from the signup dropdown with nothing on screen to say why.
void main() {
  /// `Auto Rikshaw`, a healthy document from the client's cab section.
  Map<String, dynamic> autoRikshaw() => <String, dynamic>{
        'id': '66176a92ef4e4',
        'name': 'Auto Rikshaw',
        'capacity': '3',
        'description': 'auto',
        'short_description': 'auto',
        'supported_vehicle': 'auto',
        'sectionId': '631852d1bc978',
        'isActive': true,
        'vehicle_icon': 'https://example.invalid/riksha.png',
        'delivery_charges_per_km': 60,
        'minimum_delivery_charges': 150,
        'minimum_delivery_charges_within_km': 3,
      };

  group('a vehicle the admin added is always offered to the driver', () {
    test('a healthy document reads exactly as before', () {
      final VehicleType vehicle = VehicleType.fromJson(autoRikshaw());

      expect(vehicle.id, '66176a92ef4e4');
      expect(vehicle.name, 'Auto Rikshaw');
      expect(vehicle.isActive, isTrue);
      expect(vehicle.capacity, '3');
      expect(vehicle.seats, 3);
      expect(vehicle.delivery_charges_per_km, 60);
      expect(vehicle.biddingMinimumFarePerKm, isNull);
    });

    test('a capacity saved as a number does not throw the vehicle away', () {
      final VehicleType vehicle = VehicleType.fromJson(autoRikshaw()..['capacity'] = 3);

      expect(vehicle.capacity, '3');
      expect(vehicle.seats, 3);
    });

    test('charges saved as strings are still numbers', () {
      final VehicleType vehicle = VehicleType.fromJson(autoRikshaw()
        ..['delivery_charges_per_km'] = '60'
        ..['minimum_delivery_charges'] = '150');

      expect(vehicle.delivery_charges_per_km, 60);
      expect(vehicle.minimum_delivery_charges, 150);
    });

    test('an isActive saved as text is still a flag', () {
      expect(VehicleType.fromJson(autoRikshaw()..['isActive'] = 'true').isActive, isTrue);
      expect(VehicleType.fromJson(autoRikshaw()..['isActive'] = 'false').isActive, isFalse);
    });

    test('a document with nothing in it reads rather than throws', () {
      final VehicleType vehicle = VehicleType.fromJson(<String, dynamic>{});

      expect(vehicle.name, isNull);
      expect(vehicle.seats, isNull);
      expect(vehicle.delivery_charges_per_km, 0);
    });
  });

  group('NaN is not a rate', () {
    test('the NaN charges the panel could save are read as no charge', () {
      // `Ookla Scooty` really carries these: three `NaN`s left by charge boxes
      // saved empty, and a distance typed into the seats box.
      final VehicleType vehicle = VehicleType.fromJson(<String, dynamic>{
        'id': '6a8fad84d238d',
        'name': 'Ookla Scooty',
        'capacity': '50km',
        'isActive': false,
        'delivery_charges_per_km': double.nan,
        'minimum_delivery_charges': double.nan,
        'minimum_delivery_charges_within_km': double.nan,
      });

      expect(vehicle.delivery_charges_per_km, 0);
      expect(vehicle.minimum_delivery_charges, 0);
      expect(vehicle.minimum_delivery_charges_within_km, 0);
      expect(vehicle.seats, isNull);
    });

    test('a NaN bidding rate is no rate, so the global floor applies', () {
      final VehicleType vehicle = VehicleType.fromJson(autoRikshaw()..['biddingMinimumFarePerKm'] = double.nan);

      expect(vehicle.biddingMinimumFarePerKm, isNull);
    });

    test('a bidding rate the admin did set is kept, string or number', () {
      // A motorcycle is given a lower floor than a car by being given one here.
      expect(VehicleType.fromJson(autoRikshaw()..['biddingMinimumFarePerKm'] = 20).biddingMinimumFarePerKm, 20);
      expect(VehicleType.fromJson(autoRikshaw()..['biddingMinimumFarePerKm'] = '20.5').biddingMinimumFarePerKm, 20.5);
    });
  });

  group('seats, from a free-text box', () {
    test('a plain count is a count', () {
      expect(VehicleType.fromJson(autoRikshaw()..['capacity'] = '2').seats, 2);
      expect(VehicleType.fromJson(autoRikshaw()..['capacity'] = ' 10 ').seats, 10);
    });

    test('anything else states no seats rather than a wrong number', () {
      expect(VehicleType.fromJson(autoRikshaw()..['capacity'] = '').seats, isNull);
      expect(VehicleType.fromJson(autoRikshaw()..['capacity'] = '0').seats, isNull);
      expect(VehicleType.fromJson(autoRikshaw()..['capacity'] = '2+1 seater').seats, isNull);
    });
  });

  group('a bidding rate the panel could once save as NaN', () {
    RideBiddingState requestFor(Object? vehicleType) => RideBiddingState.fromJson(<String, dynamic>{
          RideBiddingFields.enabled: true,
          RideBiddingFields.status: RideBiddingStatus.open,
          RideBiddingFields.distanceKm: 10,
          RideBiddingFields.offeredFare: 400,
          'vehicleType': vehicleType,
        });

    test('is no rate, so the global floor still applies', () {
      // `NaN <= 0` is false, so a NaN rate used to be taken for a real one and
      // the floor it produced was NaN - which no offer is ever below, so the
      // minimum-fare rule quietly stopped applying to that vehicle.
      final RideBiddingState request = requestFor(<String, dynamic>{'id': 'bike', 'biddingMinimumFarePerKm': double.nan});

      expect(request.vehicleRatePerKm, isNull);
    });

    test('a rate the admin really set is still used', () {
      expect(requestFor(<String, dynamic>{'id': 'bike', 'biddingMinimumFarePerKm': 25}).vehicleRatePerKm, 25);
      expect(requestFor(<String, dynamic>{'id': 'car'}).vehicleRatePerKm, isNull);
    });

    test('the floor a NaN rate produces is the global one, not NaN', () {
      const BiddingSettings settings = BiddingSettings(
        enabled: true,
        minimumFarePerKmEnabled: true,
        minimumFarePerKm: 50,
      );
      final RideBiddingState request = requestFor(<String, dynamic>{'id': 'bike', 'biddingMinimumFarePerKm': double.nan});

      final double floor = BiddingFareRules.minimumAllowedFare(
        settings: settings,
        distanceKm: request.distanceKm.toDouble(),
        currencyDecimals: 0,
        vehicleRatePerKm: request.vehicleRatePerKm,
      );

      expect(floor, 500);
    });
  });
}
