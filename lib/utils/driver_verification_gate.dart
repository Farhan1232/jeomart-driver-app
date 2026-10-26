import 'package:driver/constant/constant.dart';
import 'package:driver/models/user_model.dart';

/// Whether [user] should be shown the "upload your documents" screen instead of
/// the screen they opened.
///
/// ## What was wrong
///
/// Every driver home screen decided this for itself, with the same expression:
///
/// ```dart
/// user.isDocumentVerify == false && user.isAutoVerify == false
/// ```
///
/// Both of those are fields on the driver's own `users` document, written **once
/// at signup**. `isAutoVerify` is set from the admin's verification switch at
/// the moment the account is created:
///
/// ```dart
/// userModel.isAutoVerify = Constant.isDriverVerification == false;
/// ```
///
/// So it is a *snapshot of a setting*, not a fact about the driver — and
/// nothing ever writes it again. When the admin later turns document
/// verification **off**, every account created while it was on keeps
/// `isAutoVerify: false` for ever, and every one of those drivers stays locked
/// on the documents screen.
///
/// On this project that is exactly what happened. `document_verification_settings`
/// has `isDriverVerification: false` and `isOwnerVerification: false` — the admin
/// has switched verification off — yet **23 of the 40 live driver accounts** still
/// carry `isAutoVerify: false` and `isDocumentVerify: false`. All 23 open the app,
/// land on the home screen, and get the documents screen where the map should be.
/// That is the "why is the map not showing" report: the map was never built, on
/// any of those accounts, for any reason to do with maps.
///
/// ## The rule now
///
/// The admin's live setting is the authority, because it is the thing the admin
/// can actually change. The per-account flags are still honoured underneath it,
/// so nothing changes for a project that *does* require verification:
///
/// * verification switched **off** → nobody is gated, whatever their stale flag
///   says;
/// * verification switched **on** → exactly the old behaviour, field for field.
///
/// The comparisons below are deliberately still `== false` rather than `!= true`.
/// A `UserModel` that has not loaded yet has `null` in both fields, and `null ==
/// false` is `false`, so an unloaded driver is not gated — which is what the
/// screens already relied on to avoid flashing the documents screen before the
/// profile arrives.
bool driverAwaitsDocumentVerification(UserModel? user) {
  if (user == null) return false;

  final bool verificationRequired =
      user.isOwner == true ? Constant.isOwnerVerification : Constant.isDriverVerification;
  if (!verificationRequired) return false;

  return user.isDocumentVerify == false && user.isAutoVerify == false;
}
