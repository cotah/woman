// File generated manually from:
//   - mobile-app/android/app/google-services.json
//   - mobile-app/ios/Runner/GoogleService-Info.plist
//
// Equivalent to running `flutterfire configure`. Regenerate (or update
// by hand) whenever the underlying Firebase configs change. Constants
// here are PUBLIC client identifiers — no secrets. The same values are
// already shipped inside the platform config files bundled with the
// app, so checking them in to source control is intentional.
//
// ignore_for_file: type=lint

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with Firebase.initializeApp.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web — '
        'this app does not support FCM in the browser.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for $defaultTargetPlatform',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDEmmIdqVpNcDmKS6ZGGBGz9E-EofepwLU',
    appId: '1:78625778867:android:73fe23d36f99d4ac96d4c6',
    messagingSenderId: '78625778867',
    projectId: 'woman-5ccfc',
    storageBucket: 'woman-5ccfc.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBCDRT0R7S1hiknfMYLWLcZ1V7jPtcrjTg',
    appId: '1:78625778867:ios:9ad5f9a923f9d68e96d4c6',
    messagingSenderId: '78625778867',
    projectId: 'woman-5ccfc',
    storageBucket: 'woman-5ccfc.firebasestorage.app',
    iosBundleId: 'com.safecircle.safecircle',
  );
}
