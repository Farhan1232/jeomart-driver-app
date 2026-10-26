import 'dart:io';

import 'package:driver/constant/constant.dart';
import 'package:driver/controllers/signup_controller.dart';
import 'package:driver/models/section_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Session 28 - the four driver-app defects the client reported on 10 Sep.
///
/// Two of them are about a driver's **service** being rewritten under them, one
/// is about a button that appeared to do nothing, and the last is the profile
/// that never reached memory. Each test names the symptom it stops coming back.
void main() {
  String read(String path) {
    final File file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing - this test is stale');
    return file.readAsStringSync();
  }

  group('a save must never rewrite the driver\'s service', () {
    test('toJson leaves serviceTypes out when the model does not carry it', () {
      final UserModel partial = UserModel(id: 'driver1', role: Constant.userRoleDriver);

      final Map<String, dynamic> json = partial.toJson();

      // The old line was `data['serviceTypes'] = serviceTypes ?? ['delivery-service']`,
      // so saving a push token turned a cab driver into a delivery driver.
      expect(json.containsKey('serviceTypes'), isFalse,
          reason: 'a model with no serviceTypes must not invent one - it is written with merge:true');
      expect(json.containsKey('sectionIds'), isFalse,
          reason: 'a model with no sectionIds must not empty the driver\'s sections');
    });

    test('toJson still writes them when the model does carry them', () {
      final UserModel full = UserModel(
        id: 'driver1',
        role: Constant.userRoleDriver,
        serviceTypes: <String>['cab-service'],
        sectionIds: <String>['631852d1bc978'],
      );

      final Map<String, dynamic> json = full.toJson();

      expect(json['serviceTypes'], <String>['cab-service']);
      expect(json['sectionIds'], <String>['631852d1bc978']);
    });

    test('the legacy singular fields are mirrored, never deleted', () {
      final String source = read('lib/utils/fire_store_utils.dart');

      // `serviceType` / `sectionId` are what the admin panel writes, and its
      // driver list still *queries* them - `drivers/index.blade.php` runs
      // `where('sectionId','==',id)` beside the array-contains on `sectionIds`.
      // Session 28 stopped deleting them during a save that carried no
      // replacement; they are now not deleted at all, because deleting the
      // panel's own record of its own selection is what makes a driver drop out
      // of the panel views that read it.
      expect(source, contains("legacyFields['serviceType'] = savedServiceTypes.first;"));
      expect(source, contains("legacyFields['sectionId'] = savedSectionIds.first;"));

      for (final String field in <String>['serviceType', 'sectionId']) {
        final int deleted =
            RegExp("'" + field + "': FieldValue\\.delete\\(\\)").allMatches(source).length;
        expect(deleted, 0,
            reason: '$field is the panel\'s own field - it must never be deleted');
      }

      // And a save that carries no service must still write neither field, so
      // saving a push token cannot mirror an answer the model never held.
      expect(source, contains('if (savedServiceTypes != null && savedServiceTypes.isNotEmpty) {'));
      expect(source, contains('if (savedSectionIds != null && savedSectionIds.isNotEmpty) {'));
    });
  });

  group('the driver type is exactly what the Admin Panel selected', () {
    setUp(() {
      Constant.sectionModels.clear();
    });

    tearDown(() {
      Constant.sectionModels.clear();
    });

    test('the recorded service wins over the sections it sits in', () async {
      Constant.sectionModels['631852d1bc978'] =
          SectionModel(id: '631852d1bc978', name: 'Cab Service', serviceTypeFlag: 'cab-service');

      // Live shape, and there are eight of these in the project: a driver the
      // panel records - and lists, and filters - as a delivery rider, whose
      // `sectionId` is stale demo data pointing at Cab Service. Session 28 let
      // the section override the panel here, to heal documents the old
      // `toJson()` had corrupted; that writer is gone, so the override is now
      // the only remaining way for the app to contradict the panel.
      final UserModel driver = UserModel(
        id: '80RqJ6t85n',
        role: Constant.userRoleDriver,
        sectionIds: <String>['631852d1bc978'],
        serviceTypes: <String>['delivery-service'],
      );

      expect(await SignupController.resolveServiceTypes(driver), <String>['delivery-service'],
          reason: 'the driver type must be exactly what the Admin Panel selected');
      expect(driver.serviceTypes, <String>['delivery-service'],
          reason: 'nothing was derived, so nothing on the model changed');
    });

    test('a cab driver the panel recorded stays a cab driver', () async {
      // The client's report, as a test: reopening the app must not turn this
      // driver into a delivery rider, whatever else is on the document.
      Constant.sectionModels['631852d1bc978'] =
          SectionModel(id: '631852d1bc978', name: 'Cab Service', serviceTypeFlag: 'cab-service');

      final UserModel legacy = UserModel.fromJson(<String, dynamic>{
        'id': '0IOAS5ZxHdWfH7aXGBi4aeAhv582',
        'role': Constant.userRoleDriver,
        // Only the legacy singular fields, which is how 213 of the project's
        // 282 drivers are actually stored.
        'serviceType': 'cab-service',
        'sectionId': '631852d1bc978',
      });

      expect(await SignupController.resolveServiceTypes(legacy), <String>['cab-service']);

      // And the save that follows a launch keeps both shapes saying cab.
      final Map<String, dynamic> saved = legacy.toJson();
      expect(saved['serviceTypes'], <String>['cab-service']);
      expect(saved['sectionIds'], <String>['631852d1bc978']);
    });

    test('a blank serviceType is no answer at all, and is never stored', () async {
      Constant.sectionModels['6285ddbfd9598'] =
          SectionModel(id: '6285ddbfd9598', name: 'Food Delivery', serviceTypeFlag: 'delivery-service');

      // `serviceType: ''` is a real shape - eight driver documents carry it.
      // Read as `['']` it matched no dashboard case, fell through to the
      // delivery default, and was then written back as the driver's answer.
      final UserModel blank = UserModel.fromJson(<String, dynamic>{
        'id': '3MYtnCd6np',
        'role': Constant.userRoleDriver,
        'serviceType': '',
        'sectionId': '',
      });

      expect(blank.serviceTypes, isNull, reason: 'a blank string is not a service');
      expect(blank.sectionIds, isNull, reason: 'a blank string is not a section');
      expect(blank.toJson().containsKey('serviceTypes'), isFalse,
          reason: 'and it must never be written back as one');
      expect(await SignupController.resolveServiceTypes(blank), isEmpty);
    });

    test('an empty plural list does not shadow the panel\'s legacy field', () async {
      Constant.sectionModels['631852d1bc978'] =
          SectionModel(id: '631852d1bc978', name: 'Cab Service', serviceTypeFlag: 'cab-service');

      final UserModel driver = UserModel.fromJson(<String, dynamic>{
        'id': 'emptyPlural',
        'role': Constant.userRoleDriver,
        'serviceTypes': <String>[],
        'serviceType': 'rental-service',
        'sectionIds': <String>[],
        'sectionId': '631852d1bc978',
      });

      expect(driver.serviceTypes, <String>['rental-service'],
          reason: 'an empty list is not an answer, so the recorded one still counts');
      expect(driver.sectionIds, <String>['631852d1bc978']);
      expect(await SignupController.resolveServiceTypes(driver), <String>['rental-service']);
    });

    test('the sections still answer for a document that records no service', () async {
      Constant.sectionModels['631852d1bc978'] =
          SectionModel(id: '631852d1bc978', name: 'Cab Service', serviceTypeFlag: 'cab-service');

      // 29 drivers have neither service field. The sections are what is left
      // to go on, and the derived answer is kept so it gets persisted.
      final UserModel driver = UserModel(
        id: 'PTfrlCUMXU',
        role: Constant.userRoleDriver,
        sectionIds: <String>['631852d1bc978'],
      );

      expect(await SignupController.resolveServiceTypes(driver), <String>['cab-service']);
      expect(driver.serviceTypes, <String>['cab-service'],
          reason: 'derived, so it is recorded for the next reader');
    });

    test('duplicate flags across sections collapse to one', () async {
      Constant.sectionModels['a'] = SectionModel(id: 'a', serviceTypeFlag: 'delivery-service');
      Constant.sectionModels['b'] = SectionModel(id: 'b', serviceTypeFlag: 'delivery-service');
      Constant.sectionModels['c'] = SectionModel(id: 'c', serviceTypeFlag: 'cab-service');

      final UserModel driver = UserModel(sectionIds: <String>['a', 'b', 'c']);

      expect(await SignupController.resolveServiceTypes(driver), <String>['delivery-service', 'cab-service']);
    });

    test('a driver with no sections keeps whatever the document said', () async {
      final UserModel driver = UserModel(serviceTypes: <String>['rental-service']);

      expect(await SignupController.resolveServiceTypes(driver), <String>['rental-service']);
    });

    test('there is one implementation of the rules, not three', () {
      // login_controller and otp_screen each carried their own copy, which is
      // how the same driver could land in different sections depending on how
      // they signed in.
      final Iterable<File> libFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'));

      final List<String> owners = <String>[];
      for (final File file in libFiles) {
        if (file.readAsStringSync().contains('Get.offAll(const MultiServiceDashboardScreen())')) {
          owners.add(file.path);
        }
      }

      expect(owners, <String>['lib/controllers/signup_controller.dart'],
          reason: 'only SignupController.navigateByUserModel may choose the dashboard');
    });
  });

  test('the ride-offer card follows the offer it is showing', () {
    final String source = read('lib/app/cab_screen/bidding_request_card.dart');

    // Both carousels build this card from a `ListView` itemBuilder, which runs
    // after the enclosing GetX builder has returned - so `myBids` and
    // `inFlight`, read inside the card, were never subscribed to. Withdraw took
    // the offer off the table and the card went on showing Withdraw, so a
    // second tap said "This offer is no longer available" and the button looked
    // dead.
    expect(source, contains('return Obx(() => _card(context));'));
    expect(source, contains('final RideBidModel? mine = controller.myBids[request.id];'));
    expect(source.indexOf('Obx(() => _card(context))'), lessThan(source.indexOf('controller.myBids[request.id]')),
        reason: 'the observable reads must happen inside the Obx');
  });

  test('the signed-in driver reaches memory on the read, not on the write', () {
    final String source = read('lib/controllers/splash_controller.dart');

    final int assign = source.indexOf('Constant.userModel = userModel;');
    final int write = source.indexOf('unawaited(FireStoreUtils.updateUser(userModel));');

    expect(assign, greaterThan(-1),
        reason: 'the splash must publish the profile it just read');
    expect(write, greaterThan(-1));
    expect(assign, lessThan(write),
        reason: 'publishing it must not depend on a write that is no longer awaited');
  });
}
