import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseBootstrap {
  static bool _initialized = false;
  static bool get initialized => _initialized;
  static String get adminEmail => _adminEmail.trim().toLowerCase();

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _adminEmail = String.fromEnvironment('FIREBASE_ADMIN_EMAIL');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  static bool get _hasAnyConfiguration => [
    _apiKey,
    _adminEmail,
    _projectId,
    _messagingSenderId,
    _authDomain,
    _webAppId,
    _androidAppId,
    _iosAppId,
    _iosBundleId,
  ].any((value) => value.isNotEmpty);

  static Future<void> initialize() async {
    if (!_hasAnyConfiguration) return;

    if (!kIsWeb &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      throw StateError(
        'Firebase yapılandırması yalnızca web, Android ve iOS için hazır.',
      );
    }
    final appId = kIsWeb
        ? _webAppId
        : defaultTargetPlatform == TargetPlatform.android
        ? _androidAppId
        : _iosAppId;
    final requiredValues = <String, String>{
      'FIREBASE_API_KEY': _apiKey,
      'FIREBASE_ADMIN_EMAIL': _adminEmail,
      'FIREBASE_PROJECT_ID': _projectId,
      'FIREBASE_MESSAGING_SENDER_ID': _messagingSenderId,
      if (kIsWeb) 'FIREBASE_AUTH_DOMAIN': _authDomain,
      if (kIsWeb) 'FIREBASE_WEB_APP_ID': _webAppId,
      if (defaultTargetPlatform == TargetPlatform.android)
        'FIREBASE_ANDROID_APP_ID': _androidAppId,
      if (defaultTargetPlatform == TargetPlatform.iOS) ...{
        'FIREBASE_IOS_APP_ID': _iosAppId,
        'FIREBASE_IOS_BUNDLE_ID': _iosBundleId,
      },
    };
    final missing = requiredValues.entries
        .where((entry) => entry.value.isEmpty)
        .map((entry) => entry.key)
        .toList();
    if (missing.isNotEmpty) {
      throw StateError('Firebase yapılandırması eksik: ${missing.join(', ')}');
    }

    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: _apiKey,
        appId: appId,
        messagingSenderId: _messagingSenderId,
        projectId: _projectId,
        authDomain: kIsWeb ? _authDomain : null,
        iosBundleId: defaultTargetPlatform == TargetPlatform.iOS
            ? _iosBundleId
            : null,
      ),
    );
    _initialized = true;
  }
}
