import 'dart:async';
import 'package:driver/utils/user_cache.dart';
import 'package:driver/utils/wallet_ledger.dart';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/app/chat_screens/chat_video_container.dart';
import 'package:driver/constant/collection_name.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/firebase_options.dart';
import 'package:driver/models/cab_order_model.dart';
import 'package:driver/models/car_makes.dart';
import 'package:driver/models/car_model.dart';
import 'package:driver/models/conversation_model.dart';
import 'package:driver/models/document_model.dart';
import 'package:driver/models/driver_document_model.dart';
import 'package:driver/models/email_template_model.dart';
import 'package:driver/models/inbox_model.dart';
import 'package:driver/models/mail_setting.dart';
import 'package:driver/models/notification_model.dart';
import 'package:driver/models/on_boarding_model.dart';
import 'package:driver/models/order_model.dart';
import 'package:driver/models/parcel_order_model.dart';
import 'package:driver/models/payment_model/cod_setting_model.dart';
import 'package:driver/models/payment_model/flutter_wave_model.dart';
import 'package:driver/models/payment_model/mercado_pago_model.dart';
import 'package:driver/models/payment_model/mid_trans.dart';
import 'package:driver/models/payment_model/orange_money.dart';
import 'package:driver/models/payment_model/pay_fast_model.dart';
import 'package:driver/models/payment_model/pay_stack_model.dart';
import 'package:driver/models/payment_model/paypal_model.dart';
import 'package:driver/models/payment_model/paytm_model.dart';
import 'package:driver/models/payment_model/razorpay_model.dart';
import 'package:driver/models/payment_model/stripe_model.dart';
import 'package:driver/models/payment_model/wallet_setting_model.dart';
import 'package:driver/models/payment_model/xendit.dart';
import 'package:driver/models/referral_model.dart';
import 'package:driver/models/rental_order_model.dart';
import 'package:driver/models/section_model.dart';
import 'package:driver/models/tax_model.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/models/vehicle_type.dart';
import 'package:driver/models/vendor_model.dart';
import 'package:driver/models/wallet_transaction_model.dart';
import 'package:driver/models/withdraw_method_model.dart';
import 'package:driver/models/withdrawal_model.dart';
import 'package:driver/models/zone_model.dart';
import 'package:driver/services/audio_player_service.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/utils/bidding_settings.dart';
import 'package:driver/utils/cab_request_slot.dart';
import 'package:driver/utils/driver_location_write.dart';
import 'package:driver/utils/driver_online_write.dart';
import 'package:driver/utils/finished_order.dart';
import 'package:driver/utils/driver_trip_settings.dart';
import 'package:driver/utils/parallel.dart';
import 'package:driver/utils/preferences.dart';
import 'package:driver/utils/deleted_driver_guard.dart';
import 'package:driver/app/auth_screen/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:geocoding/geocoding.dart';
import 'package:get/get.dart' show Get, GetNavigation, Trans;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:video_compress/video_compress.dart';
import '../models/parcel_category.dart';
import '../models/rating_model.dart';

enum FirebaseEnv { defaultDb, staging }

/// Change this to switch between default / staging
const FirebaseEnv currentEnv = FirebaseEnv.defaultDb;

class FireStoreUtils {
  FireStoreUtils._privateConstructor();

  static final FireStoreUtils instance = FireStoreUtils._privateConstructor();

  static late FirebaseFirestore fireStore;

  /// Initialize Firestore with a FirebaseApp and optional databaseId
  void init(FirebaseApp app, {String? databaseId}) {
    fireStore = FirebaseFirestore.instanceFor(app: app, databaseId: databaseId);
  }

  static String getCurrentUid() {
    return FirebaseAuth.instance.currentUser!.uid;
  }

  static Future<bool> isLogin() async {
    bool isLogin = false;
    if (FirebaseAuth.instance.currentUser != null) {
      isLogin = await userExistOrNot(FirebaseAuth.instance.currentUser!.uid);
    } else {
      isLogin = false;
    }
    return isLogin;
  }

  /// The same question as [isLogin], with "I could not ask" kept apart from "no".
  ///
  /// A driver stays signed in until they press Logout. [isLogin] answers a plain
  /// bool, so a `users` read that failed - no signal in a basement, a dropped
  /// connection, a Firestore hiccup on launch - was indistinguishable from a
  /// profile that is really gone, and the splash signed the driver out for it.
  /// That is the "session out by itself" the client reported.
  ///
  /// Returns true when the document is there, false when the read succeeded and
  /// there is no document, and **null when the read itself failed** - on which
  /// the splash keeps the session, exactly as [isMaintenanceMode] carries on
  /// rather than locking the app when its own read fails.
  ///
  /// [userExistOrNot] keeps its bool: the login and OTP screens use it to decide
  /// whether a *fresh* sign-in may proceed, and a failed read must still stop
  /// that.
  static Future<bool?> isLoginOrUnknown() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await fireStore.collection(CollectionName.users).doc(user.uid).get();
      if (doc.exists) {
        final Map<String, dynamic>? data = doc.data();
        if (data != null) {
          try {
            UserCache.put(user.uid, UserModel.fromJson(data));
          } catch (_) {
            // Unparseable here is not this call's problem - it only answers
            // whether the document is there, exactly as userExistOrNot does.
          }
        }
        return true;
      }
      return false;
    } catch (error) {
      log("isLoginOrUnknown() could not be read, keeping the session :: $error");
      return null;
    }
  }

  /// [getUserProfile], with "I could not ask" kept apart from "there is none".
  ///
  /// Same reason as [isLoginOrUnknown]: `getUserProfile` returns null for both a
  /// missing document and a failed read, and the splash signed the driver out on
  /// null. Returns the profile, or null when the document is genuinely absent,
  /// and throws when the read failed so the caller can tell the difference.
  static Future<UserModel?> getUserProfileOrThrow(String uuid) async {
    final UserModel? cached = UserCache.get(uuid);
    if (cached != null) return cached;
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await fireStore.collection(CollectionName.users).doc(uuid).get();
    if (!doc.exists) return null;
    final UserModel loaded = UserModel.fromJson(doc.data()!);
    UserCache.put(uuid, loaded);
    return loaded;
  }

  /// Whether a `users` document exists.
  ///
  /// The document it reads is the same one `getUserProfile()` reads moments
  /// later on the startup path - `isLogin()` here, then the profile in the
  /// splash - so the parsed model is put in [UserCache] on the way past and
  /// that second read is served from memory. One fewer network round trip
  /// between launching the app and seeing a screen.
  static Future<bool> userExistOrNot(String uid) async {
    bool isExist = false;

    await fireStore.collection(CollectionName.users).doc(uid).get().then(
      (value) {
        if (value.exists) {
          isExist = true;
          final data = value.data();
          if (data != null) {
            try {
              UserCache.put(uid, UserModel.fromJson(data));
            } catch (_) {
              // A profile this call cannot parse is not this call's problem;
              // it only has to answer whether the document exists.
            }
          }
        } else {
          isExist = false;
        }
      },
    ).catchError((error) {
      log("Failed to check user exist: $error");
      isExist = false;
    });
    return isExist;
  }

  /// Whether the driver app is switched off from the admin panel.
  ///
  /// Fails open. This is the very first read the splash screen makes, and an
  /// unhandled throw here - no connection, a rules change, anything - used to
  /// reject `redirectScreen()` and leave the app sitting on the splash art for
  /// ever with no error and no way forward.
  static Future<bool> isMaintenanceMode() async {
    bool isMaintenance = false;
    try {
      final value = await fireStore.collection(CollectionName.settings).doc('maintenance_settings').get();
      isMaintenance = value.data()?['isMaintenanceModeForDriver'] == true;
      log("isMaintenance :: $isMaintenance");
    } catch (e) {
      log("isMaintenanceMode() could not be read, continuing :: $e");
    }
    return isMaintenance;
  }

  /// Reads a `users` document.
  ///
  /// Backed by [UserCache] so the same profile is not re-read on every
  /// rebuild or list row. Pass `forceRefresh: true` where the freshest copy
  /// matters (wallet balance, online status).
  static Future<UserModel?> getUserProfile(String uuid, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = UserCache.get(uuid);
      if (cached != null) return cached;
    }
    UserModel? userModel;
    await fireStore
        .collection(CollectionName.users)
        .doc(uuid)
        .get()
        .then((value) {
          if (value.exists) {
            userModel = UserModel.fromJson(value.data()!);
          }
        })
        .catchError((error) {
          log("Failed to update user: $error");
          userModel = null;
        });
    final loaded = userModel;
    if (loaded != null) UserCache.put(uuid, loaded);
    return loaded;
  }

  /// The wallet writer. Kept as a field so a test can swap the runner.
  static WalletLedger walletLedger = WalletLedger(FirestoreWalletTransactionRunner(fireStore, collection: CollectionName.users));

  /// Adds [amount] to `users/{userId}.wallet_amount`, negative to debit.
  ///
  /// Runs inside a Firestore transaction and writes only `wallet_amount`.
  /// This used to read the whole profile, add the delta in Dart and write the
  /// whole profile back, so two overlapping updates read the same balance and
  /// the later write discarded the earlier one.
  static Future<bool?> updateUserWallet({required String amount, required String userId}) async {
    final double? delta = WalletLedger.parseAmount(amount);
    if (delta == null) return false;
    try {
      final bool applied = await walletLedger.applyDelta(userId: userId, delta: delta);
      if (applied) {
        // The document just changed - drop any cached copy, and keep the
        // in-memory profile of the signed-in user in step with it.
        UserCache.invalidate(userId);
        final UserModel? current = Constant.userModel;
        if (current != null && current.id == userId) {
          current.walletAmount = (current.walletAmount ?? 0) + delta;
        }
      }
      return applied;
    } catch (error, stack) {
      log("Failed to update wallet: $error");
      log(stack.toString());
      return false;
    }
  }

  static Map<String, dynamic> removeNulls(Map<String, dynamic> map) {
    map.removeWhere((key, value) => value == null);

    // A nested map left empty is dropped as well - decided inside removeWhere,
    // which may remove while it walks the map. This used to call map.remove()
    // inside map.forEach(), which throws a ConcurrentModificationError, so
    // every save of a profile holding an empty map failed. The Admin Panel
    // writes `vehicleDetails: {}` for every delivery driver it creates or
    // edits: their login never saved the push token, and the dispatcher skips
    // a driver without one - they received no orders at all.
    map.removeWhere((key, value) {
      if (value is Map<String, dynamic>) {
        removeNulls(value);
        return value.isEmpty;
      }
      return false;
    });

    return map;
  }

  /// Whether the Admin Panel's deletion record for [uid] exists, live.
  static Stream<bool> _deletionRecordExists(String uid) => fireStore
      .collection(DeletedDriverGuard.collection)
      .doc(uid)
      .snapshots()
      .map((DocumentSnapshot<Map<String, dynamic>> doc) => doc.exists);

  /// The admin deleted the driver signed in on this phone: sign out, back to login.
  static void _endDeletedDriverSession(String uid) {
    UserCache.invalidate(uid);
    ShowToastDialog.showToast("This account has been deleted. Please contact the administrator.".tr);
    unawaited(FirebaseAuth.instance.signOut().catchError((Object _) {}).whenComplete(() => Get.offAll(const LoginScreen())));
  }

  /// Saves where the signed-in driver is, and nothing else.
  ///
  /// The dashboards' GPS listeners used to do this with [updateUser], which
  /// saves the whole profile from a copy - see [DriverLocationWrite] for what
  /// that copy overwrote. The "is this driver available?" rule is unchanged;
  /// it is simply asked of the dashboard's live profile ([live]) once that has
  /// loaded. Returns the profile the decision was made on, null when there was
  /// none, which is what the dashboards acted on before.
  static Future<UserModel?> updateDriverLocation({
    required UserModel live,
    required bool onlyWhenActive,
    double? latitude,
    double? longitude,
    num? heading,
  }) async {
    final String uid = getCurrentUid();
    if (uid.isEmpty) return null;
    final UserModel? profile = await DriverLocationWrite.profileFor(live, () => getUserProfile(uid));
    if (profile == null) return null;
    if (onlyWhenActive && profile.isActive != true) return profile;

    // The same deleted-driver rule as updateUser (Session 38).
    DeletedDriverGuard.follow(uid, recordExists: _deletionRecordExists, onDeleted: _endDeletedDriverSession);
    if (DeletedDriverGuard.isDeleted(uid)) return profile;

    UserCache.invalidate(uid);
    try {
      await fireStore.collection(CollectionName.users).doc(uid).update(DriverLocationWrite.fields(latitude: latitude, longitude: longitude, heading: heading));
    } catch (error) {
      log("Failed to update driver location: $error");
    }
    return profile;
  }

  /// Turns the signed-in driver's Available Status on or off.
  ///
  /// One field on the driver's own document, exactly what the Admin Panel's
  /// Online switch writes - so what the driver chooses in the app is what the
  /// panel shows, and nothing else in the app can put it back. Returns whether
  /// the change reached the server, so the switch can say so when it did not.
  static Future<bool> setDriverOnlineStatus(bool isOnline) async {
    final String uid = getCurrentUid();
    if (uid.isEmpty) return false;

    // The same deleted-driver rule as every other write here (Session 38).
    DeletedDriverGuard.follow(uid, recordExists: _deletionRecordExists, onDeleted: _endDeletedDriverSession);
    if (DeletedDriverGuard.isDeleted(uid)) return false;

    UserCache.invalidate(uid);
    try {
      await fireStore.collection(CollectionName.users).doc(uid).update(DriverOnlineWrite.fields(isOnline: isOnline));
      // The app's own copy, so a profile save that follows carries the status
      // the driver just chose rather than the one it was read with.
      Constant.userModel?.isActive = isOnline;
      return true;
    } catch (error, stack) {
      log("Failed to update online status: $error");
      log(stack.toString());
      return false;
    }
  }

  /// Takes a finished order off the signed-in driver's own order lists.
  ///
  /// The dispatcher treats a driver whose `inProgressOrderID` or
  /// `orderRequestData` holds anything as busy, and with "one order at a time"
  /// on it offers them nothing more. A delivered or cancelled order left in
  /// those lists therefore stopped a driver receiving orders for good. This
  /// removes that one id and nothing else - no copy of the profile is written.
  static Future<bool> releaseDriverOrder(String orderId) async {
    final String uid = getCurrentUid();
    if (uid.isEmpty || orderId.isEmpty) return false;

    // The same deleted-driver rule as every other write here (Session 38).
    DeletedDriverGuard.follow(uid, recordExists: _deletionRecordExists, onDeleted: _endDeletedDriverSession);
    if (DeletedDriverGuard.isDeleted(uid)) return false;

    UserCache.invalidate(uid);
    try {
      await fireStore.collection(CollectionName.users).doc(uid).update(FinishedOrder.releaseFields(orderId));
      Constant.userModel?.inProgressOrderID?.remove(orderId);
      Constant.userModel?.orderRequestData?.remove(orderId);
      return true;
    } catch (error, stack) {
      log("Failed to release finished order $orderId: $error");
      log(stack.toString());
      return false;
    }
  }

  static Future<bool> updateUser(UserModel userModel, {bool includeOnlineStatus = false}) async {
    // A driver the Admin Panel deleted is not written back: on a deleted
    // document the set(merge) below would create it again (Session 38).
    final String? signedInUid = FirebaseAuth.instance.currentUser?.uid;
    if (signedInUid != null && userModel.id == signedInUid) {
      DeletedDriverGuard.follow(signedInUid, recordExists: _deletionRecordExists, onDeleted: _endDeletedDriverSession);
    }
    if (DeletedDriverGuard.isDeleted(userModel.id)) return false;

    // The document is about to change - drop any cached copy.
    UserCache.invalidate(userModel.id);
    try {
      final docRef = fireStore.collection(CollectionName.users).doc(userModel.id);

      final Map<String, dynamic> data = removeNulls(userModel.toJson());
      // The ride request belongs to the dispatcher. A copy of the profile never
      // puts one back - it can only be cleared, below. See CabRequestSlot.
      data.remove('ordercabRequestData');
      // The Available Status belongs to the switch, and only to the switch.
      // A profile save carries whatever copy it was given - at launch, when the
      // push token is saved, after an order - and that copy can be older than
      // the driver's last tap, which is how a driver who had just gone online
      // was put back offline seconds later. Only the two account-creation paths
      // pass `includeOnlineStatus: true`, to write the starting value.
      // See DriverOnlineWrite / setDriverOnlineStatus.
      if (!includeOnlineStatus) {
        data.remove(DriverOnlineWrite.field);
      }

      await docRef.set(data, SetOptions(merge: true));

      // Legacy / deprecated top-level fields, via a separate update() call.
      // Sentinels (FieldValue.delete) can only appear at the top level of an
      // update, and must not appear inside nested maps written via set().
      final Map<String, dynamic> legacyFields = {
        'serviceDetails': FieldValue.delete(),
      };

      // The legacy singular fields are **mirrored**, never deleted.
      //
      // `serviceType` and `sectionId` are not dead fields: the Admin Panel's
      // own driver list queries them directly - `drivers/index.blade.php` runs
      // `where('sectionIds','array-contains',id)` *and*
      // `where('sectionId','==',id)` and merges the two, and the deliveryman
      // list filters on `serviceType` - so a driver whose singular fields have
      // been deleted drops out of the panel views that use them. Deleting the
      // panel's own record of its own selection is the one thing least
      // compatible with "the driver type must stay exactly as selected in the
      // Admin Panel".
      //
      // Mirroring keeps both shapes present and in agreement, whichever one a
      // given reader understands. The singular field can only hold one value,
      // so a driver in several services mirrors the first - which is what the
      // panel's own deliveryman pages do when they write `'sectionId': s` and
      // `'sectionIds': [s]` together, and is strictly better than the nothing
      // such a driver has there today.
      final List<String>? savedServiceTypes = data['serviceTypes'] as List<String>?;
      if (savedServiceTypes != null && savedServiceTypes.isNotEmpty) {
        legacyFields['serviceType'] = savedServiceTypes.first;
      }
      final List<String>? savedSectionIds = data['sectionIds'] as List<String>?;
      if (savedSectionIds != null && savedSectionIds.isNotEmpty) {
        legacyFields['sectionId'] = savedSectionIds.first;
      }
      if (userModel.role == Constant.userRoleDriver) {
        legacyFields.addAll({
          'vehicleType': FieldValue.delete(),
          'vehicleId': FieldValue.delete(),
          'carName': FieldValue.delete(),
          'carNumber': FieldValue.delete(),
          'carMakes': FieldValue.delete(),
          'rideType': FieldValue.delete(),
        });
      }
      // Cleared only when this copy was read holding a request that the caller
      // has since let go of. Clearing whenever a copy had none deleted offers
      // that had arrived after the copy was read.
      if (CabRequestSlot.shouldClear(current: userModel.orderCabRequestData, loadedWithRequest: userModel.loadedWithCabRequest)) {
        legacyFields['ordercabRequestData'] = FieldValue.delete();
      }
      await docRef.update(legacyFields);

      if (userModel.id == getCurrentUid()) {
        // The status was not written above, so the copy must not carry an older
        // one into the app's own model either.
        if (!includeOnlineStatus) {
          userModel.isActive = Constant.userModel?.isActive ?? userModel.isActive;
        }
        Constant.userModel = userModel;
      }

      return true;
    } catch (error, stack) {
      log("Failed to update user: $error");
      log(stack.toString());
      return false;
    }
  }

  static Future<List<OnBoardingModel>> getOnBoardingList() async {
    List<OnBoardingModel> onBoardingModel = [];
    await fireStore.collection(CollectionName.onBoarding).where("type", isEqualTo: "driver").get().then((value) {
      for (var element in value.docs) {
        OnBoardingModel documentModel = OnBoardingModel.fromJson(element.data());
        onBoardingModel.add(documentModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return onBoardingModel;
  }

  static Future<List<SectionModel>> getSections(String serviceType) async {
    List<SectionModel> sections = [];
    QuerySnapshot<Map<String, dynamic>> productsQuery = await fireStore.collection(CollectionName.sections).where("serviceTypeFlag", isEqualTo: serviceType).where("isActive", isEqualTo: true).get();

    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        sections.add(SectionModel.fromJson(document.data()));
      } catch (e) {
        print('**-FireStoreUtils.getSection Parse error $e');
      }
    });
    return sections;
  }

  /// Returns active sections for driver registration (delivery, cab, parcel, rental only).
  /// Excludes onDemand, ecommerce, and any other non-driver section types.
  static Future<List<SectionModel>> getAllActiveSections() async {
    const driverFlags = ['delivery-service', 'cab-service', 'parcel_delivery', 'rental-service'];
    List<SectionModel> sections = [];
    await fireStore.collection(CollectionName.sections).where("isActive", isEqualTo: true).get().then((query) {
      for (var doc in query.docs) {
        try {
          final section = SectionModel.fromJson(doc.data());
          if (driverFlags.contains(section.serviceTypeFlag)) {
            sections.add(section);
          }
        } catch (e) {
          print('**-FireStoreUtils.getAllActiveSections Parse error $e');
        }
      }
    });
    return sections;
  }

  static Future<bool?> setWalletTransaction(WalletTransactionModel walletTransactionModel) async {
    bool isAdded = false;
    await fireStore.collection(CollectionName.wallet).doc(walletTransactionModel.id).set(walletTransactionModel.toJson()).then((value) {
      isAdded = true;
    }).catchError((error) {
      log("Failed to update user: $error");
      isAdded = false;
    });
    return isAdded;
  }

  /// Reads one settings document twice - from the copy already on the device,
  /// then from the server - and applies whichever arrives.
  ///
  /// `settings/*` is read on every single launch and changes about never, so
  /// waiting for the network before the app could draw anything meant paying
  /// full price for the same bytes every time the driver opened the app.
  /// `settings/globalSettings` alone is 130 KB of it, almost all one base64
  /// mp3 ringtone stored inline. A launch that has a copy applies it without
  /// touching the network and refreshes behind the first screen; only a first
  /// launch, with nothing cached, waits.
  ///
  /// [apply] therefore runs up to twice, cache first, and must be safe to run
  /// again with newer data.
  static Future<void> _readSettings(String documentId, void Function(Map<String, dynamic> data) apply) async {
    bool servedFromCache = false;
    try {
      final DocumentSnapshot<Map<String, dynamic>> cached =
          await fireStore.collection(CollectionName.settings).doc(documentId).get(const GetOptions(source: Source.cache));
      final Map<String, dynamic>? data = cached.data();
      if (data != null) {
        apply(data);
        servedFromCache = true;
      }
    } catch (e) {
      // Nothing on the device yet. Normal on a first launch, and on a fresh
      // install after the app data has been cleared.
      log("getSettings() has no cached settings/$documentId :: $e");
    }

    // Started either way, so a stale cached copy is corrected within the same
    // launch. Carries its own error handling: when it is not awaited, a future
    // that throws is an unhandled error.
    final Future<void> fromServer = fireStore
        .collection(CollectionName.settings)
        .doc(documentId)
        .get(const GetOptions(source: Source.server))
        .then((DocumentSnapshot<Map<String, dynamic>> snapshot) {
          final Map<String, dynamic>? data = snapshot.data();
          if (data != null) apply(data);
        })
        .catchError((Object e) {
          log("getSettings() could not read settings/$documentId :: $e");
        });

    if (!servedFromCache) await fromServer;
  }

  /// The terms of service or the privacy policy, read when its screen opens.
  ///
  /// Kept on the device, so a second visit draws immediately from that copy
  /// while a fresh one is fetched behind it, and so the screen still has
  /// something to show with no connection.
  static Future<String> legalDocument({required String documentId, required String field, required String cacheKey}) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await fireStore.collection(CollectionName.settings).doc(documentId).get();
      final String text = snapshot.data()?[field]?.toString() ?? '';
      if (text.isNotEmpty) {
        await Preferences.setString(cacheKey, text);
      }
      return text;
    } catch (e) {
      log("legalDocument() could not read settings/$documentId :: $e");
      return Preferences.getString(cacheKey);
    }
  }

  static Future<void> getSettings() async {
    try {
      // The three settings documents this method blocks on are independent of
      // each other, so all three are started here rather than one round trip
      // after the other - and each is served from the device first, so a
      // launch after the first does not wait on the network at all. Together
      // that is most of the "app is loading slow" report at startup.
      bool audioReady = false;

      final Future<void> globalSettings = _readSettings("globalSettings", (Map<String, dynamic> data) {
        Constant.orderRingtoneUrl = data['order_ringtone_url']?.toString() ?? '';
        Constant.isSelfDeliveryFeature = data['isSelfDelivery'] as bool? ?? false;
        Constant.defaultCountryCode = data['defaultCountryCode']?.toString() ?? '';

        Preferences.setString(Preferences.orderRingtone, Constant.orderRingtoneUrl);
        // Kept on the device ahead of the first ride request, so the request
        // rings the moment it arrives instead of after the file has streamed.
        unawaited(AudioPlayerService.prepareRingtone(Constant.orderRingtoneUrl));
        // Guarded: an unwritten or malformed colour used to throw here and take
        // the country code, the ringtone and everything after it down with it.
        final int? driverColour = int.tryParse((data['app_driver_color']?.toString() ?? '').replaceFirst("#", "0xff"));
        if (driverColour != null) {
          AppThemeData.primary300 = Color(driverColour);
        }
        if (Constant.orderRingtoneUrl.isNotEmpty && !audioReady) {
          // Not awaited, and once per launch however many times this document
          // is applied. Nothing needs the player before the first screen.
          audioReady = true;
          unawaited(AudioPlayerService.initAudio());
        }
      });

      final Future<void> documentVerification = _readSettings("document_verification_settings", (Map<String, dynamic> data) {
        Constant.isDriverVerification = data['isDriverVerification'] as bool? ?? Constant.isDriverVerification;
        Constant.isOwnerVerification = data['isOwnerVerification'] as bool? ?? Constant.isOwnerVerification;
      });

      fireStore.collection(CollectionName.settings).doc("googleMapKey").snapshots().listen((event) {
        if (event.exists) {
          Constant.mapAPIKey = event.data()!["key"];
        }
      });

      fireStore.collection(CollectionName.settings).doc("notification_setting").snapshots().listen((event) {
        if (event.exists) {
          Constant.senderId = event.data()?["senderId"];
          Constant.jsonNotificationFileURL = event.data()?["serviceJson"];
        }
      });

      fireStore.collection(CollectionName.settings).doc("RestaurantNearBy").snapshots().listen((event) {
        if (event.exists) {
          Constant.distanceType = event.data()!["distanceType"];
        }
      });

      // Bidding / counter-offer configuration. Live, so the admin's global
      // switch reaches drivers without an app restart; absent means off.
      fireStore.collection(CollectionName.settings).doc(BiddingSettings.documentId).snapshots().listen((event) {
        Constant.biddingSettings = event.exists ? BiddingSettings.fromJson(event.data()) : BiddingSettings.disabled;
      }, onError: (Object error) {
        log("biddingSettings listener error: $error");
        Constant.biddingSettings = BiddingSettings.disabled;
      });

      // Driver-created trips: how long a published trip stays visible to
      // customers. Live, so an admin change reaches drivers without an app
      // restart; absent means the 24-hour default.
      fireStore.collection(CollectionName.settings).doc(DriverTripSettings.documentId).snapshots().listen((event) {
        Constant.driverTripSettings = event.exists ? DriverTripSettings.fromJson(event.data()) : DriverTripSettings.defaults;
      }, onError: (Object error) {
        log("driverTripsSettings listener error: $error");
        Constant.driverTripSettings = DriverTripSettings.defaults;
      });

      // The terms and the privacy policy are not read here any more. They are
      // the two largest documents in `settings/` - 51 KB and 69 KB - and this
      // pulled both of them down, on a live listener, during startup, on every
      // launch, for two screens most drivers never open. `legalDocument()`
      // fetches one when its screen is opened instead.

      fireStore.collection(CollectionName.settings).doc("Version").snapshots().listen((event) {
        if (event.exists) {
          Constant.googlePlayLink = event.data()!["googlePlayLink"] ?? '';
          Constant.appStoreLink = event.data()!["appStoreLink"] ?? '';
          Constant.appVersion = event.data()!["app_version"] ?? '';
        }
      });

      // fireStore.collection(CollectionName.settings).doc('referral_amount').get().then((value) {
      //   Constant.referralAmount = value.data()!['referralAmount'];
      // });

      fireStore.collection(CollectionName.settings).doc("emailSetting").get().then((value) {
        if (value.exists) {
          Constant.mailSettings = MailSettings.fromJson(value.data()!);
        }
      });

      fireStore.collection(CollectionName.settings).doc('placeHolderImage').get().then((value) {
        Constant.placeHolderImage = value.data()!['image'];
      });

      final Future<void> driverNearBy = _readSettings("DriverNearBy", (Map<String, dynamic> value) {
        // Every field falls back to what is already loaded. These were plain
        // assignments of `data()![key]` into non-nullable statics, so one field
        // the admin panel has never written threw a type error here and took
        // the rest of the document down with it - including the two map
        // settings below, which is a driver looking at a blank home screen
        // because of an unrelated missing key.
        Constant.minimumDepositToRideAccept = value['minimumDepositToRideAccept']?.toString() ?? Constant.minimumDepositToRideAccept;
        Constant.ownerMinimumDepositToRideAccept = value['ownerMinimumDepositToRideAccept']?.toString() ?? Constant.ownerMinimumDepositToRideAccept;
        Constant.minimumAmountToWithdrawal = value['minimumAmountToWithdrawal']?.toString() ?? Constant.minimumAmountToWithdrawal;
        Constant.driverLocationUpdate = value['driverLocationUpdate']?.toString() ?? Constant.driverLocationUpdate;
        Constant.singleOrderReceive = value['singleOrderReceive'] as bool? ?? Constant.singleOrderReceive;
        Constant.selectedMapType = value["selectedMapType"]?.toString() ?? Constant.selectedMapType;
        Constant.mapType = value["mapType"]?.toString() ?? Constant.mapType;
        Constant.autoApproveDriver = value["auto_approve_driver"] as bool? ?? Constant.autoApproveDriver;
        Constant.enableOTPTripStart = value["enableOTPTripStart"] as bool? ?? Constant.enableOTPTripStart;
        Constant.enableOTPTripStartForRental = value["enableOTPTripStartForRental"] as bool? ?? Constant.enableOTPTripStartForRental;
        Constant.parcelRadius = value["parcelRadius"]?.toString() ?? Constant.parcelRadius;
        Constant.rentalRadius = value["rentalRadius"]?.toString() ?? Constant.rentalRadius;
        // Keeps the map the admin chose on the device, and tells the screens
        // that already drew one that the real configuration has arrived.
        Constant.rememberMapSettings();
        log("Constant.singleOrderReceive :: ${Constant.singleOrderReceive}");
      });

      await Future.wait(<Future<void>>[globalSettings, documentVerification, driverNearBy]);
    } catch (e) {
      log(e.toString());
    }
  }

  static Future<List<ZoneModel>?> getZone() async {
    List<ZoneModel> airPortList = [];
    await fireStore.collection(CollectionName.zone).where('publish', isEqualTo: true).get().then((value) {
      for (var element in value.docs) {
        ZoneModel ariPortModel = ZoneModel.fromJson(element.data());
        airPortList.add(ariPortModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return airPortList;
  }

  static Future<List<CarMakes>> getCarMakes() async {
    List<CarMakes> airPortList = [];
    await fireStore.collection(CollectionName.carMake).where('isActive', isEqualTo: true).get().then((value) {
      for (var element in value.docs) {
        CarMakes ariPortModel = CarMakes.fromJson(element.data());
        airPortList.add(ariPortModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return airPortList;
  }

  static Future<List<ParcelOrderModel>> getOnGoingParcelList() async {
    List<ParcelOrderModel> parcelOrderList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await fireStore
        .collection(CollectionName.parcelOrders)
        .where("driverId", isEqualTo: FireStoreUtils.getCurrentUid())
        .where("status", whereIn: [Constant.driverAccepted, Constant.orderInTransit, Constant.orderShipped]).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        parcelOrderList.add(ParcelOrderModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.get Currency Parse error $e');
      }
    });
    return parcelOrderList;
  }

  static Future<List<RentalOrderModel>> getRentalOnGoingParcelList() async {
    List<RentalOrderModel> parcelOrderList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await fireStore
        .collection(CollectionName.rentalOrders)
        .where("driverId", isEqualTo: FireStoreUtils.getCurrentUid())
        .where("status", whereIn: [Constant.driverAccepted, Constant.orderInTransit, Constant.orderShipped]).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        parcelOrderList.add(RentalOrderModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.get Currency Parse error $e');
      }
    });
    return parcelOrderList;
  }

  static Future<List<UserModel>> getOwnerDriver() async {
    List<UserModel> userList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery =
        await fireStore.collection(CollectionName.users).where("ownerId", isEqualTo: FireStoreUtils.getCurrentUid()).where("isOwner", isEqualTo: false).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        userList.add(UserModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.get Currency Parse error $e');
      }
    });
    return userList;
  }

  static Future<List<CarModel>> getCarModel(String name) async {
    List<CarModel> airPortList = [];
    await fireStore.collection(CollectionName.carModel).where("car_make_name", isEqualTo: name).where('isActive', isEqualTo: true).get().then((value) {
      for (var element in value.docs) {
        CarModel ariPortModel = CarModel.fromJson(element.data());
        airPortList.add(ariPortModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return airPortList;
  }

  static Future<List<VehicleType>> getCabVehicleType(String sectionId) async {
    List<VehicleType> airPortList = [];
    await fireStore.collection(CollectionName.vehicleType).where('sectionId', isEqualTo: sectionId).where("isActive", isEqualTo: true).get().then((value) {
      for (var element in value.docs) {
        VehicleType ariPortModel = VehicleType.fromJson(element.data());
        airPortList.add(ariPortModel);
      }
    });
    return airPortList;
  }

  static Future<List<VehicleType>> getRentalVehicleType(String sectionId) async {
    print("sectionId :: $sectionId");
    List<VehicleType> airPortList = [];
    await fireStore.collection(CollectionName.rentalVehicleType).where('sectionId', isEqualTo: sectionId).where('isActive', isEqualTo: true).get().then((value) {
      for (var element in value.docs) {
        VehicleType ariPortModel = VehicleType.fromJson(element.data());
        airPortList.add(ariPortModel);
      }
    });
    return airPortList;
  }

  static Future<List<WalletTransactionModel>?> getWalletTransaction() async {
    List<WalletTransactionModel> walletTransactionList = [];
    await fireStore.collection(CollectionName.wallet).where('user_id', isEqualTo: FireStoreUtils.getCurrentUid()).orderBy('date', descending: true).get().then((value) {
      for (var element in value.docs) {
        WalletTransactionModel walletTransactionModel = WalletTransactionModel.fromJson(element.data());
        walletTransactionList.add(walletTransactionModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return walletTransactionList;
  }

  static Future getPaymentSettingsData() async {
    // All thirteen documents are requested together, then applied one at a
    // time in the order they always were. They are independent reads, but
    // awaiting each before asking for the next made the wallet - and every
    // screen that loads payment settings - pay thirteen round trips end to end.
    // A read that fails still stops the Preferences after it from being written,
    // as before: `ignore()` only keeps the reads started alongside it from
    // reporting their own failure as an unhandled error, and the await below
    // still throws.
    final Future<DocumentSnapshot<Map<String, dynamic>>> payFastSettingsRead = fireStore.collection(CollectionName.settings).doc("payFastSettings").get()..ignore();
    final Future<DocumentSnapshot<Map<String, dynamic>>> mercadoPagoRead = fireStore.collection(CollectionName.settings).doc("MercadoPago").get()..ignore();
    final Future<DocumentSnapshot<Map<String, dynamic>>> paypalSettingsRead = fireStore.collection(CollectionName.settings).doc("paypalSettings").get()..ignore();
    final Future<DocumentSnapshot<Map<String, dynamic>>> stripeSettingsRead = fireStore.collection(CollectionName.settings).doc("stripeSettings").get()..ignore();
    final Future<DocumentSnapshot<Map<String, dynamic>>> flutterWaveRead = fireStore.collection(CollectionName.settings).doc("flutterWave").get()..ignore();
    final Future<DocumentSnapshot<Map<String, dynamic>>> payStackRead = fireStore.collection(CollectionName.settings).doc("payStack").get()..ignore();
    final Future<DocumentSnapshot<Map<String, dynamic>>> paytmSettingsRead = fireStore.collection(CollectionName.settings).doc("PaytmSettings").get()..ignore();
    final Future<DocumentSnapshot<Map<String, dynamic>>> walletSettingsRead = fireStore.collection(CollectionName.settings).doc("walletSettings").get()..ignore();
    final Future<DocumentSnapshot<Map<String, dynamic>>> razorpaySettingsRead = fireStore.collection(CollectionName.settings).doc("razorpaySettings").get()..ignore();
    final Future<DocumentSnapshot<Map<String, dynamic>>> codSettingsRead = fireStore.collection(CollectionName.settings).doc("CODSettings").get()..ignore();
    final Future<DocumentSnapshot<Map<String, dynamic>>> midtransSettingsRead = fireStore.collection(CollectionName.settings).doc("midtrans_settings").get()..ignore();
    final Future<DocumentSnapshot<Map<String, dynamic>>> orangeMoneySettingsRead = fireStore.collection(CollectionName.settings).doc("orange_money_settings").get()..ignore();
    final Future<DocumentSnapshot<Map<String, dynamic>>> xenditSettingsRead = fireStore.collection(CollectionName.settings).doc("xendit_settings").get()..ignore();

    await payFastSettingsRead.then((value) async {
      if (value.exists) {
        PayFastModel payFastModel = PayFastModel.fromJson(value.data()!);
        await Preferences.setString(Preferences.payFastSettings, jsonEncode(payFastModel.toJson()));
      }
    });
    await mercadoPagoRead.then((value) async {
      if (value.exists) {
        MercadoPagoModel mercadoPagoModel = MercadoPagoModel.fromJson(value.data()!);
        await Preferences.setString(Preferences.mercadoPago, jsonEncode(mercadoPagoModel.toJson()));
      }
    });
    await paypalSettingsRead.then((value) async {
      if (value.exists) {
        PayPalModel payPalModel = PayPalModel.fromJson(value.data()!);
        await Preferences.setString(Preferences.paypalSettings, jsonEncode(payPalModel.toJson()));
      }
    });
    await stripeSettingsRead.then((value) async {
      if (value.exists) {
        StripeModel stripeModel = StripeModel.fromJson(value.data()!);
        await Preferences.setString(Preferences.stripeSettings, jsonEncode(stripeModel.toJson()));
      }
    });
    await flutterWaveRead.then((value) async {
      if (value.exists) {
        FlutterWaveModel flutterWaveModel = FlutterWaveModel.fromJson(value.data()!);
        await Preferences.setString(Preferences.flutterWave, jsonEncode(flutterWaveModel.toJson()));
      }
    });
    await payStackRead.then((value) async {
      if (value.exists) {
        PayStackModel payStackModel = PayStackModel.fromJson(value.data()!);
        await Preferences.setString(Preferences.payStack, jsonEncode(payStackModel.toJson()));
      }
    });
    await paytmSettingsRead.then((value) async {
      if (value.exists) {
        PaytmModel paytmModel = PaytmModel.fromJson(value.data()!);
        await Preferences.setString(Preferences.paytmSettings, jsonEncode(paytmModel.toJson()));
      }
    });
    await walletSettingsRead.then((value) async {
      if (value.exists) {
        WalletSettingModel walletSettingModel = WalletSettingModel.fromJson(value.data()!);
        await Preferences.setString(Preferences.walletSettings, jsonEncode(walletSettingModel.toJson()));
      }
    });
    await razorpaySettingsRead.then((value) async {
      if (value.exists) {
        RazorPayModel razorPayModel = RazorPayModel.fromJson(value.data()!);
        await Preferences.setString(Preferences.razorpaySettings, jsonEncode(razorPayModel.toJson()));
      }
    });
    await codSettingsRead.then((value) async {
      if (value.exists) {
        CodSettingModel codSettingModel = CodSettingModel.fromJson(value.data()!);
        await Preferences.setString(Preferences.codSettings, jsonEncode(codSettingModel.toJson()));
      }
    });

    await midtransSettingsRead.then((value) async {
      if (value.exists) {
        MidTrans midTrans = MidTrans.fromJson(value.data()!);
        await Preferences.setString(Preferences.midTransSettings, jsonEncode(midTrans.toJson()));
      }
    });

    await orangeMoneySettingsRead.then((value) async {
      if (value.exists) {
        OrangeMoney orangeMoney = OrangeMoney.fromJson(value.data()!);
        await Preferences.setString(Preferences.orangeMoneySettings, jsonEncode(orangeMoney.toJson()));
      }
    });

    await xenditSettingsRead.then((value) async {
      if (value.exists) {
        Xendit xendit = Xendit.fromJson(value.data()!);
        await Preferences.setString(Preferences.xenditSettings, jsonEncode(xendit.toJson()));
      }
    });
  }

  static Future<VendorModel?> getVendorById(String vendorId) async {
    VendorModel? vendorModel;
    try {
      await fireStore.collection(CollectionName.vendors).doc(vendorId).get().then((value) {
        if (value.exists) {
          vendorModel = VendorModel.fromJson(value.data()!);
        }
      });
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return vendorModel;
  }

  static Future<OrderModel?> getOrderById(String orderId) async {
    OrderModel? orderModel;
    try {
      await fireStore.collection(CollectionName.vendorOrders).doc(orderId).get().then((value) {
        if (value.exists) {
          orderModel = OrderModel.fromJson(value.data()!);
        }
      });
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return orderModel;
  }

  /// Sections are admin-configured service verticals that effectively never
  /// change during a session, but this was being read from Firestore inside the
  /// order listeners - once per order update.
  static final Map<String, SectionModel> _sectionCache = <String, SectionModel>{};

  static Future<SectionModel?> getSectionBySectionId(String sectionId) async {
    final cached = _sectionCache[sectionId];
    if (cached != null) return cached;

    SectionModel? orderModel;
    try {
      await fireStore.collection(CollectionName.sections).doc(sectionId).get().then((value) {
        if (value.exists) {
          orderModel = SectionModel.fromJson(value.data()!);
        }
      });
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    final loaded = orderModel;
    if (loaded != null) _sectionCache[sectionId] = loaded;
    return loaded;
  }

  static Future<DeliveryCharge?> getDeliveryCharge() async {
    DeliveryCharge? deliveryCharge;
    try {
      await fireStore.collection(CollectionName.settings).doc("DeliveryCharge").get().then((value) {
        if (value.exists) {
          deliveryCharge = DeliveryCharge.fromJson(value.data()!);
        }
      });
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return deliveryCharge;
  }

  static Future<List<TaxModel>?> getTaxList() async {
    List<TaxModel> taxList = [];
    List<Placemark> placeMarks = await placemarkFromCoordinates(Constant.selectedLocation.location!.latitude!, Constant.selectedLocation.location!.longitude!);
    await fireStore.collection(CollectionName.tax).where('country', isEqualTo: placeMarks.first.country).where('enable', isEqualTo: true).get().then((value) {
      for (var element in value.docs) {
        TaxModel taxModel = TaxModel.fromJson(element.data());
        taxList.add(taxModel);
      }
    }).catchError((error) {
      log(error.toString());
    });

    return taxList;
  }

  static Future<bool?> setOrder(OrderModel orderModel) async {
    bool isAdded = false;
    await fireStore.collection(CollectionName.vendorOrders).doc(orderModel.id).set(orderModel.toJson(), SetOptions(merge: true)).then((value) {
      isAdded = true;
    }).catchError((error) {
      log("Failed to update user: $error");
      isAdded = false;
    });
    return isAdded;
  }

  /// Moves a delivery order to [status], writing that one field only.
  static Future<bool> setOrderStatus(String? orderId, String status) async {
    if (orderId == null || orderId.isEmpty) return false;
    try {
      await fireStore.collection(CollectionName.vendorOrders).doc(orderId).update(<String, dynamic>{'status': status});
      return true;
    } catch (error) {
      log("Failed to update order $orderId status: $error");
      return false;
    }
  }

  static Future<bool?> setParcelOrder(ParcelOrderModel orderModel) async {
    bool isAdded = false;
    await fireStore.collection(CollectionName.parcelOrders).doc(orderModel.id).set(orderModel.toJson()).then((value) {
      isAdded = true;
    }).catchError((error) {
      log("Failed to update user: $error");
      isAdded = false;
    });
    return isAdded;
  }

  static Future<bool> setCabOrder(CabOrderModel orderModel) async {
    log("setCabOrder :: ${orderModel.toJson()}");
    try {
      await fireStore.collection(CollectionName.ridesBooking).doc(orderModel.id).set(orderModel.toJson(), SetOptions(merge: true));
      return true;
    } catch (error) {
      log("Failed to update cab order: $error");
      return false;
    }
  }

  static Future<EmailTemplateModel?> getEmailTemplates(String type) async {
    EmailTemplateModel? emailTemplateModel;
    await fireStore.collection(CollectionName.emailTemplates).where('type', isEqualTo: type).get().then((value) {
      print("------>");
      if (value.docs.isNotEmpty) {
        print(value.docs.first.data());
        emailTemplateModel = EmailTemplateModel.fromJson(value.docs.first.data());
      }
    });
    return emailTemplateModel;
  }

  static Future<void> updateWallateAmount(OrderModel orderModel) async {
    double subTotal = 0.0;
    double specialDiscountAmount = 0.0;
    double couponAmount = 0.0;
    double productTaxAmount = 0.0;
    double orderTaxAmount = 0.0;
    double driverDeliveryTaxAmount = 0.0;
    double packagingTaxAmount = 0.0;
    double platformTaxAmount = 0.0;
    double platformFee = 0.0;
    double deliveryCharges = 0.0;
    double deliveryTips = 0.0;
    double packagingCharge = 0.0;

    /// ---------------- SUBTOTAL ----------------
    for (var element in orderModel.products!) {
      // `tryParse`: these fields have no default on the model, so a missing one
      // arrived as the text "null" and `double.parse` threw - Make Order
      // Delivered then did nothing. Numbers that are there parse the same.
      final double discountPrice = double.tryParse(element.discountPrice.toString()) ?? 0.0;
      final double price = (discountPrice > 0) ? discountPrice : (double.tryParse(element.price.toString()) ?? 0.0);

      final double qty = double.tryParse(element.quantity.toString()) ?? 0.0;
      final double extras = double.tryParse(element.extrasPrice.toString()) ?? 0.0;

      subTotal += (price * qty) + (extras * qty);
    }

    /// ---------------- DISCOUNTS ----------------
    couponAmount = double.tryParse(orderModel.discount.toString()) ?? 0.0;

    if (orderModel.specialDiscount != null && orderModel.specialDiscount!['special_discount'] != null) {
      specialDiscountAmount = double.tryParse(orderModel.specialDiscount!['special_discount'].toString()) ?? 0.0;
    }

    final double totalDiscount = couponAmount + specialDiscountAmount;

    /// ---------------- DISCOUNT RATIO ----------------
    double discountRatio = 0.0;
    if (subTotal > 0 && totalDiscount > 0) {
      discountRatio = totalDiscount / subTotal;
    }

    /// ---------------- PRODUCT TAX (AFTER DISCOUNT) ----------------
    if (orderModel.taxScope == "product") {
      for (var element in orderModel.products!) {
        final double discountPrice = double.tryParse(element.discountPrice.toString()) ?? 0.0;
        final double price = (discountPrice > 0) ? discountPrice : (double.tryParse(element.price.toString()) ?? 0.0);

        final double qty = double.tryParse(element.quantity.toString()) ?? 0.0;
        final double extras = double.tryParse(element.extrasPrice.toString()) ?? 0.0;

        final double itemAmount = (price * qty) + (extras * qty);

        final double discountedItemAmount = itemAmount - (itemAmount * discountRatio);

        for (var taxElement in element.taxSetting!) {
          if (taxElement.type == "fix") {
            productTaxAmount += Constant.calculateTax(
                  amount: discountedItemAmount.toString(),
                  taxModel: taxElement,
                ) *
                qty;
          } else {
            productTaxAmount += Constant.calculateTax(
              amount: discountedItemAmount.toString(),
              taxModel: taxElement,
            );
          }
        }
      }
    }

    /// ---------------- ORDER LEVEL TAX ----------------
    if (orderModel.taxScope == "order") {
      for (var taxElement in orderModel.taxSetting ?? []) {
        orderTaxAmount += Constant.calculateTax(
          amount: (subTotal - totalDiscount).toString(),
          taxModel: taxElement,
        );
      }
    }

    /// ---------------- OTHER CHARGES ----------------
    deliveryCharges = double.parse(orderModel.deliveryCharge.toString());

    deliveryTips = double.parse(orderModel.tipAmount.toString());

    packagingCharge = orderModel.packagingChargeEnable == true ? double.parse(orderModel.vendor!.packagingCharge.toString()) : 0.0;

    platformFee = double.parse(orderModel.platformFee ?? '0.0');

    /// ---------------- DELIVERY TAX ----------------
    if (orderModel.takeAway != true && orderModel.vendor?.isSelfDelivery != true) {
      for (var taxElement in orderModel.driverDeliveryTax ?? []) {
        driverDeliveryTaxAmount += Constant.calculateTax(
          amount: deliveryCharges.toString(),
          taxModel: taxElement,
        );
      }
    }

    /// ---------------- PACKAGING TAX ----------------
    if (packagingCharge > 0) {
      for (var taxElement in orderModel.packagingTax ?? []) {
        packagingTaxAmount += Constant.calculateTax(
          amount: packagingCharge.toString(),
          taxModel: taxElement,
        );
      }
    }

    /// ---------------- PLATFORM TAX ----------------
    if (platformFee > 0) {
      for (var taxElement in orderModel.platformTax ?? []) {
        platformTaxAmount += Constant.calculateTax(
          amount: platformFee.toString(),
          taxModel: taxElement,
        );
      }
    }

    double driverAmount = 0.0;
    final isCOD = orderModel.paymentMethod?.toLowerCase() == "cod";

    if (isCOD) {
      // Driver gives money back
      driverAmount = -((subTotal - totalDiscount) + productTaxAmount + orderTaxAmount + packagingTaxAmount + platformTaxAmount + packagingCharge + platformFee);

      WalletTransactionModel codTxn = WalletTransactionModel(
        id: Constant.getUuid(),
        amount: driverAmount,
        date: Timestamp.now(),
        paymentMethod: orderModel.paymentMethod!,
        transactionUser: "driver",
        userId: FireStoreUtils.getCurrentUid(),
        isTopup: false,
        note: "Product amount debited from order #${orderModel.id}",
        orderId: orderModel.id,
        paymentStatus: "success",
      );

      await FireStoreUtils.setWalletTransaction(codTxn);
    } else {
      driverAmount = deliveryCharges + deliveryTips + driverDeliveryTaxAmount;

      WalletTransactionModel onlineTxn = WalletTransactionModel(
        id: Constant.getUuid(),
        amount: driverAmount,
        date: Timestamp.now(),
        paymentMethod: orderModel.paymentMethod ?? "online",
        transactionUser: "driver",
        userId: FireStoreUtils.getCurrentUid(),
        isTopup: true,
        note: "Delivery charge credited for order #${orderModel.id}",
        orderId: orderModel.id,
        paymentStatus: "success",
      );

      await FireStoreUtils.setWalletTransaction(onlineTxn);
    }
    await FireStoreUtils.updateUserWallet(
      userId: orderModel.driverID!,
      amount: driverAmount.toString(),
    );
  }

  static Future<void> sendTopUpMail({required String amount, required String paymentMethod, required String tractionId}) async {
    EmailTemplateModel? emailTemplateModel = await FireStoreUtils.getEmailTemplates(Constant.walletTopup);

    String newString = emailTemplateModel!.message.toString();
    newString = newString.replaceAll("{username}", Constant.userModel!.firstName.toString() + Constant.userModel!.lastName.toString());
    newString = newString.replaceAll("{date}", DateFormat('yyyy-MM-dd').format(Timestamp.now().toDate()));
    newString = newString.replaceAll("{amount}", Constant.amountShow(amount: amount));
    newString = newString.replaceAll("{paymentmethod}", paymentMethod.toString());
    newString = newString.replaceAll("{transactionid}", tractionId.toString());
    newString = newString.replaceAll("{newwalletbalance}.", Constant.amountShow(amount: Constant.userModel!.walletAmount.toString()));
    await Constant.sendMail(subject: emailTemplateModel.subject, isAdmin: emailTemplateModel.isSendToAdmin, body: newString, recipients: [Constant.userModel!.email]);
  }

  static Future<List> getVendorCuisines(String id) async {
    List tagList = [];
    List prodTagList = [];
    QuerySnapshot<Map<String, dynamic>> productsQuery = await fireStore.collection(CollectionName.vendorProducts).where('vendorID', isEqualTo: id).get();
    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      if (document.data().containsKey("categoryID") && document.data()['categoryID'].toString().isNotEmpty) {
        prodTagList.add(document.data()['categoryID']);
      }
    });
    QuerySnapshot<Map<String, dynamic>> catQuery = await fireStore.collection(CollectionName.vendorCategories).where('publish', isEqualTo: true).get();
    await Future.forEach(catQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      Map<String, dynamic> catDoc = document.data();
      if (catDoc.containsKey("id") && catDoc['id'].toString().isNotEmpty && catDoc.containsKey("title") && catDoc['title'].toString().isNotEmpty && prodTagList.contains(catDoc['id'])) {
        tagList.add(catDoc['title']);
      }
    });
    return tagList;
  }

  static Future<NotificationModel?> getNotificationContent(String type) async {
    NotificationModel? notificationModel;
    await fireStore.collection(CollectionName.dynamicNotification).where('type', isEqualTo: type).get().then((value) {
      print("------>");
      if (value.docs.isNotEmpty) {
        print(value.docs.first.data());

        notificationModel = NotificationModel.fromJson(value.docs.first.data());
      } else {
        notificationModel = NotificationModel(id: "", message: "Notification setup is pending", subject: "setup notification", type: "");
      }
    });
    return notificationModel;
  }

  static Future<bool?> deleteUser() async {
    bool? isDelete;
    try {
      await fireStore.collection(CollectionName.users).doc(FireStoreUtils.getCurrentUid()).delete();

      // delete user  from firebase auth
      await FirebaseAuth.instance.currentUser?.delete().then((value) {
        isDelete = true;
      });
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return false;
    }
    return isDelete;
  }

  static Future<List<DocumentModel>> getDocumentList(String type) async {
    List<DocumentModel> documentList = [];
    await fireStore.collection(CollectionName.documents).where('type', isEqualTo: type).where('enable', isEqualTo: true).get().then((value) {
      for (var element in value.docs) {
        DocumentModel documentModel = DocumentModel.fromJson(element.data());
        documentList.add(documentModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return documentList;
  }

  static Future<DriverDocumentModel?> getDocumentOfDriver() async {
    DriverDocumentModel? driverDocumentModel;
    await fireStore.collection(CollectionName.documentsVerify).doc(getCurrentUid()).get().then((value) async {
      if (value.exists) {
        driverDocumentModel = DriverDocumentModel.fromJson(value.data()!);
      }
    });
    return driverDocumentModel;
  }

  static Future addDriverInbox(InboxModel inboxModel) async {
    return await fireStore.collection("chat_driver").doc(inboxModel.orderId).set(inboxModel.toJson()).then((document) {
      return inboxModel;
    });
  }

  static Future addDriverChat(ConversationModel conversationModel) async {
    return await fireStore.collection("chat_driver").doc(conversationModel.orderId).collection("thread").doc(conversationModel.id).set(conversationModel.toJson()).then((document) {
      return conversationModel;
    });
  }

  static Future addRestaurantChat(ConversationModel conversationModel) async {
    return await fireStore.collection("chat_restaurant").doc(conversationModel.orderId).collection("thread").doc(conversationModel.id).set(conversationModel.toJson()).then((document) {
      return conversationModel;
    });
  }

  static Future<Url> uploadChatImageToFireStorage(File image, BuildContext context) async {
    ShowToastDialog.showLoader("Please wait");
    var uniqueID = const Uuid().v4();
    Reference upload = FirebaseStorage.instance.ref().child('images/$uniqueID.png');
    UploadTask uploadTask = upload.putFile(image);
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    var metaData = await storageRef.getMetadata();
    ShowToastDialog.closeLoader();
    return Url(mime: metaData.contentType ?? 'image', url: downloadUrl.toString());
  }

  // static Future<ChatVideoContainer> uploadChatVideoToFireStorage(File video, BuildContext context) async {
  //   ShowToastDialog.showLoader("Please wait");
  //   var uniqueID = const Uuid().v4();
  //   Reference upload = FirebaseStorage.instance.ref().child('videos/$uniqueID.mp4');
  //   SettableMetadata metadata = SettableMetadata(contentType: 'video');
  //   UploadTask uploadTask = upload.putFile(video, metadata);
  //   var storageRef = (await uploadTask.whenComplete(() {})).ref;
  //   var downloadUrl = await storageRef.getDownloadURL();
  //   var metaData = await storageRef.getMetadata();
  //   final uint8list = await VideoThumbnail.thumbnailFile(video: downloadUrl, thumbnailPath: (await getTemporaryDirectory()).path, imageFormat: ImageFormat.PNG);
  //   final file = File(uint8list ?? '');
  //   String thumbnailDownloadUrl = await uploadVideoThumbnailToFireStorage(file);
  //   ShowToastDialog.closeLoader();
  //   return ChatVideoContainer(videoUrl: Url(url: downloadUrl.toString(), mime: metaData.contentType ?? 'video'), thumbnailUrl: thumbnailDownloadUrl);
  // }

  static Future<ChatVideoContainer?> uploadChatVideoToFireStorage(BuildContext context, File video) async {
    try {
      ShowToastDialog.showLoader("Uploading video...");
      final String uniqueID = const Uuid().v4();
      final Reference videoRef = FirebaseStorage.instance.ref('videos/$uniqueID.mp4');
      final UploadTask uploadTask = videoRef.putFile(
        video,
        SettableMetadata(contentType: 'video/mp4'),
      );
      await uploadTask;
      final String videoUrl = await videoRef.getDownloadURL();
      ShowToastDialog.showLoader("Generating thumbnail...");
      File thumbnail = await VideoCompress.getFileThumbnail(
        video.path,
        quality: 75, // 0 - 100
        position: -1, // Get the first frame
      );

      final String thumbnailID = const Uuid().v4();
      final Reference thumbnailRef = FirebaseStorage.instance.ref('thumbnails/$thumbnailID.jpg');
      final UploadTask thumbnailUploadTask = thumbnailRef.putData(
        thumbnail.readAsBytesSync(),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      await thumbnailUploadTask;
      final String thumbnailUrl = await thumbnailRef.getDownloadURL();
      var metaData = await thumbnailRef.getMetadata();
      ShowToastDialog.closeLoader();

      return ChatVideoContainer(videoUrl: Url(url: videoUrl.toString(), mime: metaData.contentType ?? 'video'), thumbnailUrl: thumbnailUrl);
    } catch (e) {
      ShowToastDialog.closeLoader();
      ShowToastDialog.showToast("Error: ${e.toString()}");
      return null;
    }
  }

  static Future<String> uploadVideoThumbnailToFireStorage(File file) async {
    var uniqueID = const Uuid().v4();
    Reference upload = FirebaseStorage.instance.ref().child('thumbnails/$uniqueID.png');
    UploadTask uploadTask = upload.putFile(file);
    var downloadUrl = await (await uploadTask.whenComplete(() {})).ref.getDownloadURL();
    return downloadUrl.toString();
  }

  static Future<bool> uploadDriverDocument(Documents documents) async {
    bool isAdded = false;
    DriverDocumentModel driverDocumentModel = DriverDocumentModel();
    List<Documents> documentsList = [];
    await fireStore.collection(CollectionName.documentsVerify).doc(getCurrentUid()).get().then((value) async {
      if (value.exists) {
        DriverDocumentModel newDriverDocumentModel = DriverDocumentModel.fromJson(value.data()!);
        documentsList = newDriverDocumentModel.documents!;
        var contain = newDriverDocumentModel.documents!.where((element) => element.documentId == documents.documentId);
        if (contain.isEmpty) {
          documentsList.add(documents);

          driverDocumentModel.id = getCurrentUid();
          driverDocumentModel.type = "driver";
          driverDocumentModel.documents = documentsList;
        } else {
          var index = newDriverDocumentModel.documents!.indexWhere((element) => element.documentId == documents.documentId);

          driverDocumentModel.id = getCurrentUid();
          driverDocumentModel.type = "driver";
          documentsList.removeAt(index);
          documentsList.insert(index, documents);
          driverDocumentModel.documents = documentsList;
          isAdded = false;
        }
      } else {
        documentsList.add(documents);
        driverDocumentModel.id = getCurrentUid();
        driverDocumentModel.type = "driver";
        driverDocumentModel.documents = documentsList;
      }
    });

    await fireStore.collection(CollectionName.documentsVerify).doc(getCurrentUid()).set(driverDocumentModel.toJson()).then((value) {
      isAdded = true;
    }).catchError((error) {
      isAdded = false;
      log(error.toString());
    });

    return isAdded;
  }

  static Future<WithdrawMethodModel?> getWithdrawMethod() async {
    WithdrawMethodModel? withdrawMethodModel;
    await fireStore.collection(CollectionName.withdrawMethod).where("userId", isEqualTo: getCurrentUid()).get().then((value) async {
      if (value.docs.isNotEmpty) {
        withdrawMethodModel = WithdrawMethodModel.fromJson(value.docs.first.data());
      }
    });
    return withdrawMethodModel;
  }

  static Future<WithdrawMethodModel?> setWithdrawMethod(WithdrawMethodModel withdrawMethodModel) async {
    if (withdrawMethodModel.id == null) {
      withdrawMethodModel.id = const Uuid().v4();
      withdrawMethodModel.userId = getCurrentUid();
    }
    await fireStore.collection(CollectionName.withdrawMethod).doc(withdrawMethodModel.id).set(withdrawMethodModel.toJson()).then((value) async {});
    return withdrawMethodModel;
  }

  static Future<List<WithdrawalModel>?> getWithdrawHistory() async {
    List<WithdrawalModel> walletTransactionList = [];
    await fireStore.collection(CollectionName.driverPayouts).where('driverID', isEqualTo: Constant.userModel!.id.toString()).orderBy('paidDate', descending: true).get().then((value) {
      for (var element in value.docs) {
        WithdrawalModel walletTransactionModel = WithdrawalModel.fromJson(element.data());
        walletTransactionList.add(walletTransactionModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return walletTransactionList;
  }

  static Future<void> sendPayoutMail({required String amount, required String payoutrequestid}) async {
    EmailTemplateModel? emailTemplateModel = await FireStoreUtils.getEmailTemplates(Constant.payoutRequest);

    String body = emailTemplateModel!.subject.toString();
    body = body.replaceAll("{userid}", Constant.userModel!.id.toString());

    String newString = emailTemplateModel.message.toString();
    newString = newString.replaceAll("{username}", Constant.userModel!.fullName());
    newString = newString.replaceAll("{userid}", Constant.userModel!.id.toString());
    newString = newString.replaceAll("{amount}", Constant.amountShow(amount: amount));
    newString = newString.replaceAll("{payoutrequestid}", payoutrequestid.toString());
    newString = newString.replaceAll("{usercontactinfo}", "${Constant.userModel!.email}\n${Constant.userModel!.phoneNumber}");
    await Constant.sendMail(subject: body, isAdmin: emailTemplateModel.isSendToAdmin, body: newString, recipients: [Constant.userModel!.email]);
  }

  static Future<bool> withdrawWalletAmount(WithdrawalModel userModel) async {
    bool isUpdate = false;
    await fireStore.collection(CollectionName.driverPayouts).doc(userModel.id).set(userModel.toJson()).whenComplete(() {
      isUpdate = true;
    }).catchError((error) {
      log("Failed to update user: $error");
      isUpdate = false;
    });
    return isUpdate;
  }

  static Future<bool> getFirestOrderOrNOt(OrderModel orderModel) async {
    bool isFirst = true;
    // `.limit(2)` answers the identical question.
    //
    // This asks "is this the customer's first order?" and decides it by
    // `size == 1`. Unbounded, it downloaded **every order that customer has
    // ever placed** to do so — on the driver's tap to complete a job, in front
    // of a blocking loader. Two documents are enough to tell one from more than
    // one, and the comparison below is unchanged.
    await fireStore.collection(CollectionName.vendorOrders).where('authorID', isEqualTo: orderModel.authorID).limit(2).get().then((value) {
      if (value.size == 1) {
        isFirst = true;
      } else {
        isFirst = false;
      }
    });
    return isFirst;
  }

  static Future updateReferralAmount(OrderModel orderModel) async {
    ReferralModel? referralModel;
    await fireStore.collection(CollectionName.referral).doc(orderModel.authorID).get().then((value) {
      if (value.data() != null) {
        referralModel = ReferralModel.fromJson(value.data()!);
      } else {
        return;
      }
    });
    if (referralModel != null) {
      if (referralModel!.referralBy != null && referralModel!.referralBy!.isNotEmpty) {
        WalletTransactionModel transactionModel = WalletTransactionModel(
            id: Constant.getUuid(),
            amount: double.parse(Constant.referralAmount.toString()),
            date: Timestamp.now(),
            paymentMethod: "Referral Amount",
            transactionUser: "user",
            userId: referralModel!.referralBy,
            isTopup: true,
            note: "You referral user has complete his this order #${orderModel.id}",
            paymentStatus: "success");

        await FireStoreUtils.setWalletTransaction(transactionModel).then((value) async {
          if (value == true) {
            await FireStoreUtils.updateUserWallet(amount: Constant.referralAmount.toString(), userId: referralModel!.referralBy.toString()).then((value) {});
          }
        });
      } else {
        return;
      }
    }
  }

  static Future<bool> getFirestOrderOrNOtCabService(CabOrderModel orderModel) async {
    bool isFirst = true;
    // `.limit(2)` answers the identical question.
    //
    // This asks "is this the customer's first order?" and decides it by
    // `size == 1`. Unbounded, it downloaded **every order that customer has
    // ever placed** to do so — on the driver's tap to complete a job, in front
    // of a blocking loader. Two documents are enough to tell one from more than
    // one, and the comparison below is unchanged.
    await fireStore.collection(CollectionName.ridesBooking).where('authorID', isEqualTo: orderModel.authorID).limit(2).get().then((value) {
      if (value.size == 1) {
        isFirst = true;
      } else {
        isFirst = false;
      }
    });
    return isFirst;
  }

  static Future updateReferralAmountCabService(CabOrderModel orderModel) async {
    ReferralModel? referralModel;
    SectionModel? sectionModel;
    await getSectionBySectionId(orderModel.sectionId.toString()).then((value) {
      sectionModel = value;
    });
    await fireStore.collection(CollectionName.referral).doc(orderModel.authorID).get().then((value) {
      if (value.data() != null) {
        referralModel = ReferralModel.fromJson(value.data()!);
      } else {
        return;
      }
    });

    if (referralModel != null) {
      if (referralModel!.referralBy != null && referralModel!.referralBy!.isNotEmpty) {
        await fireStore.collection(CollectionName.users).doc(referralModel!.referralBy).get().then((value) async {
          DocumentSnapshot<Map<String, dynamic>> userDocument = value;
          if (userDocument.data() != null && userDocument.exists) {
            try {
              UserModel user = UserModel.fromJson(userDocument.data()!);
              await fireStore
                  .collection(CollectionName.users)
                  .doc(user.id)
                  .update({"wallet_amount": double.parse(user.walletAmount.toString()) + double.parse(sectionModel!.referralAmount.toString())});

              WalletTransactionModel transactionModel = WalletTransactionModel(
                  id: Constant.getUuid(),
                  amount: double.parse(sectionModel!.referralAmount.toString()),
                  date: Timestamp.now(),
                  paymentMethod: "Referral Amount",
                  transactionUser: "user",
                  userId: referralModel!.referralBy.toString(),
                  isTopup: true,
                  note: "Wallet Top-up",
                  paymentStatus: "success");

              await FireStoreUtils.setWalletTransaction(transactionModel).then((value) async {
                if (value == true) {
                  await FireStoreUtils.updateUserWallet(amount: sectionModel!.referralAmount.toString(), userId: referralModel!.referralBy.toString()).then((value) {});
                }
              });
            } catch (e) {
              log(e.toString());
            }
          }
        });
      } else {
        return;
      }
    }
  }

  static Future<bool> getParcelFirstOrderOrNOt(ParcelOrderModel orderModel) async {
    bool isFirst = true;
    // `.limit(2)` answers the identical question.
    //
    // This asks "is this the customer's first order?" and decides it by
    // `size == 1`. Unbounded, it downloaded **every order that customer has
    // ever placed** to do so — on the driver's tap to complete a job, in front
    // of a blocking loader. Two documents are enough to tell one from more than
    // one, and the comparison below is unchanged.
    await fireStore.collection(CollectionName.parcelOrders).where('authorID', isEqualTo: orderModel.authorID).limit(2).get().then((value) {
      if (value.size == 1) {
        isFirst = true;
      } else {
        isFirst = false;
      }
    });
    return isFirst;
  }

  static Future<bool> getRentalFirstOrderOrNOt(RentalOrderModel orderModel) async {
    bool isFirst = true;
    // `.limit(2)` answers the identical question.
    //
    // This asks "is this the customer's first order?" and decides it by
    // `size == 1`. Unbounded, it downloaded **every order that customer has
    // ever placed** to do so — on the driver's tap to complete a job, in front
    // of a blocking loader. Two documents are enough to tell one from more than
    // one, and the comparison below is unchanged.
    await fireStore.collection(CollectionName.rentalOrders).where('authorID', isEqualTo: orderModel.authorID).limit(2).get().then((value) {
      if (value.size == 1) {
        isFirst = true;
      } else {
        isFirst = false;
      }
    });
    return isFirst;
  }

  static Future updateParcelReferralAmount(ParcelOrderModel orderModel) async {
    ReferralModel? referralModel;
    SectionModel? sectionModel;
    print(orderModel.authorID);
    await getSectionBySectionId(orderModel.sectionId.toString()).then((value) {
      sectionModel = value;
    });
    await fireStore.collection(CollectionName.referral).doc(orderModel.authorID).get().then((value) {
      if (value.data() != null) {
        referralModel = ReferralModel.fromJson(value.data()!);
      } else {
        return;
      }
    });

    if (referralModel != null) {
      if (referralModel!.referralBy != null && referralModel!.referralBy!.isNotEmpty) {
        await fireStore.collection(CollectionName.users).doc(referralModel!.referralBy).get().then((value) async {
          DocumentSnapshot<Map<String, dynamic>> userDocument = value;
          if (userDocument.data() != null && userDocument.exists) {
            try {
              UserModel user = UserModel.fromJson(userDocument.data()!);
              await fireStore
                  .collection(CollectionName.users)
                  .doc(user.id)
                  .update({"wallet_amount": double.parse(user.walletAmount.toString()) + double.parse(sectionModel!.referralAmount.toString())});

              WalletTransactionModel transactionModel = WalletTransactionModel(
                  id: Constant.getUuid(),
                  amount: double.parse(sectionModel!.referralAmount.toString()),
                  date: Timestamp.now(),
                  paymentMethod: "Referral Amount",
                  transactionUser: "user",
                  userId: referralModel!.referralBy.toString(),
                  isTopup: true,
                  note: "Wallet Top-up",
                  paymentStatus: "success");

              await FireStoreUtils.setWalletTransaction(transactionModel).then((value) async {
                if (value == true) {
                  await FireStoreUtils.updateUserWallet(amount: sectionModel!.referralAmount.toString(), userId: referralModel!.referralBy.toString()).then((value) {});
                }
              });
            } catch (error) {
              log(error.toString());
            }
            print("data val");
          }
        });
      } else {
        return;
      }
    }
  }

  static Future updateRentalReferralAmount(RentalOrderModel orderModel) async {
    ReferralModel? referralModel;
    SectionModel? sectionModel;
    print(orderModel.authorID);
    await getSectionBySectionId(orderModel.sectionId.toString()).then((value) {
      sectionModel = value;
    });
    await fireStore.collection(CollectionName.referral).doc(orderModel.authorID).get().then((value) {
      if (value.data() != null) {
        referralModel = ReferralModel.fromJson(value.data()!);
      } else {
        return;
      }
    });

    if (referralModel != null) {
      if (referralModel!.referralBy != null && referralModel!.referralBy!.isNotEmpty) {
        await fireStore.collection(CollectionName.users).doc(referralModel!.referralBy).get().then((value) async {
          DocumentSnapshot<Map<String, dynamic>> userDocument = value;
          if (userDocument.data() != null && userDocument.exists) {
            try {
              UserModel user = UserModel.fromJson(userDocument.data()!);
              await fireStore
                  .collection(CollectionName.users)
                  .doc(user.id)
                  .update({"wallet_amount": double.parse(user.walletAmount.toString()) + double.parse(sectionModel!.referralAmount.toString())});

              WalletTransactionModel transactionModel = WalletTransactionModel(
                  id: Constant.getUuid(),
                  amount: double.parse(sectionModel!.referralAmount.toString()),
                  date: Timestamp.now(),
                  paymentMethod: "Referral Amount",
                  transactionUser: "user",
                  userId: referralModel!.referralBy.toString(),
                  isTopup: true,
                  note: "Wallet Top-up",
                  paymentStatus: "success");

              await FireStoreUtils.setWalletTransaction(transactionModel).then((value) async {
                if (value == true) {
                  await FireStoreUtils.updateUserWallet(amount: sectionModel!.referralAmount.toString(), userId: referralModel!.referralBy.toString()).then((value) {});
                }
              });
            } catch (error) {
              log(error.toString());
            }
            print("data val");
          }
        });
      } else {
        return;
      }
    }
  }

  static Stream<List<ParcelOrderModel>> listenParcelOrders(String driverId) {
    return fireStore.collection(CollectionName.parcelOrders).where('driverId', isEqualTo: driverId).orderBy('createdAt', descending: true).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) {
        // Every parcel in the driver's history, printed on every snapshot of
        // the owner's board. Debug builds only.
        if (kDebugMode) {
          log("===>");
          print(doc.data());
        }
        return ParcelOrderModel.fromJson(doc.data());
      }).toList();
    });
  }

  static Future<List<ParcelCategory>> getParcelServiceCategory() async {
    List<ParcelCategory> parcelCategoryList = [];
    await fireStore.collection(CollectionName.parcelCategory).where('publish', isEqualTo: true).orderBy('set_order', descending: false).get().then((value) {
      for (var element in value.docs) {
        try {
          ParcelCategory category = ParcelCategory.fromJson(element.data());
          parcelCategoryList.add(category);
        } catch (e, stackTrace) {
          print('getParcelServiceCategory parse error: ${element.id} $e');
          print(stackTrace);
        }
      }
    });
    return parcelCategoryList;
  }

  static Future rentalOrderPlace(RentalOrderModel orderModel) async {
    await fireStore.collection(CollectionName.rentalOrders).doc(orderModel.id).set(orderModel.toJson());
  }

  static Future<RentalOrderModel?> getRentalOrderById(String orderId) async {
    RentalOrderModel? orderModel;
    await fireStore.collection(CollectionName.rentalOrders).doc(orderId).get().then((value) {
      if (value.exists) {
        orderModel = RentalOrderModel.fromJson(value.data()!);
      }
    });
    return orderModel;
  }

  static Stream<List<RentalOrderModel>> getRentalOrders(String driverId) {
    return fireStore.collection(CollectionName.rentalOrders).where('driverId', isEqualTo: driverId).orderBy('createdAt', descending: true).snapshots().map((
      query,
    ) {
      List<RentalOrderModel> ordersList = [];
      for (var element in query.docs) {
        ordersList.add(RentalOrderModel.fromJson(element.data()));
      }
      return ordersList;
    });
  }

  static Future<RatingModel?> getReviewsbyID(String orderId) async {
    RatingModel? ratingModel;

    await fireStore.collection(CollectionName.itemsReview).where('orderid', isEqualTo: orderId).get().then((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        ratingModel = RatingModel.fromJson(snapshot.docs.first.data());
      }
    }).catchError((error) {
      print('Error fetching review for provider: $error');
    });

    return ratingModel;
  }

  static Future<RatingModel?> updateReviewById(RatingModel ratingProduct) async {
    try {
      await fireStore.collection(CollectionName.itemsReview).doc(ratingProduct.id).set(ratingProduct.toJson());
      return ratingProduct;
    } catch (e, stackTrace) {
      print('Error updating review: $e');
      print(stackTrace);
      return null;
    }
  }

  /// Paginated sources for the driver's history screens.
  ///
  /// Deliberately the same where/orderBy shapes as the streaming versions
  /// above, so they reuse the existing composite indexes - the paginator only
  /// adds `limit()` and `startAfterDocument()`, which need no index of their
  /// own.
  static Query<Map<String, dynamic>> cabOrdersQuery(String driverId) {
    return fireStore.collection(CollectionName.ridesBooking).where('driverId', isEqualTo: driverId).orderBy('createdAt', descending: true);
  }

  static Query<Map<String, dynamic>> parcelOrdersQuery(String driverId) {
    return fireStore.collection(CollectionName.parcelOrders).where('driverId', isEqualTo: driverId).orderBy('createdAt', descending: true);
  }

  static Query<Map<String, dynamic>> rentalOrdersQuery(String driverId) {
    return fireStore.collection(CollectionName.rentalOrders).where('driverId', isEqualTo: driverId).orderBy('createdAt', descending: true);
  }

  static Query<Map<String, dynamic>> deliveryOrdersQuery(String driverId) {
    return fireStore.collection(CollectionName.vendorOrders).where('driverID', isEqualTo: driverId).orderBy('createdAt', descending: true);
  }

  static Query<Map<String, dynamic>> walletTransactionQuery() {
    return fireStore.collection(CollectionName.wallet).where('user_id', isEqualTo: FireStoreUtils.getCurrentUid()).orderBy('date', descending: true);
  }

  static Stream<List<CabOrderModel>> getCabDriverOrders(String driverId) {
    return fireStore.collection(CollectionName.ridesBooking).where('driverId', isEqualTo: driverId).orderBy('createdAt', descending: true).snapshots().map((query) {
      List<CabOrderModel> ordersList = [];
      for (var element in query.docs) {
        ordersList.add(CabOrderModel.fromJson(element.data()));
      }
      return ordersList;
    });
  }

  static Future<dynamic> getOrderByIdFromAllCollections(String orderId) async {
    final List<String> collections = [
      CollectionName.parcelOrders,
      CollectionName.rentalOrders,
      CollectionName.ridesBooking,
      CollectionName.vendorOrders,
    ];

    // All four collections are asked at once, and the answers are still read
    // in this priority order, so the same collection wins as before. Asked one
    // after the other, a tap on a wallet transaction sat through up to three
    // empty queries - with nothing on screen to say anything was happening -
    // before the order opened.
    final List<Future<QuerySnapshot<Map<String, dynamic>>?>> lookups = collections.map((String collection) async {
      try {
        return await fireStore.collection(collection).where('id', isEqualTo: orderId).limit(1).get();
      } catch (e) {
        log("Error fetching from $collection => $e");
        return null;
      }
    }).toList();

    for (int i = 0; i < collections.length; i++) {
      final snapshot = await lookups[i];
      if (snapshot != null && snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        data['collection_name'] = collections[i];
        return data;
      }
    }

    log("No order found with ID $orderId");
    return null;
  }

  static Future<List<CabOrderModel>> getCabDriverOrdersOnce(String driverId) async {
    Query query = fireStore.collection(CollectionName.ridesBooking).orderBy('createdAt', descending: true);
    if (driverId.isNotEmpty) {
      query = query.where('driverId', isEqualTo: driverId);
    }
    QuerySnapshot snapshot = await query.get();
    return snapshot.docs.map((doc) => CabOrderModel.fromJson(doc.data() as Map<String, dynamic>)).toList();
  }

  static Future<List<ParcelOrderModel>> getParcelDriverOrdersOnce(String driverId) async {
    Query query = fireStore.collection(CollectionName.parcelOrders).orderBy('createdAt', descending: true);
    if (driverId.isNotEmpty) {
      query = query.where('driverId', isEqualTo: driverId);
    }
    QuerySnapshot snapshot = await query.get();
    return snapshot.docs.map((doc) => ParcelOrderModel.fromJson(doc.data() as Map<String, dynamic>)).toList();
  }

  static Future<List<RentalOrderModel>> getRentalDriverOrdersOnce(String driverId) async {
    Query query = fireStore.collection(CollectionName.rentalOrders).orderBy('createdAt', descending: true);
    if (driverId.isNotEmpty) {
      query = query.where('driverId', isEqualTo: driverId);
    }
    QuerySnapshot snapshot = await query.get();
    return snapshot.docs.map((doc) => RentalOrderModel.fromJson(doc.data() as Map<String, dynamic>)).toList();
  }

  // ── Section-filtered order queries (for owner order list) ─────────────────
  //
  // Each of these used to run **one query per driver, in series**, with no
  // limit on any of them: a fleet of twenty drivers meant twenty round trips
  // laid end to end before the owner's list could show a single row, each one
  // downloading that driver's entire order history for the section. On a phone
  // that is the screen the client reported as never finishing.
  //
  // The queries are independent of one another, so they now run through
  // [Parallel.map], which keeps the results in driver order — the list is
  // concatenated and rendered in that order, so shuffling it would change what
  // the owner sees — and yields an empty list for a driver whose query failed
  // instead of failing the whole board.
  //
  // What each query asks, and what comes back, is unchanged.

  static Future<List<CabOrderModel>> getCabOrdersBySection({
    required String sectionId,
    required List<String> driverIds,
  }) async {
    final List<List<CabOrderModel>?> perDriver = await Parallel.map<String, List<CabOrderModel>>(
      driverIds,
      (String did) async {
        Query query = fireStore.collection(CollectionName.ridesBooking).where('driverId', isEqualTo: did).where('sectionId', isEqualTo: sectionId).orderBy('createdAt', descending: true);
        QuerySnapshot snapshot = await query.get();
        return snapshot.docs.map((doc) => CabOrderModel.fromJson(doc.data() as Map<String, dynamic>)).toList();
      },
    );

    return <CabOrderModel>[
      for (final List<CabOrderModel>? orders in perDriver) ...(orders ?? <CabOrderModel>[]),
    ];
  }

  static Future<List<ParcelOrderModel>> getParcelOrdersBySection({
    required String sectionId,
    required List<String> driverIds,
  }) async {
    final List<List<ParcelOrderModel>?> perDriver = await Parallel.map<String, List<ParcelOrderModel>>(
      driverIds,
      (String did) async {
        Query query = fireStore.collection(CollectionName.parcelOrders).where('driverId', isEqualTo: did).where('sectionId', isEqualTo: sectionId).orderBy('createdAt', descending: true);
        QuerySnapshot snapshot = await query.get();
        return snapshot.docs.map((doc) => ParcelOrderModel.fromJson(doc.data() as Map<String, dynamic>)).toList();
      },
    );

    return <ParcelOrderModel>[
      for (final List<ParcelOrderModel>? orders in perDriver) ...(orders ?? <ParcelOrderModel>[]),
    ];
  }

  static Future<List<RentalOrderModel>> getRentalOrdersBySection({
    required String sectionId,
    required List<String> driverIds,
  }) async {
    final List<List<RentalOrderModel>?> perDriver = await Parallel.map<String, List<RentalOrderModel>>(
      driverIds,
      (String did) async {
        Query query = fireStore.collection(CollectionName.rentalOrders).where('driverId', isEqualTo: did).where('sectionId', isEqualTo: sectionId).orderBy('createdAt', descending: true);
        QuerySnapshot snapshot = await query.get();
        return snapshot.docs.map((doc) => RentalOrderModel.fromJson(doc.data() as Map<String, dynamic>)).toList();
      },
    );

    return <RentalOrderModel>[
      for (final List<RentalOrderModel>? orders in perDriver) ...(orders ?? <RentalOrderModel>[]),
    ];
  }

  static Future<List<OrderModel>> getVendorOrdersBySection({
    required String sectionId,
    required List<String> driverIds,
  }) async {
    final List<List<OrderModel>?> perDriver = await Parallel.map<String, List<OrderModel>>(
      driverIds,
      (String did) async {
        Query query = fireStore.collection(CollectionName.vendorOrders).where('driverID', isEqualTo: did).where('section_id', isEqualTo: sectionId).orderBy('createdAt', descending: true);
        QuerySnapshot snapshot = await query.get();
        return snapshot.docs.map((doc) => OrderModel.fromJson(doc.data() as Map<String, dynamic>)).toList();
      },
    );

    return <OrderModel>[
      for (final List<OrderModel>? orders in perDriver) ...(orders ?? <OrderModel>[]),
    ];
  }

  static Future<bool> deleteDriverId(String uid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("❌ No user is logged in.");
        return false;
      }

      final idToken = await user.getIdToken();
      final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
      final url = Uri.parse('https://us-central1-$projectId.cloudfunctions.net/deleteUser');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'data': {'uid': uid}, // 👈 matches your Cloud Function structure
        }),
      );

      print("Response [${response.statusCode}]: ${response.body}");

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['result']?['success'] == true || decoded['success'] == true;
      } else {
        print("⚠️ Cloud Function failed: ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ Error deleting driver: $e");
      return false;
    }
  }

  static Future<InboxModel> addInbox(InboxModel inboxModel) async {
    final collection = fireStore.collection(CollectionName.chat);
    final docId = (inboxModel.senderReceiverId?.contains('admin') == false) ? inboxModel.orderId : inboxModel.senderId;
    await collection.doc(docId).set(inboxModel.toJson());
    log("inboxModel :: 22 :: ${inboxModel.senderReceiverId?.contains('admin')} :: $docId ::  ${inboxModel.toJson()} ");
    return inboxModel;
  }

  static Future<ConversationModel> addChat(ConversationModel conversationModel) async {
    final chatCollection = fireStore.collection(CollectionName.chat);
    final docId = (conversationModel.receiverId?.contains('admin') == false) ? conversationModel.orderId : conversationModel.senderId;
    await chatCollection.doc(docId).collection("thread").doc(conversationModel.id).set(conversationModel.toJson());
    log("conversationModel :: 22 :: $docId ::  ${conversationModel.toJson()} ");
    return conversationModel;
  }

  static StreamSubscription<QuerySnapshot>? adminChatSeenSubscription;

  static void setSeen() {
    final currentUserId = FireStoreUtils.getCurrentUid();

    adminChatSeenSubscription?.cancel();
    adminChatSeenSubscription = fireStore
        .collection(CollectionName.chat)
        .doc(currentUserId)
        .collection("thread")
        .where('senderId', isEqualTo: Constant.adminType)
        .where('seen', isEqualTo: false)
        .snapshots()
        .listen((querySnapshot) async {
      for (final doc in querySnapshot.docs) {
        try {
          await doc.reference.update({'seen': true});
        } catch (e) {
          log(e.toString());
        }
      }
    }, onError: (error) {
      log(error.toString());
    });
  }

  static void stopSeenListener() {
    adminChatSeenSubscription?.cancel();
    adminChatSeenSubscription = null;
  }

  static StreamSubscription<QuerySnapshot>? orderChatSeenSubscription;

  static void setSeenChatForOrder({required String orderId}) {
    orderChatSeenSubscription?.cancel();
    orderChatSeenSubscription = fireStore
        .collection(CollectionName.chat)
        .doc(orderId)
        .collection("thread")
        .where('senderId', isNotEqualTo: FireStoreUtils.getCurrentUid())
        .where('seen', isEqualTo: false)
        .snapshots()
        .listen((querySnapshot) async {
      for (final doc in querySnapshot.docs) {
        try {
          await doc.reference.update({'seen': true});
        } catch (e) {
          log(e.toString());
        }
      }
    }, onError: (error) {
      log(error.toString());
    });
  }
}
