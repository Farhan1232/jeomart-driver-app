import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The client's third report: "The Withdraw button is not working. Find why it
/// is not responding and fix them to go the related screen."
///
/// Four separate things could stop that button, and every one of them looks
/// identical from the outside - the driver taps and the screen does not move.
/// Three were exceptions thrown inside a tap handler, which Flutter reports to
/// the console and nowhere else; the fourth was the button reaching a dead end
/// on purpose.
void main() {
  String read(String relative) => File(relative).readAsStringSync();

  late String screen;
  late String controller;

  /// Just the Withdraw button and the withdrawal sheet it opens.
  ///
  /// The wallet screen is 1300 lines and also draws order, rental and parcel
  /// earnings summaries, which parse their own amounts. Only the withdrawal
  /// path is this report's subject, so the parse assertions are scoped to it
  /// rather than to a file that has every other reason to hold a `parse`.
  late String withdrawFlow;

  setUpAll(() {
    screen = read('lib/app/wallet_screen/wallet_screen.dart');
    controller = read('lib/controllers/wallet_controller.dart');

    final int start = screen.indexOf('title: "Withdraw".tr,');
    final int end = screen.indexOf('InkWell transactionCardWithdrawal(');
    expect(start, greaterThan(-1), reason: 'the Withdraw button must still be there to test');
    expect(end, greaterThan(start));
    withdrawFlow = screen.substring(start, end);
  });

  group('nothing in the Withdraw flow can throw inside a tap handler', () {
    test('the wallet screen no longer force-unwraps the signed-in driver', () {
      // `Constant.userModel` is only populated once the profile has been read.
      // Session 28 made that happen on the read rather than on a write, but the
      // null assertion was still sitting in the handler - and it is the handler
      // that has to survive a driver who opened the wallet early.
      expect(screen.contains('Constant.userModel!'), isFalse,
          reason: 'a null assertion in onPress is a button that silently does nothing');
    });

    test('the currency symbol cannot bring the withdrawal sheet down', () {
      expect(screen.contains('Constant.currencyModel!'), isFalse);
      expect(screen, contains("(Constant.currencyModel?.symbol ?? '').tr"));
    });

    test('neither amount is parsed with a throwing parse', () {
      // An admin who clears the minimum-amount field leaves the setting an
      // empty string, and `double.parse('')` threw for every driver at once.
      expect(RegExp(r'double\.parse\(').hasMatch(withdrawFlow), isFalse,
          reason: 'double.tryParse refuses; double.parse throws');
      expect(withdrawFlow, contains('double.tryParse(Constant.minimumAmountToWithdrawal) ?? 0'));
      expect(withdrawFlow, contains('double.tryParse(controller.amountTextFieldController.value.text.trim())'));
    });

    test('the driver is asked through the controller, which always has an answer', () {
      expect(screen, contains('controller.hasWithdrawMethod'));
      expect(controller, contains('bool get hasWithdrawMethod'));
      // The controller's copy is populated from the cache *or* a profile read,
      // which is what makes it safe to read without a null assertion.
      expect(controller, contains('final UserBankDetails? bank = userModel.value.userBankDetails;'));
      expect(controller, contains('return withdrawMethodModel.value.id != null;'));
    });
  });

  group('with no payment method the button goes to the related screen', () {
    test('it opens the withdraw-method setup screen instead of only toasting', () {
      // The dead end: the only thing that used to happen was a toast telling
      // the driver to enter a payment method, with nothing that let them.
      expect(screen, contains('await Get.to(() => const WithdrawMethodSetupScreen())'));
      expect(screen, contains("import 'package:driver/app/withdraw_method_setup_screens/withdraw_method_setup_screen.dart';"));
      expect(screen.contains('ShowToastDialog.showToast("Please enter payment method".tr)'), isFalse,
          reason: 'the toast that went nowhere is gone');
    });

    test('it re-reads the method on the way back and then opens the sheet', () {
      final int navigate = screen.indexOf('await Get.to(() => const WithdrawMethodSetupScreen())');
      final int refresh = screen.indexOf('await controller.refreshWithdrawMethod()');
      expect(navigate, greaterThan(-1));
      expect(refresh, greaterThan(navigate), reason: 'the re-read has to follow the screen it is reading after');

      // And the sheet opens on the same tap, so adding a bank account and
      // withdrawing is one journey rather than two.
      expect(screen.indexOf('withdrawalCardBottomSheet(context, controller)', refresh), greaterThan(refresh));
      expect(controller, contains('Future<void> refreshWithdrawMethod() async'));
    });

    test('a driver who already has a method still goes straight to the sheet', () {
      final int guard = screen.indexOf('if (controller.hasWithdrawMethod) {');
      final int sheet = screen.indexOf('withdrawalCardBottomSheet(context, controller);', guard);
      final int ret = screen.indexOf('return;', sheet);
      expect(guard, greaterThan(-1));
      expect(sheet, greaterThan(guard));
      expect(ret, greaterThan(sheet), reason: 'the happy path must not fall through into the setup screen');
    });
  });

  group('the wallet screen itself', () {
    test('the tab controller agrees with the tabs it has', () {
      // `length: 3` against two Tabs and two TabBarView children. Flutter only
      // asserts that in debug; a release build hands the third page to a view
      // with two children.
      expect(screen.contains('length: 3,'), isFalse);
      expect(screen, contains('length: 2,'));
      expect(RegExp(r'Tab\(\s*text:').allMatches(screen).length, 2);
    });

    test('a withdrawal larger than the balance is refused', () {
      expect(screen, contains('amount > (controller.userModel.value.walletAmount ?? 0)'));
    });
  });

  group('the amount field accepts the number the keyboard offers', () {
    // The field asks for a decimal keyboard and then filtered the decimal
    // point out, so 10.50 was submitted as 1050.
    final TextInputFormatter formatter = FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'));

    String filter(String input) => formatter
        .formatEditUpdate(
          const TextEditingValue(text: ''),
          TextEditingValue(text: input, selection: TextSelection.collapsed(offset: input.length)),
        )
        .text;

    test('the formatter in the screen is the one under test here', () {
      expect(screen, contains(r"FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))"));
    });

    test('a decimal amount survives', () {
      expect(filter('10.50'), '10.50');
      expect(filter('0.75'), '0.75');
      expect(filter('1000'), '1000');
      expect(filter('7'), '7');
    });

    test('nonsense does not', () {
      expect(filter('abc'), '');
      expect(filter('12abc'), '12');
      expect(filter('1.2.3'), '1.2', reason: 'one point only, so tryParse always succeeds');
      expect(filter('-5'), '', reason: 'a negative withdrawal is not a withdrawal');
      expect(filter('1.234'), '1.23', reason: 'two decimal places is money');
    });

    test('every value the filter allows is a number tryParse accepts', () {
      for (final String input in <String>['10.50', '0.75', '1000', '7', '12abc', '1.2.3', '1.234', '0.1']) {
        final String filtered = filter(input);
        if (filtered.isEmpty) continue;
        expect(double.tryParse(filtered), isNotNull, reason: '"$input" filtered to "$filtered"');
      }
    });
  });
}
