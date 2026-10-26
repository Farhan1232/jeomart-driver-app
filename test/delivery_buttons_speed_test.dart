import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Food delivery: "Picked Order" and "Make Order Delivered" sat on "Please
/// wait" (5-10 s measured on the client's orders of 19 Oct). These pin what each
/// tap waits for, and that the Home screen underneath stops redoing work on
/// every write to the driver's document.
void main() {
  String code(String path) {
    final File file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing');
    return file.readAsStringSync().split('\n').where((String l) => !l.trimLeft().startsWith('//')).join('\n');
  }

  String bodyOf(String source, String signature) {
    final int start = source.indexOf(signature);
    expect(start, greaterThan(-1), reason: '$signature is missing');
    final int end = source.indexOf('\n  }\n', start);
    return source.substring(start, end == -1 ? source.length : end);
  }

  test('Picked Order writes the status field only and reports a failed save', () {
    final String screen = code('lib/app/home_screen/pickup_order_screen.dart');
    expect(screen, contains('await FireStoreUtils.setOrderStatus(controller.orderModel.value.id, Constant.orderInTransit);'));
    expect(screen.contains('FireStoreUtils.setOrder(controller.orderModel.value)'), isFalse);
    final String helper = bodyOf(code('lib/utils/fire_store_utils.dart'), 'static Future<bool> setOrderStatus(String? orderId, String status) async {');
    expect(helper, contains(".update(<String, dynamic>{'status': status})"));
  });

  test('after delivery the Home screen clears the order with the one-field release', () {
    final String screen = code('lib/app/home_screen/home_screen.dart');
    expect(screen, contains('unawaited(FireStoreUtils.releaseDriverOrder(deliveredId))'));
    expect(screen.contains('await FireStoreUtils.updateUser(controller.driverModel.value);'), isFalse);
  });

  test('the route is fetched again only when order, status or position changed, at most every 20 s', () {
    final String home = code('lib/controllers/home_controller.dart');
    expect(bodyOf(home, 'Future<void> changeData() async {'), contains('if (Constant.mapType == "inappmap" && _routeIsDue()) {'));
    final String due = bodyOf(home, 'bool _routeIsDue() {');
    expect(due, contains("'\${currentOrder.value.id}|\${currentOrder.value.status}|\$at'"));
    expect(home, contains('static const Duration _routeMinInterval = Duration(seconds: 20);'));
  });

  test('the order listener is kept while it follows the same order, and dropped whenever no order is shown', () {
    final String home = code('lib/controllers/home_controller.dart');
    final String listen = bodyOf(home, 'void _listenToOrder(String orderId, {bool checkInRequestData = false}) {');
    expect(listen, contains('if (_orderSub != null && _orderListenKey == key) return;'));
    expect(listen.indexOf('_orderListenKey == key'), lessThan(listen.indexOf('_orderSub?.cancel();')));
    expect(bodyOf(home, 'Future<void> _resetCurrentOrder() async {'), contains('_forgetOrderListener();'));
    expect(bodyOf(home, 'Future<void> _handleOrderNotFound() async {'), contains('_forgetOrderListener();'));
  });
}
