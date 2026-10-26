import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Session 36 - the driver app's remaining waits.
///
/// Source-level guards, in the house style: these controllers open Firebase
/// listeners in `onInit`, so the shape is pinned rather than the screen pumped.
/// Every change here removes a wait or a duplicate without changing what is
/// read, written or shown.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// Source with comment lines dropped, so a comment quoting old code is not
  /// mistaken for the code.
  String code(String source) => source
      .split('\n')
      .where((String line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  String bodyOf(String source, String signature) {
    final int start = source.indexOf(signature);
    expect(start, greaterThan(-1), reason: '$signature is missing');
    final int end = source.indexOf('\n  }\n', start);
    return source.substring(start, end == -1 ? source.length : end);
  }

  test('switching to Available replaces the location listener instead of adding one', () {
    const List<String> dashboards = <String>[
      'lib/controllers/cab_dashboard_controller.dart',
      'lib/controllers/dash_board_controller.dart',
      'lib/controllers/parcel_dashboard_controller.dart',
      'lib/controllers/rental_dashboard_controller.dart',
    ];
    for (final String path in dashboards) {
      final String source = code(read(path));
      const String listen = '_subscriptions.add(location.onLocationChanged.listen(';
      int from = 0;
      int listeners = 0;
      while (true) {
        final int at = source.indexOf(listen, from);
        if (at == -1) break;
        listeners++;
        // The very next statement after the listener's closing `}));`.
        final int close = source.indexOf('}));', at);
        final String after = source.substring(close + 4).trimLeft();
        expect(after.startsWith('_keepOnlyNewestLocationSubscription();'), isTrue,
            reason: '$path: a location listener is added without dropping the previous one');
        from = close;
      }
      expect(listeners, 2, reason: path);
      final String helper = bodyOf(source, 'void _keepOnlyNewestLocationSubscription() {');
      expect(helper, contains('previous.cancel();'));
      expect(helper, contains('_subscriptions.remove(previous);'));
    }
  });

  test('payment settings are requested together and applied in the original order', () {
    final String body = bodyOf(code(read('lib/utils/fire_store_utils.dart')), 'static Future getPaymentSettingsData() async {');
    const List<String> order = <String>[
      'payFastSettings', 'MercadoPago', 'paypalSettings', 'stripeSettings', 'flutterWave', 'payStack', 'PaytmSettings',
      'walletSettings', 'razorpaySettings', 'CODSettings', 'midtrans_settings', 'orange_money_settings', 'xendit_settings',
    ];

    expect(RegExp(r'await fireStore\.collection').hasMatch(body), isFalse, reason: 'a settings read is awaited before the next is started');
    expect('.get()..ignore();'.allMatches(body).length, 13);

    int lastApplied = -1;
    for (final String id in order) {
      final int started = body.indexOf('.doc("$id").get()..ignore();');
      expect(started, greaterThan(-1), reason: 'settings/$id is not started up front');
      final Match? variable = RegExp(r'final Future<DocumentSnapshot<Map<String, dynamic>>> (\w+) = [^;]*\.doc\("' + RegExp.escape(id) + r'"\)').firstMatch(body);
      expect(variable, isNotNull, reason: id);
      final int applied = body.indexOf('await ${variable!.group(1)}.then(');
      expect(applied, greaterThan(lastApplied), reason: 'settings/$id is applied out of its original order');
      lastApplied = applied;
    }
  });

  test('a wallet transaction asks all four collections at once, in the same priority', () {
    final String body = bodyOf(code(read('lib/utils/fire_store_utils.dart')), 'static Future<dynamic> getOrderByIdFromAllCollections(String orderId) async {');

    final List<String> priority = <String>['CollectionName.parcelOrders', 'CollectionName.rentalOrders', 'CollectionName.ridesBooking', 'CollectionName.vendorOrders'];
    int last = -1;
    for (final String collection in priority) {
      final int at = body.indexOf(collection);
      expect(at, greaterThan(last));
      last = at;
    }
    expect(body, contains('collections.map((String collection) async {'));
    expect(body, contains('final snapshot = await lookups[i];'));
    expect(RegExp(r'for \(String collection in collections\)').hasMatch(body), isFalse);
  });

  test('the wallet starts its payment reads with the page, and still waits for them', () {
    final String source = code(read('lib/controllers/wallet_controller.dart'));
    final int started = source.indexOf('final Future<void> paymentMethod = getPaymentMethod()..ignore();');
    final int firstPage = source.indexOf('await firstPage;');
    final int awaited = source.indexOf('await paymentMethod;');
    final int lifted = source.indexOf('isLoading.value = false;', awaited);

    expect(started, greaterThan(-1));
    expect(started, lessThan(firstPage));
    expect(awaited, greaterThan(firstPage));
    expect(lifted, greaterThan(awaited), reason: 'the spinner must still wait for the withdraw method');

    final String method = bodyOf(source, 'Future<void> getPaymentMethod() async {');
    expect(method, contains('await Future.wait(<Future<void>>['));
    expect('await FireStoreUtils'.allMatches(method).length, 0);
  });

  test('chat buttons read both profiles at once', () {
    const List<String> screens = <String>[
      'lib/app/home_screen/home_screen.dart',
      'lib/app/parcel_screen/parcel_home_screen.dart',
      'lib/app/rental_service/rental_home_screen.dart',
      'lib/app/cab_screen/cab_home_screen.dart',
    ];
    for (final String path in screens) {
      final String source = code(read(path));
      expect(RegExp(r'UserModel\? customer = await FireStoreUtils\.getUserProfile').hasMatch(source), isFalse, reason: path);
      expect(source, contains('final List<UserModel?> people = await Future.wait(<Future<UserModel?>>['), reason: path);
    }
  });

  test('a bid is answered as soon as the transaction is, and the push still goes out', () {
    final String body = bodyOf(code(read('lib/services/bidding_service.dart')), 'static Future<SubmitBidResult> submitBid({');

    expect(body, contains('unawaited('));
    expect(body, contains('SendNotification.sendOneNotification('));
    expect(body.contains('await SendNotification.sendOneNotification('), isFalse);
    expect(body, contains('.catchError((Object e) {'), reason: 'a failed push must not become an unhandled error');
  });

  test('the parcel home opens its profile listeners once, however often the list refreshes', () {
    final String body = bodyOf(code(read('lib/controllers/parcel_home_controller.dart')), 'Future<void> getParcelList() async {');

    expect(body, contains('if (!_driverListenerOpen) {'));
    expect(body, contains('_driverListenerOpen = true;'));
    expect(body, contains('if (!_ownerListenerOpen && '));
    expect(body, contains('_ownerListenerOpen = true;'));
    expect(body, contains('FireStoreUtils.getOnGoingParcelList()'), reason: 'the list itself must still be re-read on every call');
  });

  test('the owner board replaces its order listeners when the driver list reloads', () {
    final String source = code(read('lib/controllers/owner_home_controller.dart'));
    final String reload = bodyOf(source, 'Future<void> getDriverList() async {');
    final String listen = bodyOf(source, 'void _listenDriverOrders(String driverId) {');

    expect(reload.indexOf('subscription.cancel();'), lessThan(reload.indexOf('_listenDriverOrders(driver.id!);')));
    expect('_trackDriverOrders('.allMatches(listen).length, 3);
    expect(listen.contains('_subscriptions.add('), isFalse);
  });
}
