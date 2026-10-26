import 'package:driver/constant/constant.dart';
import 'package:driver/themes/app_them_data.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:driver/utils/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

/// The terms of service, or the privacy policy.
///
/// The text used to arrive through two live listeners opened during startup,
/// which meant every driver downloaded 120 KB of legal copy on every launch of
/// the app whether or not they ever opened either screen. This asks for its own
/// document when it is opened, and keeps it, so the second visit is instant and
/// startup carries none of it.
class TermsAndConditionScreen extends StatefulWidget {
  final String? type;

  const TermsAndConditionScreen({super.key, this.type});

  @override
  State<TermsAndConditionScreen> createState() => _TermsAndConditionScreenState();
}

class _TermsAndConditionScreenState extends State<TermsAndConditionScreen> {
  bool get _isPrivacy => widget.type == "privacy";

  String get _cacheKey => _isPrivacy ? Preferences.privacyPolicyKey : Preferences.termsAndConditionsKey;

  /// What is on the device, drawn on the first frame. Empty on a first visit,
  /// which is the only time this screen shows a loader.
  late String _html = Preferences.getString(_cacheKey);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final String latest = await FireStoreUtils.legalDocument(
      documentId: _isPrivacy ? "privacyPolicy" : "termsAndConditions",
      field: _isPrivacy ? "privacy_policy" : "terms_and_condition",
      cacheKey: _cacheKey,
    );
    // Kept on `Constant` as well, because that is where the rest of the app
    // has always looked for them.
    if (latest.isNotEmpty) {
      if (_isPrivacy) {
        Constant.privacyPolicy = latest;
      } else {
        Constant.termsAndConditions = latest;
      }
    }
    if (!mounted || latest.isEmpty || latest == _html) return;
    setState(() => _html = latest);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeData.grey50,
      body: _html.isEmpty
          ? Constant.loader()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SingleChildScrollView(
                child: Html(
                  shrinkWrap: true,
                  data: _html,
                ),
              ),
            ),
    );
  }
}
