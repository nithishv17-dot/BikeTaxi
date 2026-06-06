import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _envApiBaseUrl = String.fromEnvironment("API_BASE_URL");

  static String get apiBaseUrl {
    if (_envApiBaseUrl.isNotEmpty) {
      return _envApiBaseUrl;
    }

    if (kIsWeb) {
      return "http://localhost:5000/api";
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return "http://10.0.2.2:5000/api";
    }

    return "http://localhost:5000/api";
  }

  static const String photonBaseUrl = String.fromEnvironment(
    "PHOTON_BASE_URL",
    defaultValue: "https://photon.komoot.io/api/",
  );
}
