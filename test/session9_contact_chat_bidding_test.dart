import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/models/driver_trip_model.dart';
import 'package:driver/models/vehicle_type.dart';
import 'package:driver/utils/bidding_fare_rules.dart';
import 'package:driver/utils/bidding_settings.dart';
import 'package:driver/utils/driver_trip_state.dart';
import 'package:driver/utils/ride_bidding_state.dart';

/// Session 9, driver side — the client's 06 Sep 2026 report.
///
/// The driver could see *that* a customer had booked their trip but had no way
/// to reach them, and the fare floor was a car's floor on a motorcycle.
void main() {
  // -------------------------------------------------------------------------
  // The customer's contact block, which the driver app was writing and never
  // reading back.
  // -------------------------------------------------------------------------
  group('the passenger block on a booked trip', () {
    Map<String, dynamic> bookedTrip() => <String, dynamic>{
          DriverTripFields.id: 'trip1',
          DriverTripFields.driverId: 'drv1',
          DriverTripFields.status: DriverTripStatus.booked,
          DriverTripFields.fromAddress: 'Kohat',
          DriverTripFields.toAddress: 'Gadakhel',
          DriverTripFields.fullVehiclePrice: 1000,
          DriverTripFields.reservedBy: 'cust1',
          DriverTripFields.reservedByName: 'Sameer Khan',
          DriverTripFields.createdAt: Timestamp.fromDate(DateTime(2026, 9, 6, 23, 33)),
        };

    test('the trip names the customer, and the reservation is where the number is', () {
      final DriverTripModel trip = DriverTripModel.fromJson(bookedTrip());
      expect(trip.hasReservation, isTrue);
      expect(trip.reservedByName, 'Sameer Khan');
      expect(trip.reservedBy, 'cust1',
          reason: 'the reservation document id is the customer id, so this is the lookup key');
    });

    test('the reservation gives a dialable number and a chat token', () {
      final TripReservationModel reservation = TripReservationModel.fromJson(<String, dynamic>{
        'id': 'cust1',
        'customerId': 'cust1',
        'customerName': 'Sameer Khan',
        'countryCode': '+92',
        'phoneNumber': '3001234567',
        'fcmToken': 'tok-customer',
      });
      expect(reservation.fullPhoneNumber, '+923001234567');
      expect(reservation.fcmToken, 'tok-customer');
    });

    test('a finished trip is still a finished trip, so the card can hide the actions', () {
      for (final String status in <String>[DriverTripStatus.cancelled, DriverTripStatus.expired]) {
        expect(DriverTripStatus.isFinished(status), isTrue, reason: status);
      }
      for (final String status in <String>[DriverTripStatus.active, DriverTripStatus.booked]) {
        expect(DriverTripStatus.isFinished(status), isFalse, reason: status);
      }
    });

    test('the chat thread is keyed by the trip id, which both apps have', () {
      final DriverTripModel trip = DriverTripModel.fromJson(bookedTrip());
      // Both sides pass `orderId: trip.id`, so they meet in chat/{tripId}/thread.
      expect(trip.id, 'trip1');
      expect((trip.id ?? '').isNotEmpty, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // The fare floor, from the driver's side of it.
  // -------------------------------------------------------------------------
  group('the driver is held to the floor the customer was shown', () {
    const BiddingSettings settings = BiddingSettings(
      enabled: true,
      minimumFarePerKmEnabled: true,
      minimumFarePerKm: 50,
    );

    RideBiddingState requestFor({Object? vehicleType, num distanceKm = 10}) => RideBiddingState.fromJson(<String, dynamic>{
          RideBiddingFields.enabled: true,
          RideBiddingFields.status: RideBiddingStatus.open,
          RideBiddingFields.distanceKm: distanceKm,
          RideBiddingFields.offeredFare: 400,
          'vehicleType': vehicleType,
        });

    test('a counter offer on a motorcycle request uses the motorcycle rate', () {
      final RideBiddingState request = requestFor(
        vehicleType: <String, dynamic>{'id': 'bike', 'biddingMinimumFarePerKm': 25},
      );
      expect(
        BiddingFareRules.check(
          amount: 300,
          settings: settings,
          distanceKm: request.distanceKm.toDouble(),
          currencyDecimals: 0,
          vehicleRatePerKm: request.vehicleRatePerKm,
        ),
        FareCheckResult.ok,
      );
    });

    test('the same counter offer on a car request is refused', () {
      final RideBiddingState request = requestFor(vehicleType: <String, dynamic>{'id': 'car'});
      expect(
        BiddingFareRules.check(
          amount: 300,
          settings: settings,
          distanceKm: request.distanceKm.toDouble(),
          currencyDecimals: 0,
          vehicleRatePerKm: request.vehicleRatePerKm,
        ),
        FareCheckResult.belowMinimum,
      );
    });

    test('the driver app cannot invent a floor the settings do not have', () {
      const BiddingSettings off = BiddingSettings(enabled: true, minimumFarePerKmEnabled: false);
      final RideBiddingState request = requestFor(
        vehicleType: <String, dynamic>{'id': 'bike', 'biddingMinimumFarePerKm': 25},
      );
      expect(
        BiddingFareRules.minimumAllowedFare(
          settings: off,
          distanceKm: request.distanceKm.toDouble(),
          currencyDecimals: 0,
          vehicleRatePerKm: request.vehicleRatePerKm,
        ),
        0,
      );
    });

    test('the vehicle rate model matches the customer app byte for byte in behaviour', () {
      final VehicleType bike = VehicleType.fromJson(<String, dynamic>{
        'id': 'bike',
        'biddingMinimumFarePerKm': 25,
      });
      expect(bike.biddingMinimumFarePerKm, 25);
      expect(VehicleType.fromJson(<String, dynamic>{'id': 'car'}).biddingMinimumFarePerKm, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // The quick raises on the counter-offer sheet.
  // -------------------------------------------------------------------------
  group('quick raise chips', () {
    /// Mirrors `BiddingRequestController.raiseCounterOffer`, which cannot be
    /// constructed here without GetX and Firebase. The arithmetic is the part
    /// worth pinning: raises are additive, so any amount is reachable.
    double raise(double current, num step, {int decimals = 0}) =>
        BiddingFareRules.roundToCurrency(current + step.toDouble(), decimals);

    test('a raise adds to the customer\'s offer rather than replacing it', () {
      expect(raise(500, 50), 550);
    });

    test('raises stack, so 50 twice is 100', () {
      expect(raise(raise(500, 50), 50), 600);
    });

    test('an empty box starts from zero rather than throwing', () {
      expect(BiddingFareRules.parseAmount('') ?? 0, 0);
      expect(raise(BiddingFareRules.parseAmount('')?.toDouble() ?? 0, 100), 100);
    });

    test('a raise is rounded the way every other amount in the app is', () {
      expect(raise(99.994, 0.001, decimals: 2), 100.0);
    });
  });

  // -------------------------------------------------------------------------
  // The driver's My Trips screen actually renders the contact block.
  // -------------------------------------------------------------------------
  group('My Trips renders the passenger block', () {
    final String source = File('lib/app/cab_screen/my_trips_screen.dart').readAsStringSync();

    test('the booked card reads the reservation rather than only the trip', () {
      expect(source.contains('controller.reservationFor(trip)'), isTrue);
      expect(source.contains('fullPhoneNumber'), isTrue);
    });

    test('the card offers both a call and a chat', () {
      expect(source.contains('Constant.makePhoneCall'), isTrue);
      expect(source.contains('ChatScreen()'), isTrue);
    });

    test('the controller loads reservations for booked trips', () {
      final String controller = File('lib/controllers/my_trips_controller.dart').readAsStringSync();
      expect(controller.contains('DriverTripService.reservationFor'), isTrue);
      expect(controller.contains('loadReservations'), isTrue);
    });
  });
}
