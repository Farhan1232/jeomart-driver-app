import 'dart:io';

import 'package:driver/models/user_model.dart';
import 'package:driver/utils/customer_phone.dart';
import 'package:flutter_test/flutter_test.dart';

/// Session 49 - once a delivery is accepted, the driver sees the customer's
/// mobile number under the customer's name.
void main() {
  String read(String path) => File(path).readAsStringSync();

  String code(String source) => source.split('\n').where((String line) => !line.trimLeft().startsWith('//')).join('\n');

  group('the number shown', () {
    test('the country code and the number together, as orders store them apart', () {
      expect(customerPhoneText(UserModel(countryCode: '+92', phoneNumber: '3001234567')), '+92 3001234567');
      expect(customerPhoneText(UserModel(countryCode: '+971', phoneNumber: '501234567')), '+971 501234567');
    });

    test('a number that already carries its code is shown as it is', () {
      expect(customerPhoneText(UserModel(countryCode: '+92', phoneNumber: '+923001234567')), '+923001234567');
    });

    test('no country code - the number alone', () {
      expect(customerPhoneText(UserModel(phoneNumber: '3001234567')), '3001234567');
      expect(customerPhoneText(UserModel(countryCode: ' ', phoneNumber: ' 3001234567 ')), '3001234567');
    });

    test('no number - nothing, so the line is hidden', () {
      expect(customerPhoneText(UserModel(countryCode: '+92', phoneNumber: '')), '');
      expect(customerPhoneText(UserModel(countryCode: '+92')), '');
      expect(customerPhoneText(null), '');
    });
  });

  group('where it is shown', () {
    final String home = code(read('lib/app/home_screen/home_screen.dart'));
    final int accepted = home.indexOf('Container buildOrderActionsCard(');

    test('once, on the accepted-order card, under the customer\'s name', () {
      expect(accepted, greaterThan(-1));
      expect('customerPhoneText('.allMatches(home).length, 2, reason: 'one visibility check and one Text, nothing more');

      final int name = home.indexOf("controller.currentOrder.value.author?.fullName() ?? ''", accepted);
      final int phone = home.indexOf('customerPhoneText(controller.currentOrder.value.author)', accepted);
      final int address = home.indexOf('controller.currentOrder.value.address!.getFullAddress()', accepted);
      expect(name, greaterThan(accepted));
      expect(phone, greaterThan(name), reason: 'under the name');
      expect(phone, lessThan(address), reason: 'and above the address');
    });

    test('not on the request card, before the driver has accepted', () {
      expect(home.indexOf('customerPhoneText('), greaterThan(accepted),
          reason: 'the card with Accept / Reject comes before buildOrderActionsCard and must not show it');
    });

    test('the call button is left exactly as it was', () {
      expect(home, contains('Constant.makePhoneCall(controller.currentOrder.value.author!.phoneNumber.toString());'));
    });
  });
}
