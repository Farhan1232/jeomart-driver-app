import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Session 50 - the chat button on the delivery home screen's accepted-order
/// card opens the chat of the order on that card.
///
/// It used to send `controller.orderModel.value.id`, which is only filled when
/// the screen is opened from the multiple-orders list. With "Single order
/// receive" on, the order id was empty, `collection('chat').doc('')` threw
/// while the chat screen was built, and no messages showed.
void main() {
  String code(String source) => source.split('\n').where((String line) => !line.trimLeft().startsWith('//')).join('\n');

  final String home = code(File('lib/app/home_screen/home_screen.dart').readAsStringSync());
  final int card = home.indexOf('Container buildOrderActionsCard(');
  final int chat = home.indexOf('Get.to(const ChatScreen()', card);
  final String chatArguments = home.substring(chat, home.indexOf('});', chat));

  test('the chat is opened with the order shown on the card', () {
    expect(card, greaterThan(-1));
    expect(chat, greaterThan(card));
    expect(chatArguments, contains('"orderId": controller.currentOrder.value.id,'));
  });

  test('not with orderModel, which is empty in single-order mode', () {
    expect(chatArguments, isNot(contains('orderModel')));
  });

  test('everything else the chat is opened with is unchanged', () {
    for (final String line in <String>[
      '"senderName": driver.fullName(),',
      '"receivedName": customer.fullName(),',
      '"senderId": driver.id,',
      '"receivedId": customer.id,',
      '"receivedProfileUrl": customer.profilePictureURL ?? "",',
      '"senderProfileUrl": driver.profilePictureURL ?? "",',
      '"token": customer.fcmToken,',
      '"chatType": Constant.userRoleDriver,',
    ]) {
      expect(chatArguments, contains(line));
    }
  });
}
