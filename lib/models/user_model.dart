import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/models/admin_commission.dart';
import 'package:driver/models/cab_order_model.dart';
import 'package:driver/models/subscription_plan_model.dart';
import 'package:driver/utils/my_trips_access.dart';

class UserModel {
  String? id;
  String? firstName;
  String? lastName;
  String? email;
  String? profilePictureURL;
  String? fcmToken;
  String? countryCode;
  String? countryISOCode;
  String? phoneNumber;
  num? walletAmount;
  bool? active;
  bool? isActive;
  bool? isDocumentVerify;
  Timestamp? createdAt;
  String? role;
  UserLocation? location;
  UserBankDetails? userBankDetails;
  List<ShippingAddress>? shippingAddress;
  String? carPictureURL;
  List<dynamic>? inProgressOrderID;
  List<dynamic>? orderRequestData;
  String? vendorID;
  String? zoneId;
  num? rotation;
  String? appIdentifier;
  String? provider;
  String? subscriptionPlanId;
  Timestamp? subscriptionExpiryDate;
  SubscriptionPlanModel? subscriptionPlan;
  List<String>? serviceTypes;
  List<String>? sectionIds;
  Map<String, String>? sectionNames; // {sectionId: sectionName}
  Map<String, dynamic>? vehicleDetails; // {sectionId: {vehicleId, vehicleType, carBrand, carModel, carPlateNumber}}
  String? reviewsCount;

  /// Completed-ride counter maintained by the admin panel
  /// (`users/{id}.orderCompleted`).
  ///
  /// Read only - deliberately absent from [toJson] so the app can never write
  /// a stale value back over the counter the panel keeps.
  num? orderCompleted;

  /// Admin-granted, time-limited permission to use the My Trips feature
  /// (`users/{id}.myTripsAccess`).
  ///
  /// Read only, and deliberately absent from [toJson] for the same reason
  /// [orderCompleted] is: the app must never be able to write its own access
  /// back over what the admin panel granted.
  MyTripsAccess myTripsAccess = MyTripsAccess.none;
  String? reviewsSum;
  AdminCommission? adminCommissionModel;
  CabOrderModel? orderCabRequestData;

  /// Whether this copy was read with a ride request on it - the only case in
  /// which saving it may clear the request. Never written; see `CabRequestSlot`.
  bool loadedWithCabRequest = false;
  String? rideType;
  String? ownerId;
  bool? isOwner;
  bool? isAutoVerify;

  UserModel({
    this.id,
    this.firstName,
    this.lastName,
    this.active,
    this.isActive,
    this.isDocumentVerify,
    this.email,
    this.profilePictureURL,
    this.fcmToken,
    this.countryCode,
    this.countryISOCode,
    this.phoneNumber,
    this.walletAmount,
    this.createdAt,
    this.role,
    this.location,
    this.shippingAddress,
    this.carPictureURL,
    this.inProgressOrderID,
    this.orderRequestData,
    this.vendorID,
    this.zoneId,
    this.rotation,
    this.appIdentifier,
    this.provider,
    this.subscriptionPlanId,
    this.subscriptionExpiryDate,
    this.subscriptionPlan,
    this.serviceTypes,
    this.sectionIds,
    this.sectionNames,
    this.vehicleDetails,
    this.reviewsCount,
    this.reviewsSum,
    this.adminCommissionModel,
    this.orderCabRequestData,
    this.rideType,
    this.ownerId,
    this.isOwner,
    this.isAutoVerify,
  });

  String fullName() {
    return "${firstName ?? ''} ${lastName ?? ''}";
  }

  double get averageRating {
    final double sum = double.tryParse(reviewsSum ?? '0') ?? 0.0;
    final double count = double.tryParse(reviewsCount ?? '0') ?? 0.0;

    if (count <= 0) return 0.0;
    return sum / count;
  }

  UserModel.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    email = json['email'];
    firstName = json['firstName'];
    lastName = json['lastName'];
    profilePictureURL = json['profilePictureURL'];
    fcmToken = json['fcmToken'];
    countryCode = json['countryCode'];
    countryISOCode = json['countryISOCode'];
    phoneNumber = json['phoneNumber'];
    walletAmount = json['wallet_amount'] ?? 0;
    createdAt = json['createdAt'];
    active = json['active'];
    isActive = json['isActive'];
    isDocumentVerify = json['isDocumentVerify'] ?? false;
    role = json['role'] ?? 'user';
    location = json['location'] != null ? UserLocation.fromJson(json['location']) : null;
    userBankDetails = json['userBankDetails'] != null ? UserBankDetails.fromJson(json['userBankDetails']) : null;
    if (json['shippingAddress'] != null) {
      shippingAddress = <ShippingAddress>[];
      json['shippingAddress'].forEach((v) {
        shippingAddress!.add(ShippingAddress.fromJson(v));
      });
    }
    carPictureURL = json['carPictureURL'];
    inProgressOrderID = json['inProgressOrderID'] ?? [];
    orderRequestData = json['orderRequestData'] ?? [];
    vendorID = json['vendorID'] ?? '';
    zoneId = json['zoneId'] ?? '';
    rotation = json['rotation'];
    appIdentifier = json['appIdentifier'];
    provider = json['provider'];
    subscriptionPlanId = json['subscriptionPlanId'];
    subscriptionExpiryDate = json['subscriptionExpiryDate'];
    subscriptionPlan = json['subscription_plan'] != null ? SubscriptionPlanModel.fromJson(json['subscription_plan']) : null;
    // serviceTypes: use new field; fall back to legacy serviceType for old documents.
    //
    // Blank entries are dropped rather than kept. `serviceType: ''` is a real
    // shape in this project - eight driver documents carry it - and reading it
    // as `['']` made the driver a delivery rider twice over: `['']` matches no
    // case in `_navigateByServiceType`, so it fell through to the delivery
    // default, and the empty string was then written back as the driver's
    // answer. An empty answer has to stay empty so the section fallback can
    // supply a real one.
    serviceTypes = _flags(json['serviceTypes'], json['serviceType']);
    // sectionIds: use new field; fall back to legacy sectionId for old documents
    sectionIds = _flags(json['sectionIds'], json['sectionId']);
    // sectionNames: use new field; fall back to legacy serviceDetails for old documents
    if (json['sectionNames'] != null) {
      sectionNames = Map<String, String>.from(json['sectionNames']);
    } else if (json['serviceDetails'] != null) {
      final legacy = Map<String, dynamic>.from(json['serviceDetails']);
      sectionNames = {for (final e in legacy.entries) e.key: (e.value['sectionName'] ?? e.key).toString()};
    }
    vehicleDetails = json['vehicleDetails'] != null ? Map<String, dynamic>.from(json['vehicleDetails']) : null;
    reviewsCount = json['reviewsCount'] == null ? '0' : json['reviewsCount'].toString();
    orderCompleted = json['orderCompleted'] is num ? json['orderCompleted'] as num : num.tryParse(json['orderCompleted']?.toString() ?? '');
    myTripsAccess = MyTripsAccess.fromUserJson(json);
    reviewsSum = json['reviewsSum'] == null ? '0' : json['reviewsSum'].toString();
    adminCommissionModel = json['adminCommission'] != null ? AdminCommission.fromJson(json['adminCommission']) : null;
    orderCabRequestData = json['ordercabRequestData'] != null ? CabOrderModel.fromJson(json['ordercabRequestData']) : null;
    loadedWithCabRequest = json['ordercabRequestData'] != null;
    rideType = json['rideType'];
    ownerId = json['ownerId'];
    isOwner = json['isOwner'];
    isAutoVerify = json['isAutoVerify'];
  }

  /// The non-blank entries of a plural field, or of the legacy singular one
  /// that preceded it, or null when neither says anything.
  ///
  /// Null and "the document has nothing to say" are the same thing here, and
  /// they have to stay distinguishable from a real value: [toJson] writes these
  /// fields only when they are non-null, which is what stops an incidental save
  /// from overwriting a service the driver's document already recorded.
  static List<String>? _flags(Object? plural, Object? singular) {
    if (plural is List) {
      final List<String> kept = plural
          .map((Object? entry) => entry?.toString().trim() ?? '')
          .where((String entry) => entry.isNotEmpty)
          .toList();
      // A plural field that is present but says nothing usable - `[]`, or a
      // list of blanks - is not an answer, so it falls through to the legacy
      // field rather than shadowing it. Nothing in the project is stored that
      // way today; the fallback is here so a document that ever is still gets
      // the service the panel recorded, instead of one derived from its
      // sections.
      if (kept.isNotEmpty) return kept;
    }
    final String one = singular?.toString().trim() ?? '';
    return one.isEmpty ? null : <String>[one];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['email'] = email;
    data['firstName'] = firstName;
    data['lastName'] = lastName;
    data['profilePictureURL'] = profilePictureURL;
    data['fcmToken'] = fcmToken;
    data['countryCode'] = countryCode;
    data['countryISOCode'] = countryISOCode;
    data['phoneNumber'] = phoneNumber;
    data['wallet_amount'] = walletAmount ?? 0;
    data['createdAt'] = createdAt;
    data['active'] = active;
    data['isActive'] = isActive;
    data['role'] = role;
    data['isDocumentVerify'] = isDocumentVerify;
    data['zoneId'] = zoneId;

    if (location != null) {
      data['location'] = location!.toJson();
    }
    if (userBankDetails != null) {
      data['userBankDetails'] = userBankDetails!.toJson();
    }
    if (shippingAddress != null) {
      data['shippingAddress'] = shippingAddress!.map((v) => v.toJson()).toList();
    }
    // Written only when this model actually carries them.
    //
    // These two used to be `serviceTypes ?? ['delivery-service']` and
    // `sectionIds ?? []`, which meant any save of a model that had not loaded
    // them - and `updateUser` is called from thirty places, most of them saving
    // something else entirely, like the push token at launch - **rewrote** the
    // driver's service as delivery and emptied their sections. The driver was
    // then a delivery driver for good: `updateUser` also deletes the legacy
    // `serviceType` field the admin panel writes, so the guess was the only
    // answer left. That is the "I closed the driver app and when i opened again
    // then my cab service is converted to delivery" the client reported.
    //
    // A field this model does not hold is now simply not written, and
    // `updateUser`'s `removeNulls` drops it, so the value already in Firestore
    // survives. Everything that legitimately sets a driver's sections - signup,
    // Change Section, an owner creating a driver - sets them on the model
    // first, so those writes are unchanged.
    if (serviceTypes != null) data['serviceTypes'] = serviceTypes;
    if (sectionIds != null) data['sectionIds'] = sectionIds;
    if (sectionNames != null) data['sectionNames'] = sectionNames;
    if (vehicleDetails != null) data['vehicleDetails'] = vehicleDetails;
    data['rotation'] = rotation;
    data['inProgressOrderID'] = inProgressOrderID;

    if (role == Constant.userRoleDriver) {
      data['vendorID'] = vendorID;
      data['carPictureURL'] = carPictureURL;
      data['orderRequestData'] = orderRequestData;
      if (orderCabRequestData != null) {
        data['ordercabRequestData'] = orderCabRequestData!.toJson();
      }
      data['ownerId'] = ownerId;
      data['isOwner'] = isOwner;
    }
    if (role == Constant.userRoleVendor) {
      data['vendorID'] = vendorID;
      data['subscriptionPlanId'] = subscriptionPlanId;
      data['subscriptionExpiryDate'] = subscriptionExpiryDate;
      data['subscription_plan'] = subscriptionPlan?.toJson();
    }
    data['appIdentifier'] = appIdentifier;
    data['provider'] = provider;
    data['reviewsCount'] = reviewsCount;
    data['reviewsSum'] = reviewsSum;
    data['isAutoVerify'] = isAutoVerify;
    if (adminCommissionModel != null) {
      data['adminCommission'] = adminCommissionModel!.toJson();
    }
    return data;
  }
}

class UserLocation {
  double? latitude;
  double? longitude;

  UserLocation({this.latitude, this.longitude});

  UserLocation.fromJson(Map<String, dynamic> json) {
    latitude = json['latitude'];
    longitude = json['longitude'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['latitude'] = latitude;
    data['longitude'] = longitude;
    return data;
  }
}

class ShippingAddress {
  String? id;
  String? address;
  String? addressAs;
  String? landmark;
  String? locality;
  UserLocation? location;
  bool? isDefault;

  ShippingAddress({this.address, this.landmark, this.locality, this.location, this.isDefault, this.addressAs, this.id});

  ShippingAddress.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    address = json['address'];
    landmark = json['landmark'];
    locality = json['locality'];
    isDefault = json['isDefault'];
    addressAs = json['addressAs'];
    location = json['location'] == null ? null : UserLocation.fromJson(json['location']);
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['address'] = address;
    data['landmark'] = landmark;
    data['locality'] = locality;
    data['isDefault'] = isDefault;
    data['addressAs'] = addressAs;
    if (location != null) {
      data['location'] = location!.toJson();
    }
    return data;
  }

  String getFullAddress() {
    return '${address == null || address!.isEmpty ? "" : address} $locality ${landmark == null || landmark!.isEmpty ? "" : landmark.toString()}';
  }
}

class UserBankDetails {
  String bankName;
  String branchName;
  String holderName;
  String accountNumber;
  String otherDetails;

  UserBankDetails({
    this.bankName = '',
    this.otherDetails = '',
    this.branchName = '',
    this.accountNumber = '',
    this.holderName = '',
  });

  factory UserBankDetails.fromJson(Map<String, dynamic> parsedJson) {
    return UserBankDetails(
      bankName: parsedJson['bankName'] ?? '',
      branchName: parsedJson['branchName'] ?? '',
      holderName: parsedJson['holderName'] ?? '',
      accountNumber: parsedJson['accountNumber'] ?? '',
      otherDetails: parsedJson['otherDetails'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bankName': bankName,
      'branchName': branchName,
      'holderName': holderName,
      'accountNumber': accountNumber,
      'otherDetails': otherDetails,
    };
  }
}
