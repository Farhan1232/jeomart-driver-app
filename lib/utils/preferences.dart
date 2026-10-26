import 'package:shared_preferences/shared_preferences.dart';

class Preferences {
  static const languageCodeKey = "languageCodeKey";
  static const isFinishOnBoardingKey = "isFinishOnBoardingKey";
  static const foodDeliveryType = "foodDeliveryType";
  static const themKey = "themKey";

  static const payFastSettings = "payFastSettings";
  static const mercadoPago = "MercadoPago";
  static const paypalSettings = "paypalSettings";
  static const stripeSettings = "stripeSettings";
  static const flutterWave = "flutterWave";
  static const payStack = "payStack";
  static const paytmSettings = "PaytmSettings";
  static const walletSettings = "walletSettings";
  static const razorpaySettings = "razorpaySettings";
  static const midTransSettings = "midTransSettings";
  static const orangeMoneySettings = "orangeMoneySettings";
  static const xenditSettings = "xenditSettings";
  static const codSettings = "CODSettings";
  static const orderRingtone = "audioSound";

  /// The map the apps draw, as the admin last set it in `settings/DriverNearBy`.
  ///
  /// Remembered on the device because those two values are read over the
  /// network at launch, and every screen that draws a map picks its map from
  /// them the first time it builds - before that read can possibly have landed
  /// on a slow connection.
  static const selectedMapTypeKey = "selectedMapTypeKey";
  static const mapTypeKey = "mapTypeKey";

  /// The terms and the privacy policy, as last fetched. They are the two
  /// biggest documents in `settings/` and are only read when their screen is
  /// opened, so the copy here is what that screen draws while a fresh one is
  /// on its way - and what it draws with no connection at all.
  static const termsAndConditionsKey = "termsAndConditionsKey";
  static const privacyPolicyKey = "privacyPolicyKey";
  static const isClickOnNotification = "isClickOnNotification";

  static late SharedPreferences pref;

  static Future<void> initPref() async {
    pref = await SharedPreferences.getInstance();
  }

  static bool getBoolean(String key) {
    return pref.getBool(key) ?? false;
  }

  static Future<void> setBoolean(String key, bool value) async {
    await pref.setBool(key, value);
  }

  static String getString(String key, {String? defaultValue}) {
    return pref.getString(key) ?? defaultValue ?? "";
  }

  static Future<void> setString(String key, String value) async {
    await pref.setString(key, value);
  }

  static int getInt(String key) {
    return pref.getInt(key) ?? 0;
  }

  static Future<void> setInt(String key, int value) async {
    await pref.setInt(key, value);
  }

  static Future<void> clearSharPreference() async {
    await pref.clear();
  }

  static Future<void> clearKeyData(String key) async {
    await pref.remove(key);
  }
}
