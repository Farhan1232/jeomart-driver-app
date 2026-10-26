import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Session 43 - buttons that hung on their loader or did nothing at all.
///
/// Source-level guards, in the house style: these handlers write to Firestore
/// and Storage and open dialogs, so their shape is pinned rather than the
/// screens pumped. Every change here closes a loader on a path that used to
/// leave it up, or replaces a throw inside a tap with a value it already meant;
/// what is written, and in which order, is unchanged.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// Source with comment lines dropped, so a comment quoting the old code is
  /// not mistaken for the code.
  String code(String source) => source
      .split('\n')
      .where((String line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  /// The body of the member declared by [signature], up to its closing brace at
  /// two spaces of indentation.
  String bodyOf(String source, String signature) {
    final int start = source.indexOf(signature);
    expect(start, greaterThan(-1), reason: '$signature is missing');
    final int end = source.indexOf('\n  }\n', start);
    return source.substring(start, end == -1 ? source.length : end);
  }

  /// [needles] appear in [body] in this order.
  void expectInOrder(String body, List<String> needles, String reason) {
    int last = -1;
    for (final String needle in needles) {
      final int at = body.indexOf(needle, last + 1);
      expect(at, greaterThan(last), reason: '$reason: "$needle" is missing or out of order');
      last = at;
    }
  }

  /// A `finally` that takes the loader down.
  void expectLoaderClosedInFinally(String body, String reason) {
    final int finallyAt = body.indexOf('} finally {');
    expect(finallyAt, greaterThan(-1), reason: '$reason: no finally');
    expect(body.indexOf('ShowToastDialog.closeLoader();', finallyAt), greaterThan(finallyAt),
        reason: '$reason: the finally does not close the loader');
  }

  group('parcel', () {
    final String source = code(read('lib/controllers/parcel_home_controller.dart'));

    test('Deliver Parcel always closes its loader and ignores a repeated tap', () {
      final String body = bodyOf(source, 'Future<void> completeParcel(ParcelOrderModel parcelBookingData) async {');
      expectLoaderClosedInFinally(body, 'completeParcel');
      expect(source, contains('String? _completingParcelId;'));
      expect(body, contains('_completingParcelId == parcelId'));
      expect(body.contains('author!.fcmToken'), isFalse);
      expect(body, contains('unawaited(SendNotification.sendFcmMessage('));
      expect(body.contains('await SendNotification.sendFcmMessage('), isFalse, reason: 'the push holds the loader again');
    });

    test('Deliver Parcel still writes wallet, parcel, list, referral - in that order', () {
      final String body = bodyOf(source, 'Future<void> completeParcel(ParcelOrderModel parcelBookingData) async {');
      expectInOrder(body, <String>[
        'await updateCabWalletAmount(parcelBookingData);',
        'await FireStoreUtils.setParcelOrder(parcelBookingData);',
        'await getParcelList();',
        'FireStoreUtils.getParcelFirstOrderOrNOt(parcelBookingData)',
      ], 'completeParcel');
    });

    test('Pickup Parcel always closes its loader', () {
      expectLoaderClosedInFinally(bodyOf(source, 'Future<void> pickupParcel(ParcelOrderModel parcelBookingData) async {'), 'pickupParcel');
    });

    test('the parcel wallet reads cannot throw on a missing field', () {
      final String body = bodyOf(source, 'Future<void> updateCabWalletAmount(ParcelOrderModel orderModel) async {');
      for (final String unsafe in <String>[
        'orderModel.adminCommission!',
        'orderModel.paymentMethod!',
        'orderModel.driver!',
        'orderModel.taxSetting!',
        'double.parse(orderModel.subTotal',
        'double.parse(orderModel.discount',
      ]) {
        expect(body.contains(unsafe), isFalse, reason: 'parcel updateCabWalletAmount: $unsafe');
      }
      expectInOrder(body, <String>['"Booking amount credited"', '"Admin commission deducted"'], 'parcel wallet order');
    });
  });

  group('rental', () {
    final String controller = code(read('lib/controllers/rental_home_controller.dart'));
    final String screen = code(read('lib/app/rental_service/rental_home_screen.dart'));

    test('Complete Booking always closes its loader and takes one completion per booking', () {
      final String body = bodyOf(controller, 'Future<void> completeParcel(RentalOrderModel parcelBookingData) async {');
      expect(body, contains('if (!beginCompletion(parcelBookingData.id))'));
      expectLoaderClosedInFinally(body, 'rental completeParcel');
      expect(body, contains('endCompletion(parcelBookingData.id);'));
      expect(body.contains('author!.fcmToken'), isFalse);
      expectInOrder(body, <String>[
        'await updateCabWalletAmount(parcelBookingData);',
        'await FireStoreUtils.rentalOrderPlace(parcelBookingData);',
      ], 'rental completeParcel');
      expect(controller, contains('bool beginCompletion(String? bookingId) {'));
      expect(controller, contains('void endCompletion(String? bookingId) {'));
    });

    test('a package without included hours or distance no longer throws', () {
      final String body = bodyOf(controller, 'Future<void> updateCabWalletAmount(RentalOrderModel orderModel) async {');
      for (final String unsafe in <String>[
        'int.parse(orderModel.rentalPackageModel!.includedHours',
        'double.parse(orderModel.rentalPackageModel!.includedDistance',
        'orderModel.adminCommission!',
        'orderModel.paymentMethod!',
        'orderModel.driver!',
      ]) {
        expect(body.contains(unsafe), isFalse, reason: 'rental updateCabWalletAmount: $unsafe');
      }
      expect(body, contains('orderModel.startTime != null'));
      expectInOrder(body, <String>['"Booking amount credited"', '"Admin commission deducted"'], 'rental wallet order');
    });

    test('Start Ride, Save km and Ride Completed close their loader when the write fails', () {
      expect(screen.contains('await FireStoreUtils.rentalOrderPlace(rentalBookingData).then('), isFalse,
          reason: 'a rentalOrderPlace that throws skips the close inside its then() again');
      for (final String dialog in <String>[
        'void showVerifyRentalPassengerDialog(',
        'void setFinalKilometerDialog(',
        'void conformCashPayment(',
      ]) {
        final String body = bodyOf(screen, dialog);
        expectLoaderClosedInFinally(body, dialog);
        expect(body, contains('if (!placed) {'), reason: '$dialog: a failed write still reports success');
      }
      expect(screen.contains('author!.fcmToken'), isFalse);
    });

    test('Ride Completed cannot credit a booking twice from a double tap', () {
      final String body = bodyOf(screen, 'void conformCashPayment(');
      expectInOrder(body, <String>[
        'if (!controller.beginCompletion(rentalBookingData.id)) return;',
        'await controller.updateCabWalletAmount(rentalBookingData);',
        'await FireStoreUtils.rentalOrderPlace(rentalBookingData);',
        'controller.endCompletion(rentalBookingData.id);',
      ], 'conformCashPayment');
    });

    test('the final kilometre check cannot throw on a missing start reading', () {
      final String body = bodyOf(screen, 'void setFinalKilometerDialog(');
      expect(body.contains('double.parse('), isFalse);
    });

    test('Verify Passenger scrolls with the keyboard up and fits four cells on a 320 px phone', () {
      final String body = bodyOf(screen, 'void showVerifyRentalPassengerDialog(');
      expect(body, contains('SingleChildScrollView('));
      expect(body, contains('insetPadding: const EdgeInsets.symmetric(horizontal: 20)'));
      // 320 - 2 x 20 inset - 2 x 20 padding = 240, four 50 px cells and three
      // 8 px gaps = 224.
      expect(body, contains('padding: const EdgeInsets.all(20.0)'));
      expect(body, contains('length: 4,'));
      expect(body, contains('cellSize: const Size(50, 50)'));
    });
  });

  group('document upload', () {
    test('Upload Document closes its loader on every path and says when it failed', () {
      final String body = bodyOf(code(read('lib/controllers/verification_details_upload_controller.dart')), 'Future<void> uploadDocument() async {');
      expectLoaderClosedInFinally(body, 'uploadDocument');
      expect(body, contains('uploaded = await FireStoreUtils.uploadDriverDocument(documents.value);'));
      expectInOrder(body, <String>['if (!uploaded) {', 'documents.value.status = previousStatus;', 'return;', 'Get.back(result: true);'], 'uploadDocument');
    });
  });

  group('edit profile', () {
    test('Save closes its loader on every path and only leaves on a real save', () {
      final String body = bodyOf(code(read('lib/controllers/edit_profile_controller.dart')), 'Future<void> saveData() async {');
      expectLoaderClosedInFinally(body, 'saveData');
      expect(body, contains('saved = await FireStoreUtils.updateUser(userModel.value);'));
      expectInOrder(body, <String>['if (!saved) {', 'return;', 'Get.back(result: true);'], 'saveData');
    });

    test('the zone field holds a long zone name', () {
      final String screen = code(read('lib/app/edit_profile_screen/edit_profile_screen.dart'));
      expectInOrder(screen, <String>['DropdownButtonFormField<ZoneModel>(', 'isExpanded: true,', 'hint: Text('], 'zone dropdown');
    });
  });

  group('camera / gallery sheets', () {
    const Map<String, String> sheets = <String, String>{
      'lib/app/edit_profile_screen/edit_profile_screen.dart': 'Future buildBottomSheet(BuildContext context, EditProfileController controller) {',
      'lib/app/verification_screen/verification_details_upload_screen.dart': 'Future buildBottomSheet(BuildContext context, DetailsUploadController controller, String type) {',
    };

    test('are sized by their content, not by a fixed share of the screen', () {
      sheets.forEach((String path, String signature) {
        final String body = bodyOf(code(read(path)), signature);
        expect(body.contains('Responsive.height(22, context)'), isFalse, reason: path);
        expect(body, contains('mainAxisSize: MainAxisSize.min'), reason: path);
        expect(body, contains('SafeArea('), reason: path);
      });
    });
  });

  group('food delivery', () {
    test('Make Order Delivered closes its loader on every path and ignores a repeated tap', () {
      final String source = code(read('lib/controllers/deliver_order_controller.dart'));
      final String body = bodyOf(source, 'Future<void> completedOrder() async {');
      expect(source, contains('String? _completingOrderId;'));
      expect(body, contains('_completingOrderId == orderId'));
      expectLoaderClosedInFinally(body, 'completedOrder');
      expect(body.contains('author!.fcmToken'), isFalse);
      expect(body, contains('unawaited(SendNotification.sendFcmMessage('));
      // 19 Oct: only the order is waited for; the wallet and the rest follow,
      // in their old order, once it is saved.
      expectInOrder(body, <String>[
        'await FireStoreUtils.setOrder(orderModel.value);',
        "if (saved != true) throw Exception(",
        'unawaited(_settleDeliveredOrder(orderModel.value));',
        'if (failed) {',
        'Get.back(result: true);',
      ], 'completedOrder');
      expect(body.contains('updateWallateAmount'), isFalse, reason: 'the wallet no longer holds the loader');
      final String settle = bodyOf(source, 'Future<void> _settleDeliveredOrder(OrderModel order) async {');
      expectInOrder(settle, <String>[
        'await FireStoreUtils.updateWallateAmount(order);',
        'await FireStoreUtils.releaseDriverOrder(order.id!);',
        'FireStoreUtils.getFirestOrderOrNOt(order)',
      ], '_settleDeliveredOrder');
      expect(settle.contains('updateUser('), isFalse, reason: 'a whole-profile save would overwrite wallet_amount');
    });

    test('the delivery wallet sum reads missing item fields as zero instead of throwing', () {
      final String body = bodyOf(code(read('lib/utils/fire_store_utils.dart')), 'static Future<void> updateWallateAmount(OrderModel orderModel) async {');
      for (final String unsafe in <String>[
        'double.parse(element.discountPrice',
        'double.parse(element.price',
        'double.parse(element.quantity',
        'double.parse(element.extrasPrice',
        'double.parse(orderModel.discount',
        "double.parse(orderModel.specialDiscount!['special_discount']",
      ]) {
        expect(body.contains(unsafe), isFalse, reason: 'updateWallateAmount: $unsafe');
      }
    });

    test('rejecting with no order in hand still takes the loader down', () {
      final String body = bodyOf(code(read('lib/controllers/home_controller.dart')), 'Future<void> rejectOrder() async {');
      final int guard = body.indexOf('if (order.id == null || driver.id == null) {');
      expect(guard, greaterThan(-1));
      final int ret = body.indexOf('return;', guard);
      expect(body.substring(guard, ret), contains('ShowToastDialog.closeLoader();'));
    });
  });
}
