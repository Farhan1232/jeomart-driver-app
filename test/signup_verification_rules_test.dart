import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A new driver is never signed up approved by a setting the app could not see.
///
/// The client: *"Most people sign up as driver and auto approved ... i already
/// opened documents approval"*. Sign-up copied the verification switch from the
/// launch-time read, which can come from the device cache and defaults to off.
void main() {
  late String signup;
  setUpAll(() {
    signup = File('lib/controllers/signup_controller.dart').readAsStringSync().split('\n').where((String l) => !l.trimLeft().startsWith('//')).join('\n');
  });

  String bodyOf(String signature) {
    final int start = signup.indexOf(signature);
    expect(start, greaterThan(-1), reason: '$signature is missing');
    final int end = signup.indexOf('\n  }\n', start);
    return signup.substring(start, end == -1 ? signup.length : end);
  }

  test('the switches are read from the server before the account is built', () {
    final String signUp = bodyOf('Future<void> signUp() async {');
    expect(signUp, contains('await _loadVerificationRules();'));
    expect(signUp.indexOf('await _loadVerificationRules();'), lessThan(signUp.indexOf('_populateUserModel();')));
    final String rules = bodyOf('Future<void> _loadVerificationRules() async {');
    expect(rules, contains("doc('document_verification_settings')"));
    expect(rules, contains('Source.server'));
  });

  test('a missing or unreadable setting counts as verification on', () {
    final String rules = bodyOf('Future<void> _loadVerificationRules() async {');
    expect(rules, contains("Constant.isDriverVerification = data['isDriverVerification'] as bool? ?? true;"));
    expect(rules, contains("Constant.isOwnerVerification = data['isOwnerVerification'] as bool? ?? true;"));
    final String onError = rules.substring(rules.indexOf('} catch (error) {'));
    expect(onError, contains('Constant.isDriverVerification = true;'));
    expect(onError, contains('Constant.isOwnerVerification = true;'));
  });
}
