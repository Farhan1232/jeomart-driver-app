import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/models/currency_model.dart';
import 'package:driver/models/language_model.dart';
import 'package:driver/models/mail_setting.dart';
import 'package:driver/models/section_model.dart';
import 'package:driver/models/tax_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/utils/bidding_settings.dart';
import 'package:driver/utils/driver_trip_settings.dart';
import 'package:driver/utils/my_trips_access.dart';
import 'package:driver/utils/preferences.dart';
import 'package:driver/widget/permission_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:get/get.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:driver/utils/network_timeout.dart';

class Constant {
  static String userRoleDriver = 'driver';
  static String userRoleCustomer = 'customer';
  static String userRoleVendor = 'vendor';

  static ShippingAddress selectedLocation = ShippingAddress();
  static LocationData? locationDataFinal;

  static UserModel? userModel;
  static Map<String, SectionModel> sectionModels = {};

  static SectionModel? sectionModelFor(String? sectionId) => sectionId != null && sectionId.isNotEmpty ? sectionModels[sectionId] : null;
  static const globalUrl = 'https://jeomart.com/';
  // static const globalUrl = "https://foodie.siswebapp.com/";

  static bool singleOrderReceive = false;
  static bool enableOTPTripStartForRental = true;
  static String driverLocationUpdate = '50';
  static String minimumDepositToRideAccept = '0.0';
  static String ownerMinimumDepositToRideAccept = '0.0';
  static String minimumAmountToWithdrawal = '0.0';

  static bool isDriverVerification = false;
  static bool isOwnerVerification = false;
  static bool enableOTPTripStart = false;

  static String parcelRadius = '0.0';
  static String rentalRadius = '0.0';

  static String mapAPIKey = "YOUR_GOOGLE_MAPS_API_KEY";
  static String placeHolderImage = "";
  static String defaultCountryCode = "";

  static String senderId = '';
  static String jsonNotificationFileURL = '';

  static String distanceType = "km";
  static String? referralAmount = "0.0";

  static String googlePlayLink = "";
  static String appStoreLink = "";
  static String appVersion = "";
  static String termsAndConditions = "";
  static String privacyPolicy = "";
  static String supportURL = "";
  static String minimumAmountToDeposit = "0.0";
  static String? mapType = "inappmap";
  static bool? autoApproveDriver = true;

  static const String orderPlaced = "Order Placed";
  static const String orderAccepted = "Order Accepted";
  static const String orderRejected = "Order Rejected";
  static const String driverPending = "Driver Pending";
  static const String driverAccepted = "Driver Accepted";
  static const String driverRejected = "Driver Rejected";
  static const String orderShipped = "Order Shipped";
  static const String orderInTransit = "In Transit";
  static const String orderCompleted = "Order Completed";
  static const String orderCancelled = "Order Cancelled";

  /// Global bidding / counter-offer configuration, from `settings/biddingSettings`.
  ///
  /// Defaults to everything off, so a missing or unreadable settings document
  /// leaves the driver's ride flow behaving exactly as it did before bidding
  /// existed.
  static BiddingSettings biddingSettings = BiddingSettings.disabled;

  /// Whether the driver should be shown bidding requests at all.
  ///
  /// Reduces to `biddingSettings.enabled` whenever the settings document has
  /// no `testUids` entry, which is its production state - see
  /// [BiddingSettings.testUids].
  static bool get isBiddingEnabled =>
      biddingSettings.isEnabledFor(auth.FirebaseAuth.instance.currentUser?.uid);

  /// Global configuration for driver-created trips, from
  /// `settings/driverTripsSettings`. Only holds how long a published trip
  /// stays visible to customers; a missing document means the 24-hour default.
  static DriverTripSettings driverTripSettings = DriverTripSettings.defaults;

  /// This driver's My Trips permission, as granted by the admin panel.
  ///
  /// Read straight off the signed-in driver's own `users/{uid}` document, so
  /// it follows the live listener the cab dashboard already keeps open and a
  /// revocation reaches the app without a restart.
  static MyTripsAccess get myTripsAccess => userModel?.myTripsAccess ?? MyTripsAccess.none;

  /// Whether My Trips should appear in navigation and accept a new trip.
  ///
  /// The device clock is what makes the UI react the instant a grant runs out;
  /// the grant itself ends at a server-anchored `expiresAt`, and the scheduled
  /// maintenance script closes it out on the server, so a driver cannot buy
  /// themselves more time by moving their phone's clock back.
  ///
  /// Two ways to be allowed, and the gate takes either: this driver's own
  /// grant, or the admin's global "every driver may post trips" switch. The
  /// switch is read off [driverTripSettings], whose default is off, so a
  /// settings document that has not loaded yet cannot open the feature up.
  static bool get hasMyTripsAccess =>
      MyTripsGate.showsInNavigation(myTripsAccess, DateTime.now(), openToAllDrivers: driverTripSettings.openToAllDrivers);

  static CurrencyModel? currencyModel;
  static List<TaxModel>? taxList = [];

  static MailSettings? mailSettings;
  static String walletTopup = "wallet_topup";
  static String newVendorSignup = "new_vendor_signup";
  static String payoutRequestStatus = "payout_request_status";
  static String payoutRequest = "payout_request";
  static String newOrderPlaced = "new_order_placed";

  static String scheduleOrder = "schedule_order";
  static String dineInPlaced = "dinein_placed";
  static String dineInCanceled = "dinein_canceled";
  static String dineinAccepted = "dinein_accepted";
  static String restaurantRejected = "restaurant_rejected";
  static String driverCompleted = "driver_completed";
  static String driverAcceptedNotification = "driver_accepted";
  static String newBidRequestNotification = "new_bid_request";
  static String bidOfferAcceptedNotification = "bid_offer_accepted";
  static String bidOfferRejectedNotification = "bid_offer_rejected";
  static String bidRequestClosedNotification = "bid_request_closed";
  static String tripReservedNotification = "trip_reserved";
  static String tripCancelledNotification = "trip_cancelled";
  static String tripCompletedNotification = "trip_completed";
  static String restaurantAccepted = "restaurant_accepted";
  static String takeawayCompleted = "takeaway_completed";
  static String parcelAccepted = "parcel_accepted";
  static String parcelCompleted = "parcel_completed";
  static String rentalAccepted = "rental_accepted";
  static String rentalCompleted = "rental_completed";

  /// Which map the in-app view draws: `osm` for the built-in OpenStreetMap
  /// view, anything else for Google Maps.
  ///
  /// The admin sets this in `settings/DriverNearBy`, which is read over the
  /// network at launch. Until that read lands this is the value below, and a
  /// screen that builds first draws its map from it - so the default has to be
  /// one that always works. OpenStreetMap needs no API key, so it draws on any
  /// project; a Google map on a project whose Maps key is rejected draws
  /// nothing at all, and "nothing at all" is a white screen where the driver
  /// expects the road. The real value is restored from the device by
  /// [restoreMapSettings] before the first frame anyway.
  static String selectedMapType = 'osm';

  /// Ticks once every time a settings read has been applied.
  ///
  /// [mapType] and [selectedMapType] are plain statics, so a screen that reads
  /// them cannot know when they change. Reading this inside an `Obx`/`GetX`
  /// builder subscribes that build to the settings load, which is what lets a
  /// first-ever launch redraw onto the right map the moment the read lands,
  /// instead of keeping whichever map it had to guess at.
  static final RxInt settingsRevision = 0.obs;

  /// The map configuration as the screens should draw it right now.
  ///
  /// Read this inside an `Obx`/`GetX` builder rather than reading [mapType]
  /// and [selectedMapType] directly: it carries [settingsRevision] with it, so
  /// the build is subscribed to the settings load. A screen that built before
  /// `settings/DriverNearBy` came back then redraws onto the right map the
  /// moment it arrives, instead of keeping the one it had to guess at until
  /// something unrelated forced a rebuild.
  static MapChoice get mapChoice => MapChoice._(settingsRevision.value, mapType, selectedMapType);

  /// Restores the last map configuration the admin set, from the device.
  ///
  /// Called from `main()` after the preferences are open and before
  /// `runApp`, so the first screen of the second and every later launch builds
  /// the same map the previous launch ended on. Nothing to restore on a first
  /// install; the defaults above cover that.
  static void restoreMapSettings() {
    final String cachedSelected = Preferences.getString(Preferences.selectedMapTypeKey);
    if (cachedSelected.isNotEmpty) selectedMapType = cachedSelected;
    final String cachedMapType = Preferences.getString(Preferences.mapTypeKey);
    if (cachedMapType.isNotEmpty) mapType = cachedMapType;
  }

  /// Remembers the configuration a settings read just applied, and tells the
  /// screens about it.
  static void rememberMapSettings() {
    Preferences.setString(Preferences.selectedMapTypeKey, selectedMapType);
    Preferences.setString(Preferences.mapTypeKey, mapType ?? 'inappmap');
    settingsRevision.value++;
  }

  static String orderRingtoneUrl = '';
  static bool isSelfDeliveryFeature = false;

  static String? adminType = "admin";

  static String amountShow({required String? amount}) {
    if (currencyModel!.symbolAtRight == true) {
      return "${double.parse(amount.toString()).toStringAsFixed(currencyModel!.decimalDigits ?? 0)} ${currencyModel!.symbol.toString()}";
    } else {
      return "${currencyModel!.symbol.toString()} ${amount == null || amount.isEmpty ? "0.0" : double.parse(amount.toString()).toStringAsFixed(currencyModel!.decimalDigits ?? 0)}";
    }
  }

  Future<Uint8List> getBytesFromUrl(String url, {int width = 100}) async {
    final http.Response response = await http.get(Uri.parse(url)).timeout(NetworkTimeout.mapRequest);
    if (response.statusCode != 200) {
      throw Exception("Failed to load image from $url");
    }

    final Uint8List bytes = response.bodyBytes;

    // Decode & resize
    final ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
    final ui.FrameInfo frameInfo = await codec.getNextFrame();

    final ByteData? byteData = await frameInfo.image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static Color statusText({required String? status}) {
    if (status == orderPlaced) {
      return AppThemeData.grey50;
    } else if (status == orderAccepted || status == orderCompleted) {
      return AppThemeData.grey50;
    } else if (status == orderRejected) {
      return AppThemeData.grey50;
    } else {
      return AppThemeData.grey900;
    }
  }

  static Color statusColor({required String? status}) {
    if (status == orderPlaced) {
      return AppThemeData.primary300;
    } else if (status == orderAccepted || status == orderCompleted) {
      return AppThemeData.success400;
    } else if (status == orderRejected) {
      return AppThemeData.danger300;
    } else {
      return AppThemeData.warning300;
    }
  }

  static double calculateTax({String? amount, TaxModel? taxModel}) {
    double taxAmount = 0.0;
    if (taxModel != null && taxModel.enable == true) {
      if (taxModel.type == "fix") {
        taxAmount = double.parse(taxModel.tax.toString());
      } else {
        taxAmount = (double.parse(amount.toString()) * double.parse(taxModel.tax!.toString())) / 100;
      }
    }
    return taxAmount;
  }

  static double calculateAdminCommission({required String amount, required String adminCommissionType, required String adminCommission}) {
    double taxAmount = 0.0;
    if (adminCommissionType == "Percentage" || adminCommissionType == "percentage") {
      taxAmount = (double.parse(amount.toString()) * double.parse(adminCommission.toString())) / 100;
    } else {
      taxAmount = double.parse(adminCommission.toString());
    }
    return taxAmount;
  }

  static String calculateReview({required String? reviewCount, required String? reviewSum}) {
    if (0 == double.parse(reviewSum.toString()) && 0 == double.parse(reviewSum.toString())) {
      return "0";
    }
    return (double.parse(reviewSum.toString()) / double.parse(reviewCount.toString())).toStringAsFixed(1);
  }

  static const userPlaceHolder = 'assets/images/user_placeholder.png';

  static String getUuid() {
    return const Uuid().v4();
  }

  static Widget loader() {
    return Center(
      child: CircularProgressIndicator(color: AppThemeData.primary300),
    );
  }

  static Widget showEmptyView({required String message, required bool isDark}) {
    return Center(
      child: Text(message, style: TextStyle(fontFamily: AppThemeData.medium, fontSize: 18, color: isDark ? AppThemeData.greyDark900 : AppThemeData.grey900)),
    );
  }

  static String getReferralCode() {
    var rng = math.Random();
    return (rng.nextInt(900000) + 100000).toString();
  }

  static String maskingString(String documentId, int maskingDigit) {
    String maskedDigits = documentId;
    for (int i = 0; i < documentId.length - maskingDigit; i++) {
      maskedDigits = maskedDigits.replaceFirst(documentId[i], "*");
    }
    return maskedDigits;
  }

  String? validateRequired(String? value, String type) {
    if (value!.isEmpty) {
      return '$type required';
    }
    return null;
  }

  String? validateEmail(String? value) {
    String pattern = r'^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$';
    RegExp regExp = RegExp(pattern);
    if (value == null || value.isEmpty) {
      return "Email is Required";
    } else if (!regExp.hasMatch(value)) {
      return "Invalid Email";
    } else {
      return null;
    }
  }

  static String getDistance({required String lat1, required String lng1, required String lat2, required String lng2}) {
    double distance;
    double distanceInMeters = Geolocator.distanceBetween(
      double.parse(lat1),
      double.parse(lng1),
      double.parse(lat2),
      double.parse(lng2),
    );
    if (distanceType == "miles") {
      distance = distanceInMeters / 1609;
    } else {
      distance = distanceInMeters / 1000;
    }
    return distance.toStringAsFixed(2);
  }

  bool hasValidUrl(String value) {
    String pattern = r'(http|https)://[\w-]+(\.[\w-]+)+([\w.,@?^=%&amp;:/~+#-]*[\w@?^=%&amp;/~+#-])?';
    RegExp regExp = RegExp(pattern);
    if (value.isEmpty) {
      return false;
    } else if (!regExp.hasMatch(value)) {
      return false;
    }
    return true;
  }

  static Future<String> uploadUserImageToFireStorage(File image, String filePath, String fileName) async {
    Reference upload = FirebaseStorage.instance.ref().child('$filePath/$fileName');
    UploadTask uploadTask = upload.putFile(image);
    var downloadUrl = await (await uploadTask.whenComplete(() {})).ref.getDownloadURL();
    return downloadUrl.toString();
  }

  static Future<void> makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    await launchUrl(launchUri);
  }

  Future<void> launchURL(Uri url) async {
    if (!await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Could not launch $url');
    }
  }

  Future<Uint8List> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    ui.FrameInfo fi = await codec.getNextFrame();
    final Uint8List bytes = (await fi.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    return bytes;
  }

  static Future<TimeOfDay?> selectTime(context) async {
    FocusScope.of(context).requestFocus(FocusNode()); //remove focus
    TimeOfDay? newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (newTime != null) {
      return newTime;
    }
    return null;
  }

  static Future<DateTime?> selectDate(context) async {
    DateTime? pickedDate = await showDatePicker(
        context: context,
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: AppThemeData.primary300, // header background color
                onPrimary: AppThemeData.grey900, // header text color
                onSurface: AppThemeData.grey900, // body text color
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: AppThemeData.grey900, // button text color
                ),
              ),
            ),
            child: child!,
          );
        },
        initialDate: DateTime.now(),
        //get today's date
        firstDate: DateTime(2000),
        //DateTime.now() - not to allow to choose before today.
        lastDate: DateTime(2101));
    return pickedDate;
  }

  static int calculateDifference(DateTime date) {
    DateTime now = DateTime.now();
    return DateTime(date.year, date.month, date.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  static String timestampToDate(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    return DateFormat('MMM dd,yyyy').format(dateTime);
  }

  static String timestampToDateTime(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    return DateFormat('MMM dd,yyyy hh:mm aa').format(dateTime);
  }

  static String timestampToTime(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    return DateFormat('hh:mm aa').format(dateTime);
  }

  static String timestampToDateChat(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    return DateFormat('dd/MM/yyyy').format(dateTime);
  }

  static DateTime stringToDate(String openDineTime) {
    return DateFormat('HH:mm').parse(DateFormat('HH:mm').format(DateFormat("hh:mm a").parse((Intl.getCurrentLocale() == "en_US") ? openDineTime : openDineTime.toLowerCase())));
  }

  static LanguageModel getLanguage() {
    final String user = Preferences.getString(Preferences.languageCodeKey);
    Map<String, dynamic> userMap = jsonDecode(user);
    return LanguageModel.fromJson(userMap);
  }

  static String orderId({String orderId = ''}) {
    return "#$orderId";
    // return "#${(orderId).substring(orderId.length - 10)}";
  }

  /// Returns the section name for a given sectionId using sectionNames map.
  static String sectionNameFromId(String? sectionId) {
    if (sectionId == null || sectionId.isEmpty) return '';
    return userModel?.sectionNames?[sectionId] ?? sectionId;
  }

  static Future<void> checkPermission({required BuildContext context, required Function() onTap}) async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      ShowToastDialog.showToast("You have to allow location permission to use your location");
    } else if (permission == LocationPermission.deniedForever) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return const PermissionDialog();
        },
      );
    } else {
      onTap();
    }
  }

  static bool isPointInPolygon(LatLng point, List<GeoPoint> polygon) {
    int crossings = 0;
    for (int i = 0; i < polygon.length; i++) {
      int next = (i + 1) % polygon.length;
      if (polygon[i].latitude <= point.latitude && polygon[next].latitude > point.latitude || polygon[i].latitude > point.latitude && polygon[next].latitude <= point.latitude) {
        double edgeLong = polygon[next].longitude - polygon[i].longitude;
        double edgeLat = polygon[next].latitude - polygon[i].latitude;
        double interpol = (point.latitude - polygon[i].latitude) / edgeLat;
        if (point.longitude < polygon[i].longitude + interpol * edgeLong) {
          crossings++;
        }
      }
    }
    return (crossings % 2 != 0);
  }

  static final smtpServer = SmtpServer(mailSettings!.host.toString(),
      username: mailSettings!.userName.toString(), password: mailSettings!.password.toString(), port: 465, ignoreBadCertificate: false, ssl: true, allowInsecure: true);

  static Future<void> sendMail({String? subject, String? body, bool? isAdmin = false, List<dynamic>? recipients}) async {
    // Create our message.
    if (isAdmin == true) {
      recipients!.add(mailSettings!.userName.toString());
    }
    final message = Message()
      ..from = Address(mailSettings!.userName.toString(), mailSettings!.fromName.toString())
      ..recipients = recipients!
      ..subject = subject
      ..text = body
      ..html = body;

    try {
      final sendReport = await send(message, smtpServer);
      print('Message sent: $sendReport');
    } on MailerException catch (e) {
      print(e);
      print('Message not sent.');
      for (var p in e.problems) {
        print('Problem: ${p.code}: ${p.msg}');
      }
    }

    // var connection = PersistentConnection(smtpServer);
    //
    // // Send the first message
    // await connection.send(message);
  }

  static Uri createCoordinatesUrl(double latitude, double longitude, [String? label]) {
    Uri uri;
    if (kIsWeb) {
      uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$latitude,$longitude'});
    } else if (Platform.isAndroid) {
      var query = '$latitude,$longitude';
      if (label != null) query += '($label)';
      uri = Uri(scheme: 'geo', host: '0,0', queryParameters: {'q': query});
    } else if (Platform.isIOS) {
      var params = {'ll': '$latitude,$longitude'};
      if (label != null) params['q'] = label;
      uri = Uri.https('maps.apple.com', '/', params);
    } else {
      uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$latitude,$longitude'});
    }

    return uri;
  }

  /// Calculate tax amount for a single tax model
  static double getTaxValue({required String amount, required TaxModel taxModel}) {
    double taxVal = 0.0;
    if (taxModel.enable == true) {
      if (taxModel.type == "fix") {
        taxVal = double.tryParse(taxModel.tax.toString()) ?? 0.0;
      } else {
        taxVal = (double.tryParse(amount) ?? 0.0) * (double.tryParse(taxModel.tax.toString()) ?? 0.0) / 100;
      }
    }
    return taxVal;
  }

  static String formatTimestamp(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();

    return DateFormat("d MMMM yyyy 'at' h:mm a").format(dateTime);
  }

  static String dateAndTimeFormatTimestamp(Timestamp? timestamp) {
    var format = DateFormat('dd MMM yyyy hh:mm aa'); // <- use skeleton here
    return format.format(timestamp!.toDate());
  }
}

extension StringExtension on String {
  String capitalizeString() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}

/// Which map to draw, read at a known settings revision.
///
/// See [Constant.mapChoice], which is the only thing that makes one.
class MapChoice {
  const MapChoice._(this.revision, this._mapType, this._selectedMapType);

  /// The settings revision this choice was read at.
  final int revision;

  final String? _mapType;
  final String _selectedMapType;

  /// The map is drawn inside the app, rather than handed off to whichever
  /// navigation app the admin picked.
  bool get isInApp => _mapType == 'inappmap';

  /// The in-app map is the built-in OpenStreetMap view - which needs no API
  /// key - rather than Google Maps.
  bool get isOsm => _selectedMapType == 'osm';
}
