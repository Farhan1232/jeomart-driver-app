<p align="center"><img src="docs/images/logo.png" width="110" alt="logo"/></p>

<h1 align="center">JEOM Mart — Driver App</h1>
<p align="center"><b>The driver and delivery-rider app: take rides, bid on fares, deliver orders and track earnings.</b></p>

<p align="center">
<img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white"/>
<img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white"/>
<img src="https://img.shields.io/badge/Firebase-Firestore%20%7C%20Auth%20%7C%20FCM-FFCA28?logo=firebase&logoColor=black"/>
<img src="https://img.shields.io/badge/State-GetX-8A2BE2"/>
<img src="https://img.shields.io/badge/Platforms-Android%20%7C%20iOS-3DDC84?logo=android&logoColor=white"/>
</p>

<p align="center">Version <b>6.2.17+65</b></p>

---

## ✨ Features

### 🚗 Rides
- Online / offline switch with live location sharing
- Incoming ride requests with ringtone and accept / reject
- **Bidding**: send a fare offer on customer ride requests
- **Post intercity trips** (My Trips) and manage bookings
- Turn-by-turn route to pickup and drop-off, ride OTP, SOS

### 📦 Deliveries
- Food, grocery and parcel delivery jobs
- Pickup → delivered flow with order details and live map
- Rental and multi-service (cab + delivery) modes

### 💰 Earnings & account
- Wallet, earnings history, withdraw requests and payout methods
- Document upload and verification, vehicle information
- Fleet owner mode (manage drivers and vehicles)
- Chat with customers and stores, push notifications, multi-language

## 🧩 The JEOM Mart ecosystem

| Repository | What it is |
|---|---|
| [jeomart-customer-app](https://github.com/Farhan1232/jeomart-customer-app) | Customer app: rides, food, grocery, parcels, rentals, services |
| [jeomart-driver-app](https://github.com/Farhan1232/jeomart-driver-app) | Driver app: ride requests, bidding, deliveries, earnings |
| [jeomart-vendor-app](https://github.com/Farhan1232/jeomart-vendor-app) | Store / restaurant app: menu, orders, staff, payouts |
| [jeomart-admin-panel](https://github.com/Farhan1232/jeomart-admin-panel) | Web admin panel (Laravel) that runs the whole platform |

```mermaid
flowchart LR
    C[📱 Customer app] <--> FS[(Firebase<br/>Firestore · Auth · Storage · FCM)]
    D[🚗 Driver app] <--> FS
    V[🏪 Vendor app] <--> FS
    A[🖥️ Admin panel<br/>Laravel] <--> FS
    A -- scheduled jobs<br/>ride dispatch --> FS
    FS -- push notifications --> C & D & V
```

## 🛠️ Tech stack

| Layer | Technology |
|---|---|
| UI | Flutter, Material |
| State / routing | GetX |
| Backend | Firebase Firestore, Auth, Storage, Realtime Database, App Check |
| Notifications | Firebase Cloud Messaging |
| Maps | Google Maps + OpenStreetMap (flutter_map), OSRM routing |
| Location | geolocator |

## 📁 Project structure

```
lib/
├── app/             # screens: home, cab, parcel, rental, owner, wallet, verification …
├── controllers/     # GetX controllers
├── models/          # Firestore data models
├── services/        # audio (ride ringtone), location, notifications
├── utils/           # Firestore access (fire_store_utils.dart), helpers
├── payment/         # payment integrations
├── widget/          # shared widgets, map widgets
├── lang/            # translations
└── themes/
test/                # unit and widget tests
```

## ⚙️ Getting started

### Requirements
- Flutter (stable) with Dart `^3.7.2`
- Android Studio / Xcode
- A Firebase project (Auth, Firestore, Storage, Cloud Messaging enabled)
- A Google Maps Platform API key

### 1. Install
```bash
git clone https://github.com/Farhan1232/jeomart-driver-app.git
cd jeomart-driver-app
flutter pub get
```

### 2. Connect your own Firebase project
All Firebase and Google keys in this repository are **placeholders**. Generate your own config:
```bash
dart pub global activate flutterfire_cli
flutterfire configure      # writes lib/firebase_options.dart
```
Then add the platform files (not committed on purpose):
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

### 3. Add your Google Maps key
Replace `YOUR_GOOGLE_MAPS_API_KEY` in:

| File | Used for |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | Map display on Android |
| `ios/Runner/AppDelegate.swift` | Map display on iOS |
| `lib/constant/constant.dart` | Fallback key (the live key is loaded from Firestore `settings/googleMapKey`) |

### 4. Run
```bash
flutter run
```

### 5. Release build
Create `android/key.properties` and your keystore (both git-ignored), then:
```bash
flutter build appbundle --release
```

## 🔐 Security notes
- No keystores, `key.properties`, `google-services.json`, `GoogleService-Info.plist` or `.env` files are in this repo.
- Restrict your Google Maps key to your app's package name and SHA-1.
- Lock down your Firestore security rules before going live.

## 🧪 Tests
```bash
flutter test
```

## 📄 Credits

Built on the **eMart** multi-vendor / multi-service platform, then customised and extended for **JEOM Mart** (Pakistan): ride bidding, intercity trips, city administration, performance work and many fixes.

Maintained by [Farhan](https://github.com/Farhan1232).
