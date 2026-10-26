// Session 43 - the rest of the driver app, at sizes other than the one it was
// drawn on.
//
// Session 33 did this for the cab screens. The same shapes turned up on the
// others:
//
//   * an **inflexible child of a Row**, which is laid out with unbounded width,
//     so a long name, email, section or translation runs the row off the card;
//   * a **size worked out for one phone** - six 50 px OTP cells, a 10 px AppBar
//     subtitle, a 1.1 grid ratio;
//   * a **Column that does not scroll** holding text fields or a list, which the
//     keyboard (or a sixth document) pushes off a short phone.
//
// The screens build GetX controllers and Firebase listeners, so - as in
// Session 33 - each layout is mirrored rather than pumped, and the screens
// themselves are pinned at source level with comment lines removed.

import 'dart:io';

import 'package:driver/app/auth_screen/otp_screen.dart';
import 'package:driver/app/change_language/change_language_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Source with comment lines dropped, so a comment quoting old code is not
/// mistaken for the code.
String code(String path) =>
    File(path).readAsStringSync().split('\n').where((String line) => !line.trimLeft().startsWith('//')).join('\n');

int count(String source, String pattern) => RegExp(pattern).allMatches(source).length;

/// Pumps [child] as a Scaffold body on a display [size] logical pixels.
Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

/// Whether the last pump reported an overflow (one, or several at once).
bool overflowed(WidgetTester tester) {
  final String error = tester.takeException()?.toString() ?? '';
  return error.contains('overflowed') || error.contains('Multiple exceptions');
}

const String longText = 'Lahore Nationwide Premium Riders and Deliveries';

void main() {
  group('OTP cells', () {
    /// The row `MaterialPinRow` builds (pin_code_fields 9.4.0): each cell
    /// `theme.cellSize.width` wide with an 8 px gap between, inside the OTP
    /// screen's 24 px + 10 px padding.
    Widget otpRow(double Function(double maxWidth) cellFor) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
                  final double cell = cellFor(constraints.maxWidth);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (int i = 0; i < 6; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: 8),
                        SizedBox(width: cell, height: cell),
                      ],
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('six 50 px cells overflow a 360 px phone, the sized cells do not', (WidgetTester tester) async {
      await pumpAt(tester, const Size(360, 640), otpRow((_) => 50));
      expect(overflowed(tester), isTrue, reason: 'the probe: the old fixed cells must overflow here');

      for (final double width in <double>[320, 360, 390]) {
        await pumpAt(tester, Size(width, 640), otpRow(OtpScreen.pinCellExtent));
        expect(overflowed(tester), isFalse, reason: 'OTP row overflows at $width px');
      }
    });

    test('cells stay 50 px wherever they already fitted, and shrink only below that', () {
      expect(OtpScreen.pinCellExtent(412 - 68), 50);
      expect(OtpScreen.pinCellExtent(700), 50);
      expect(OtpScreen.pinCellExtent(360 - 68), 42);
      expect(OtpScreen.pinCellExtent(320 - 68), 35);
      for (final double width in <double>[252, 292, 307, 322, 340, 344]) {
        final double cell = OtpScreen.pinCellExtent(width);
        expect(6 * cell + 5 * 8, lessThanOrEqualTo(width), reason: 'at $width px');
      }
    });

    test('the screen sizes its cells from the width it has (source)', () {
      final String source = code('lib/app/auth_screen/otp_screen.dart');
      expect(source, contains('LayoutBuilder(builder: (context, constraints) {'));
      expect(source, contains('pinCellExtent(constraints.maxWidth)'));
      expect(source, contains('cellSize: Size(cell, cell),'));
      expect(source, isNot(contains('cellSize: const Size(50, 50)')));
    });
  });

  group('rows with an inflexible child', () {
    testWidgets('the "Section:" line on the order lists', (WidgetTester tester) async {
      Widget row({required bool flexible}) {
        const Text name = Text(longText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13));
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: <Widget>[
            const Text('Section: ', style: TextStyle(fontSize: 13)),
            if (flexible) const Flexible(child: name) else name,
          ]),
        );
      }

      await pumpAt(tester, const Size(320, 640), row(flexible: false));
      expect(overflowed(tester), isTrue, reason: 'the probe');
      await pumpAt(tester, const Size(320, 640), row(flexible: true));
      expect(overflowed(tester), isFalse);
    });

    test('all three order lists shorten the section name (source)', () {
      for (final String path in <String>[
        'lib/app/cab_screen/cab_order_list_screen.dart',
        'lib/app/parcel_screen/parcel_order_list_screen.dart',
        'lib/app/rental_service/rental_order_list_screen.dart',
      ]) {
        expect(
          count(code(path), r'Flexible\(\s*child: Text\(\s*Constant\.sectionNameFromId\(order\.sectionId\),\s*maxLines: 1,\s*overflow: TextOverflow\.ellipsis,'),
          1,
          reason: path,
        );
      }
    });

    testWidgets('"Your Setup is pending / Setup now" in a longer language', (WidgetTester tester) async {
      Widget row({required bool flexible}) {
        const Text pending = Text('Your setup is still pending for this account', style: TextStyle(fontSize: 16));
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: <Widget>[
            if (flexible) const Flexible(child: pending) else pending,
            const SizedBox(width: 10),
            const Text('Setup now', style: TextStyle(fontSize: 16)),
          ]),
        );
      }

      await pumpAt(tester, const Size(320, 640), row(flexible: false));
      expect(overflowed(tester), isTrue, reason: 'the probe');
      await pumpAt(tester, const Size(320, 640), row(flexible: true));
      expect(overflowed(tester), isFalse);
    });

    test('all five withdraw methods let the pending text wrap (source)', () {
      final String source = code('lib/app/withdraw_method_setup_screens/withdraw_method_setup_screen.dart');
      expect(count(source, r'Flexible\(\s*child: Text\(\s*"Your Setup is pending"\.tr,'), 5);
      expect(count(source, r'"Your Setup is pending"\.tr,'), 5);
    });

    testWidgets('the customer row on the rental order details', (WidgetTester tester) async {
      Widget row({required bool flexible}) {
        final Widget details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Muhammad Abdullah Khan', style: TextStyle(fontSize: 18)),
            Text('muhammad.abdullah.khan.customer@gmail.com',
                maxLines: flexible ? 1 : null, overflow: flexible ? TextOverflow.ellipsis : null, style: const TextStyle(fontSize: 14)),
            const Text('03001234567', style: TextStyle(fontSize: 16)),
          ],
        );
        final Widget person = Row(children: <Widget>[
          const SizedBox(width: 52, height: 52),
          const SizedBox(width: 20),
          if (flexible) Expanded(child: details) else details,
        ]);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (flexible) Expanded(child: person) else person,
              if (flexible) const SizedBox(width: 8),
              const SizedBox(width: 42, height: 42),
            ],
          ),
        );
      }

      await pumpAt(tester, const Size(360, 640), row(flexible: false));
      expect(overflowed(tester), isTrue, reason: 'the probe');
      await pumpAt(tester, const Size(360, 640), row(flexible: true));
      expect(overflowed(tester), isFalse);
    });

    test('the rental customer row and both summary panels (source)', () {
      final String rental = code('lib/app/rental_service/rental_order_details_screen.dart');
      expect(count(rental, r"Expanded\(\s*child: Column\(\s*crossAxisAlignment: CrossAxisAlignment\.start,\s*children: \[\s*Text\(\s*controller\.userData\.value\?\.fullName\(\)"), 1);
      expect(count(rental, r"controller\.userData\.value\?\.email \?\? '',\s*maxLines: 1,\s*overflow: TextOverflow\.ellipsis,"), 1);

      for (final String path in <String>[
        'lib/app/rental_service/rental_order_details_screen.dart',
        'lib/app/parcel_screen/parcel_order_details.dart',
      ]) {
        final String source = code(path);
        final int start = source.indexOf('Widget _summaryTile(');
        expect(start, greaterThan(-1), reason: path);
        final String tile = source.substring(start);
        expect(count(tile, r'Expanded\(\s*child: Text\(title,'), 1, reason: '$path: the tax title is inflexible again');
        expect(tile, contains('textAlign: TextAlign.end,'), reason: path);
      }
    });

    test('the parcel details carry the cab screen\'s fixes (source)', () {
      final String source = code('lib/app/parcel_screen/parcel_order_details.dart');
      expect(count(source, r'Expanded\(\s*child: _iconTile\('), 3, reason: 'the distance/weight/rate strip');
      expect(count(source, r'Flexible\(\s*child: Text\(\s*controller\.parcelOrder\.value\.parcelType'), 1);
    });

    testWidgets('a long help & support message beside the avatar', (WidgetTester tester) async {
      Widget bubble({required bool flexible}) {
        final Widget message = Container(
          constraints: const BoxConstraints(maxWidth: 360 * 0.75),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Text('$longText $longText $longText', softWrap: true),
        );
        return Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
          child: Container(
            padding: const EdgeInsets.only(left: 80, right: 10, top: 10, bottom: 10),
            child: Align(
              alignment: Alignment.topRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      if (flexible) Flexible(child: message) else message,
                      const Padding(padding: EdgeInsets.only(left: 5), child: SizedBox(width: 18, height: 18)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }

      await pumpAt(tester, const Size(360, 640), bubble(flexible: false));
      expect(overflowed(tester), isTrue, reason: 'the probe');
      await pumpAt(tester, const Size(360, 640), bubble(flexible: true));
      expect(overflowed(tester), isFalse);
    });

    test('the help & support bubble is flexible (source)', () {
      expect(count(code('lib/app/help_support_screen/help_support_screen.dart'), r'Flexible\(child: data\.messageType == "text"'), 1);
    });

    test('dashboard names stay on one line, as on the cab dashboard (source)', () {
      for (final String path in <String>[
        'lib/app/dash_board_screen/dash_board_screen.dart',
        'lib/app/parcel_screen/parcel_dashboard_screen.dart',
        'lib/app/rental_service/rental_dashboard_screen.dart',
        'lib/app/owner_screen/owner_dashboard_screen.dart',
      ]) {
        final String source = code(path);
        expect(count(source, r"'Welcome Back 👋'\.tr,\s*maxLines: 1,\s*overflow: TextOverflow\.ellipsis,"), 1, reason: path);
        expect(count(source, r'fullName\(\)\.tr(?: : "")?,\s*maxLines: 1,\s*overflow: TextOverflow\.ellipsis,'), 1, reason: path);
      }
    });

    testWidgets('a long zone or vehicle name inside a dropdown', (WidgetTester tester) async {
      await pumpAt(
        tester,
        const Size(320, 640),
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: longText,
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(value: longText, child: Text(longText, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (_) {},
          ),
        ),
      );
      expect(overflowed(tester), isFalse);
    });

    test('every dropdown on the signup, owner orders and driver form fills its field (source)', () {
      for (final String path in <String>[
        'lib/app/auth_screen/signup_screen.dart',
        'lib/app/owner_screen/owner_order_list.dart',
        'lib/app/owner_screen/driver_create_screen.dart',
      ]) {
        final String source = code(path);
        final int dropdowns = count(source, r'DropdownButtonFormField<[^>]*>\(');
        expect(dropdowns, greaterThan(0), reason: path);
        expect(count(source, r'DropdownButtonFormField<[^>]*>\(\s*isExpanded: true,'), dropdowns, reason: path);
      }
    });
  });

  group('sizes worked out for one phone', () {
    testWidgets('language cells are never shorter than the flag and name', (WidgetTester tester) async {
      Widget grid(double Function(double gridWidth) ratio) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 20),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) => GridView.count(
                    crossAxisCount: 2,
                    childAspectRatio: ratio(constraints.maxWidth),
                    crossAxisSpacing: 5,
                    mainAxisSpacing: 1,
                    children: <Widget>[
                      for (final String name in <String>['English', 'Arabic', 'Portuguese (Brazil)', 'Hindi'])
                        Container(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: <Widget>[
                            const SizedBox(width: 80, height: 80),
                            const SizedBox(height: 5),
                            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }

      await pumpAt(tester, const Size(320, 640), grid((_) => 1.1));
      expect(overflowed(tester), isTrue, reason: 'the probe: 1.1 is too short a cell at 320 px');
      await pumpAt(tester, const Size(320, 640), grid((double width) => ChangeLanguageScreen.languageCellAspectRatio(width, TextScaler.noScaling)));
      expect(overflowed(tester), isFalse);
    });

    test('the ordinary phone keeps the 1.1 shape (unit + source)', () {
      expect(ChangeLanguageScreen.languageCellAspectRatio(360 - 32, TextScaler.noScaling), 1.1);
      expect(ChangeLanguageScreen.languageCellAspectRatio(768 - 32, TextScaler.noScaling), 1.1);
      expect(ChangeLanguageScreen.languageCellAspectRatio(320 - 32, TextScaler.noScaling), lessThan(1.1));

      final String source = code('lib/app/change_language/change_language_screen.dart');
      expect(source, contains('childAspectRatio: languageCellAspectRatio(constraints.maxWidth, MediaQuery.textScalerOf(context)),'));
      expect(source, isNot(contains('(1.1 / 1)')));
    });
  });

  group('screens the keyboard or a long list pushes off a short phone', () {
    testWidgets('the document list scrolls instead of overflowing', (WidgetTester tester) async {
      Widget screen({required bool flexible}) {
        final Widget card = Container(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: ListView.separated(
              itemCount: 8,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemBuilder: (BuildContext context, int index) => const SizedBox(height: 60),
              separatorBuilder: (BuildContext context, int index) =>
                  const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
            ),
          ),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Document Verification', style: TextStyle(fontSize: 22)),
              const SizedBox(height: 5),
              const Text('Upload your ID Proof to complete the verification process.'),
              const SizedBox(height: 40),
              if (flexible) Flexible(child: card) else card,
            ],
          ),
        );
      }

      await pumpAt(tester, const Size(360, 640), screen(flexible: false));
      expect(overflowed(tester), isTrue, reason: 'the probe');
      await pumpAt(tester, const Size(360, 640), screen(flexible: true));
      expect(overflowed(tester), isFalse);
    });

    test('the verification list is flexible (source)', () {
      expect(count(code('lib/app/verification_screen/verification_screen.dart'), r'Flexible\(\s*child: Container\(\s*decoration: ShapeDecoration\('), 1);
    });

    test('login, change password and the withdraw-method dialogs scroll (source)', () {
      expect(code('lib/app/auth_screen/login_screen.dart'), contains('body: SingleChildScrollView('));
      expect(count(code('lib/app/change_password_screen/change_password_screen.dart'), r': SingleChildScrollView\(\s*child: Padding\('), 1);
      expect(
        count(code('lib/app/withdraw_method_setup_screens/withdraw_method_setup_screen.dart'),
            r'child: SingleChildScrollView\(\s*child: SizedBox\(\s*width: 500,'),
        4,
        reason: 'FlutterWave, PayPal, RazorPay and Stripe',
      );
    });
  });
}
