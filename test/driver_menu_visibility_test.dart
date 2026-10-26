import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:driver/utils/driver_menu_visibility.dart';

/// Session 4: "Hide Change Section" and "Hide Vehicle information" in the
/// Driver App.
///
/// Both requirements are about **reachability**, so testing the flag alone
/// would prove nothing - a flag nobody consults hides nothing. These tests
/// therefore read the dashboard sources and assert that every navigation site
/// which can reach either screen sits behind [DriverMenuVisibility]. That is
/// the property the client asked for, and it is the one that breaks if someone
/// later adds a fifth dashboard or re-adds an unguarded entry.
void main() {
  /// The four driver dashboards that render a drawer. `owner_dashboard_screen`
  /// has its own drawer but never offered either entry.
  const List<String> dashboards = <String>[
    'lib/app/cab_screen/cab_dashboard_screen.dart',
    'lib/app/rental_service/rental_dashboard_screen.dart',
    'lib/app/parcel_screen/parcel_dashboard_screen.dart',
    'lib/app/dash_board_screen/dash_board_screen.dart',
  ];

  /// The two dashboards that host `VehicleInformationScreen` in drawer slot 6.
  const List<String> vehicleDashboards = <String>[
    'lib/app/cab_screen/cab_dashboard_screen.dart',
    'lib/app/rental_service/rental_dashboard_screen.dart',
  ];

  String read(String path) {
    final File file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing - the dashboard list in this test is stale');
    return file.readAsStringSync();
  }

  /// Every `.dart` file under `lib/`, so "is there an unguarded entry anywhere"
  /// is answered across the app rather than across a list this test maintains.
  List<File> libDartFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList();

  int occurrences(String haystack, String needle) {
    if (needle.isEmpty) return 0;
    int count = 0;
    int index = haystack.indexOf(needle);
    while (index != -1) {
      count++;
      index = haystack.indexOf(needle, index + needle.length);
    }
    return count;
  }

  group('the flags themselves', () {
    test('both client-requested entries are hidden', () {
      expect(DriverMenuVisibility.showChangeSection, isFalse);
      expect(DriverMenuVisibility.showVehicleInformation, isFalse);
    });

    test('the vehicle-information drawer slot is still 6', () {
      // The body of the cab and rental dashboards renders
      // VehicleInformationScreen for this slot. If the constant and the body
      // ever disagree, the entry would open the wrong screen the moment it is
      // restored.
      expect(DriverMenuVisibility.vehicleInformationDrawerIndex, 6);
    });
  });

  group('Change Section is unreachable', () {
    test('every navigation to ChangeSectionScreen is behind the flag', () {
      int navigationSites = 0;
      for (final File file in libDartFiles()) {
        final String source = file.readAsStringSync();
        // The screen's own definition file is not a navigation site.
        if (file.path.endsWith('change_section_screen.dart')) continue;
        navigationSites += occurrences(source, 'ChangeSectionScreen()');
      }
      expect(navigationSites, 4, reason: 'expected exactly the four dashboard drawer entries');

      for (final String path in dashboards) {
        final String source = read(path);
        expect(
          occurrences(source, 'ChangeSectionScreen()'),
          occurrences(source, 'DriverMenuVisibility.showChangeSection'),
          reason: '$path navigates to Change Section without the visibility guard',
        );
      }
    });

    test('the screen and its controller are retained, not deleted', () {
      // Hiding the entry must not cost the app the only code that knows how to
      // rewrite sectionNames/vehicleDetails consistently.
      expect(File('lib/app/change_section_screen/change_section_screen.dart').existsSync(), isTrue);
      expect(File('lib/controllers/change_section_controller.dart').existsSync(), isTrue);
    });
  });

  group('Vehicle Information is unreachable', () {
    test('the drawer entry is behind the flag in both dashboards', () {
      for (final String path in vehicleDashboards) {
        final String source = read(path);
        expect(
          occurrences(source, 'DriverMenuVisibility.showVehicleInformation'),
          1,
          reason: '$path must guard its Vehicle Information entry exactly once',
        );
        expect(
          occurrences(source, 'DriverMenuVisibility.vehicleInformationDrawerIndex'),
          1,
          reason: '$path must write the slot through the named constant',
        );
      }
    });

    test('only the cab and rental dashboards can render the screen', () {
      // Each dashboard owns its own drawerIndex space - the owner dashboard's
      // slot 6 is Change Language, not vehicle information - so the guarantee
      // is scoped to the two files that actually map the slot to the screen.
      final List<String> renderingFiles = <String>[];
      for (final File file in libDartFiles()) {
        if (file.path.endsWith('vehicle_information_screen.dart')) continue;
        if (file.readAsStringSync().contains('VehicleInformationScreen(')) {
          renderingFiles.add(file.path);
        }
      }
      expect(renderingFiles..sort(), vehicleDashboards.toList()..sort());
    });

    test('the guarded entry is the only writer of the slot in those two files', () {
      for (final String path in vehicleDashboards) {
        final String source = read(path);
        expect(
          source.contains('drawerIndex.value = 6'),
          isFalse,
          reason: '$path writes the vehicle-information slot by literal, bypassing the guard',
        );
        // One writer, and it is the one inside the guard.
        expect(occurrences(source, 'drawerIndex.value = DriverMenuVisibility.vehicleInformationDrawerIndex'), 1);
      }
    });

    test('the screen, its controller and the vehicle model are retained', () {
      expect(File('lib/app/vehicle_information_screen/vehicle_information_screen.dart').existsSync(), isTrue);
      expect(File('lib/controllers/vehicle_information_controller.dart').existsSync(), isTrue);

      // The ride-facing vehicle data must survive: bidding puts it on every
      // offer, and a published trip carries it too.
      expect(File('lib/models/user_model.dart').readAsStringSync().contains('vehicleDetails'), isTrue);
      expect(File('lib/services/bidding_service.dart').readAsStringSync().contains('vehicleDetails'), isTrue);
      expect(File('lib/services/driver_trip_service.dart').readAsStringSync().contains('vehicleDetails'), isTrue);
    });

    test('driver onboarding can still capture vehicle details', () {
      // Signup and the owner's "add driver" form are how vehicleDetails is
      // populated. Neither is the screen the client asked to hide, and hiding
      // either would make it impossible to onboard a driver at all.
      expect(File('lib/controllers/signup_controller.dart').readAsStringSync().contains('vehicleDetails'), isTrue);
      expect(File('lib/controllers/driver_create_controller.dart').readAsStringSync().contains('vehicleDetails'), isTrue);
    });
  });
}
