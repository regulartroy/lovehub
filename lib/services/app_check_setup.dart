import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// reCAPTCHA Enterprise site key for the LoveHub web app (public value).
///
/// TODO(app-check): paste the key created in Google Cloud > Security >
/// reCAPTCHA (score-based, website, domains love-hub.web.app,
/// lovehub-26107.web.app, lovehub-26107.firebaseapp.com, localhost).
/// Can also be passed with --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=...
const String kRecaptchaEnterpriseSiteKey = String.fromEnvironment(
  'RECAPTCHA_ENTERPRISE_SITE_KEY',
  defaultValue: '',
);

/// Whether App Check should be activated for this build.
bool shouldActivateAppCheck({required bool isWeb, required String siteKey}) =>
    isWeb && siteKey.trim().isNotEmpty;

/// Activates Firebase App Check on web so Firebase AI Logic (Gemini Smart
/// Sort) requests carry a token. Only AI Logic is meant to be enforced.
/// Never throws: a failure here must not stop the app starting.
Future<void> activateAppCheck() async {
  if (!shouldActivateAppCheck(
    isWeb: kIsWeb,
    siteKey: kRecaptchaEnterpriseSiteKey,
  )) {
    return;
  }
  try {
    await FirebaseAppCheck.instance.activate(
      providerWeb: ReCaptchaEnterpriseProvider(kRecaptchaEnterpriseSiteKey),
    );
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  } catch (e) {
    debugPrint('App Check activation failed: $e');
  }
}
