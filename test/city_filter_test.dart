import 'package:driver/models/vehicle_type.dart';
import 'package:driver/utils/city_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final List<VehicleType> types = <VehicleType>[
    VehicleType.fromJson(<String, dynamic>{'id': 'car', 'name': 'Car'}),
    VehicleType.fromJson(<String, dynamic>{'id': 'bikeLahore', 'zoneIds': <String>['lahore']}),
    VehicleType.fromJson(<String, dynamic>{'id': 'rickshawKohat', 'zoneIds': <String>['kohat', 'pk']}),
    VehicleType.fromJson(<String, dynamic>{'id': 'van', 'zoneIds': <String>[]}),
  ];
  List<String?> ids(String? zone, {String? keepId}) =>
      CityFilter.keep(types, zone, zoneIdsOf: (VehicleType t) => t.zoneIds, idOf: (VehicleType t) => t.id, keepId: keepId).map((VehicleType t) => t.id).toList();

  test('nothing ticked = every city (all existing vehicle types)', () {
    expect(ids('kohat'), containsAll(<String>['car', 'van']));
  });
  test('only the driver city, order unchanged', () {
    expect(ids('kohat'), <String>['car', 'rickshawKohat', 'van']);
    expect(ids('lahore'), <String>['car', 'bikeLahore', 'van']);
    expect(ids('pk'), <String>['car', 'rickshawKohat', 'van']);
  });
  test('no zone yet = list as read', () {
    expect(ids(null), <String>['car', 'bikeLahore', 'rickshawKohat', 'van']);
    expect(ids(''), <String>['car', 'bikeLahore', 'rickshawKohat', 'van']);
  });
  test('the vehicle a driver already has is never taken away', () {
    expect(ids('kohat', keepId: 'bikeLahore'), <String>['car', 'bikeLahore', 'rickshawKohat', 'van']);
    expect(ids('kohat', keepId: ''), <String>['car', 'rickshawKohat', 'van']);
  });
  test('zoneIds is read, never written back into the driver profile', () {
    expect(types[1].zoneIds, <String>['lahore']);
    expect(types[1].toJson().containsKey('zoneIds'), isFalse);
    expect(types[0].zoneIds, isNull);
    expect(CityFilter.parseZoneIds(<dynamic>['a', 1, '', 'b']), <String>['a', 'b']);
    expect(CityFilter.parseZoneIds('a'), isNull);
  });
}
