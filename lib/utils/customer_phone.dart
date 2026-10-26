import 'package:driver/models/user_model.dart';

/// The customer's mobile number as the driver sees it on an accepted order.
///
/// Orders carry the number and the country code in separate fields (almost all
/// `+92` and ten digits), so they are shown together. A number that already
/// starts with `+` is shown as it is, and an order without a number shows
/// nothing - the caller hides the line.
String customerPhoneText(UserModel? customer) {
  final String number = (customer?.phoneNumber ?? '').trim();
  if (number.isEmpty) return '';
  final String code = (customer?.countryCode ?? '').trim();
  if (code.isEmpty || number.startsWith('+')) return number;
  return '$code $number';
}
