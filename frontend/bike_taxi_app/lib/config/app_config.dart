import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _envApiBaseUrl = String.fromEnvironment("API_BASE_URL");

  static String get apiBaseUrl {
    if (_envApiBaseUrl.isNotEmpty) {
      return _envApiBaseUrl;
    }

    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == "localhost" || host == "127.0.0.1") {
        return "http://localhost:5000/api";
      }
      return "https://biketaxi.onrender.com/api";
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return "https://biketaxi.onrender.com/api";
    }

    return "https://biketaxi.onrender.com/api";
  }

  static const String photonBaseUrl = String.fromEnvironment(
    "PHOTON_BASE_URL",
    defaultValue: "https://photon.komoot.io/api/",
  );

  /// Default fallback location in Ariyalur, Tamil Nadu
  static const double defaultLat = 11.1401;
  static const double defaultLng = 79.0786;
  static const String defaultCityName = "Ariyalur, Tamil Nadu";
}
