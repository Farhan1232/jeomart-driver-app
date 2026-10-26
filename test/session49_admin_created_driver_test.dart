import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Session 49 - a delivery driver created in the Admin Panel receives orders.
///
/// The panel writes `vehicleDetails: {}` for a delivery driver (no vehicle).
/// `removeNulls` - the clean-up every profile save runs first - removed that
/// empty map from inside its own `forEach` and threw, so the driver's profile
/// could never be saved: login never stored the push token, and the dispatcher
/// skips a driver without one.
void main() {
  group('removeNulls', () {
    test('an empty nested map is dropped, without throwing', () {
      final Map<String, dynamic> data = <String, dynamic>{
        'id': 'd1',
        'vehicleDetails': <String, dynamic>{},
      };
      expect(() => FireStoreUtils.removeNulls(data), returnsNormally);
      expect(data, <String, dynamic>{'id': 'd1'});
    });

    test('several empty nested maps in one profile', () {
      final Map<String, dynamic> data = <String, dynamic>{
        'a': <String, dynamic>{},
        'b': 1,
        'c': <String, dynamic>{},
        'd': <String, dynamic>{'x': null},
      };
      expect(FireStoreUtils.removeNulls(data), <String, dynamic>{'b': 1});
    });

    test('top-level nulls go, everything else stays as it was', () {
      final Map<String, dynamic> data = <String, dynamic>{
        'id': 'd1',
        'fcmToken': 'token',
        'carPictureURL': null,
        'isActive': false,
        'wallet_amount': 0,
        'serviceTypes': <String>['delivery-service'],
        'empty list stays': <String>[],
        'empty string stays': '',
      };
      expect(FireStoreUtils.removeNulls(data), <String, dynamic>{
        'id': 'd1',
        'fcmToken': 'token',
        'isActive': false,
        'wallet_amount': 0,
        'serviceTypes': <String>['delivery-service'],
        'empty list stays': <String>[],
        'empty string stays': '',
      });
    });

    test('a nested map keeps its values and loses only its nulls, at any depth', () {
      final Map<String, dynamic> data = <String, dynamic>{
        'vehicleDetails': <String, dynamic>{
          'section1': <String, dynamic>{'vehicleId': 'v1', 'carBrand': null},
          'section2': <String, dynamic>{'carBrand': null},
        },
        'location': <String, dynamic>{'latitude': 31.5, 'longitude': 74.3},
      };
      expect(FireStoreUtils.removeNulls(data), <String, dynamic>{
        'vehicleDetails': <String, dynamic>{
          'section1': <String, dynamic>{'vehicleId': 'v1'},
        },
        'location': <String, dynamic>{'latitude': 31.5, 'longitude': 74.3},
      });
    });

    test('the same map is cleaned and returned, as before', () {
      final Map<String, dynamic> data = <String, dynamic>{'a': null, 'b': 2};
      expect(identical(FireStoreUtils.removeNulls(data), data), isTrue);
    });
  });

  group('a driver shaped the way the Admin Panel creates one', () {
    // Field for field what `drivers/create` / `drivers/edit` store for a
    // delivery-only driver (synthetic values).
    Map<String, dynamic> adminCreatedDeliveryDriver() => <String, dynamic>{
          'id': 'adminDriver1',
          'firstName': 'Test',
          'lastName': 'Delivery',
          'email': 'test.delivery@example.com',
          'role': 'driver',
          'active': true,
          'isActive': true,
          'isDocumentVerify': false,
          'isAutoVerify': true,
          'isOwner': false,
          'ownerId': null,
          'vendorID': '',
          'zoneId': 'zone1',
          'wallet_amount': 0,
          'rotation': 0.0,
          'provider': 'email',
          'appIdentifier': 'android',
          'phoneNumber': '3000000000',
          'profilePictureURL': '',
          'carPictureURL': null,
          'carProofPictureURL': null,
          'driverProofPictureURL': null,
          'carInfo': null,
          'carColor': null,
          'carRate': null,
          'sectionIds': <dynamic>['6285ddbfd9598'],
          'serviceTypes': <dynamic>['delivery-service'],
          'sectionNames': <String, dynamic>{'6285ddbfd9598': 'Food Delivery'},
          'vehicleDetails': <String, dynamic>{},
          'userBankDetails': <String, dynamic>{
            'bankName': '',
            'branchName': '',
            'holderName': '',
            'accountNumber': '',
            'otherDetails': '',
          },
          'location': <String, dynamic>{'latitude': 32.3, 'longitude': 73.7},
          'coordinates': const GeoPoint(32.3, 73.7),
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 18)),
        };

    test('its profile can be prepared for saving, push token included', () {
      final UserModel driver = UserModel.fromJson(adminCreatedDeliveryDriver());
      driver.fcmToken = 'device-token';

      late Map<String, dynamic> data;
      expect(() => data = FireStoreUtils.removeNulls(driver.toJson()), returnsNormally);
      expect(data['fcmToken'], 'device-token', reason: 'the login saves the token the dispatcher needs');
      expect(data.containsKey('vehicleDetails'), isFalse, reason: 'an empty map is left out, so the stored {} stays as it is');
    });

    test('the rest of updateUser reads the prepared profile without trouble', () {
      final Map<String, dynamic> data = FireStoreUtils.removeNulls(UserModel.fromJson(adminCreatedDeliveryDriver()).toJson());
      expect(data['serviceTypes'] as List<String>?, <String>['delivery-service']);
      expect(data['sectionIds'] as List<String>?, <String>['6285ddbfd9598']);
    });
  });
}
