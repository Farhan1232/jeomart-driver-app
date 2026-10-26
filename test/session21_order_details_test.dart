// Session 21: opening any ride in the driver's Orders section drew a blank
// screen.
//
// The client sent two screenshots of it - one from tapping a completed ride,
// one from tapping the ride they had just accepted - and both are the same
// thing: a flat grey rectangle with no app bar. That is what a release build
// paints when a widget throws while it is being built, and the throw was in
// `CabOrderDetailsController.onInit`, before the screen existed at all.
//
// The cause is live data, not a corrupt document. `adminCommission` is null on
// every ride placed while the admin has that section's commission switched off,
// which on this project is 100 of 265 rides and every recent one; `taxSetting`
// is null on the rest; `scheduleDateTime` is only written for a ride booked for
// later. Each was read through `!`.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/controllers/cab_order_details_controller.dart';
import 'package:driver/models/cab_order_model.dart';
import 'package:driver/models/tax_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String screen = File('lib/app/cab_screen/cab_order_details.dart').readAsStringSync();

  /// A ride shaped the way the live project writes them: a fare, no commission,
  /// no tax list, and no scheduled time because it was hailed for now.
  CabOrderModel liveRide() => CabOrderModel()
    ..id = 'ride-1'
    ..subTotal = '1000.0'
    ..discount = '0.0'
    ..status = 'Order Completed'
    // Local time: `formatDate` prints in the driver's zone, as the list
    // screen behind this one does.
    ..createdAt = Timestamp.fromDate(DateTime(2026, 9, 9, 14, 59));

  group('the fare adds up whatever the ride document is missing', () {
    test('a ride with no commission and no tax list totals its subtotal', () {
      final controller = CabOrderDetailsController();
      controller.cabOrder.value = liveRide();

      controller.calculateTotalAmount();

      expect(controller.subTotal.value, 1000.0);
      expect(controller.discount.value, 0.0);
      expect(controller.taxAmount.value, 0.0);
      expect(controller.adminCommission.value, 0.0);
      expect(controller.totalAmount.value, 1000.0);
    });

    test('an empty commission string is not a commission', () {
      // `''` reached `calculateAdminCommission` as a live value before, via the
      // `?? '0'` on a field that was not null but empty.
      final controller = CabOrderDetailsController();
      controller.cabOrder.value = liveRide()..adminCommission = '';

      controller.calculateTotalAmount();

      expect(controller.adminCommission.value, 0.0);
      expect(controller.totalAmount.value, 1000.0);
    });

    test('a subtotal that is missing entirely reads as zero, not as a throw', () {
      final controller = CabOrderDetailsController();
      controller.cabOrder.value = CabOrderModel()..id = 'ride-2';

      controller.calculateTotalAmount();

      expect(controller.subTotal.value, 0.0);
      expect(controller.totalAmount.value, 0.0);
    });

    test('a tax list that is present is still applied', () {
      // The fix must not have made the screen ignore tax where there is some.
      final controller = CabOrderDetailsController();
      controller.cabOrder.value = liveRide()
        ..taxSetting = <TaxModel>[TaxModel(title: 'GST', type: 'percentage', tax: '10', enable: true)];

      controller.calculateTotalAmount();

      expect(controller.taxAmount.value, 100.0);
      expect(controller.totalAmount.value, 1100.0);
    });
  });

  group('the booking date', () {
    test('falls back to when the ride was created', () {
      // `scheduleDateTime` is null unless the customer booked for later. The
      // list screen behind this one prints `createdAt` for those, so this
      // screen now agrees with it instead of throwing.
      final controller = CabOrderDetailsController();
      controller.cabOrder.value = liveRide();

      expect(controller.bookingDate, '09 Sep 2026, 02:59 PM');
    });

    test('is blank when the ride carries neither date', () {
      final controller = CabOrderDetailsController();
      controller.cabOrder.value = CabOrderModel();

      expect(controller.bookingDate, '');
    });

    test('the screen asks the controller for it rather than forcing the field', () {
      expect(screen.contains('scheduleDateTime!'), isFalse);
      expect(screen.contains(r'${controller.bookingDate}'), isTrue);
    });
  });

  group('the map', () {
    test('is drawn only for a ride that carries both ends', () {
      // Every map call on this screen needs four coordinates. A ride without
      // them now draws no map rather than taking the whole screen down.
      expect(screen.contains('if (controller.hasRoute)'), isTrue);
    });

    test('hasRoute wants all four numbers', () {
      final controller = CabOrderDetailsController();
      controller.cabOrder.value = liveRide();
      expect(controller.hasRoute, isFalse);

      controller.cabOrder.value = liveRide()
        ..sourceLocation = DestinationLocation(latitude: 33.58, longitude: 71.44)
        ..destinationLocation = DestinationLocation(latitude: 33.59, longitude: 71.45);
      expect(controller.hasRoute, isTrue);

      controller.cabOrder.value = liveRide()
        ..sourceLocation = DestinationLocation(latitude: 33.58, longitude: 71.44)
        ..destinationLocation = DestinationLocation(latitude: null, longitude: 71.45);
      expect(controller.hasRoute, isFalse);
    });
  });

  group('the tax rows', () {
    test('generate nothing rather than force a null list', () {
      expect(screen.contains('taxSetting!.length'), isFalse);
      expect(screen.contains('(controller.cabOrder.value.taxSetting ?? const []).length'), isTrue);
    });
  });
}
