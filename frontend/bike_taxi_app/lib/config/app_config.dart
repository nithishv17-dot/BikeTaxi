import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _envApiBaseUrl = String.fromEnvironment("API_BASE_URL");
  static const String _envSocketUrl = String.fromEnvironment("SOCKET_URL");

  static const String googleClientId =
      "57219954065-obscrq1h5ohuaeiclt58msjm7kjmh5v6.apps.googleusercontent.com";

  static String get apiBaseUrl {
    if (_envApiBaseUrl.isNotEmpty) {
      return _envApiBaseUrl;
    }

    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == "localhost" || host == "127.0.0.1") {
        return "http://localhost:5000/api";
      }
      return "https://biketaxi-1.onrender.com/api";
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return "https://biketaxi-1.onrender.com/api";
    }

    return "https://biketaxi-1.onrender.com/api";
  }

  static String get socketUrl {
    if (_envSocketUrl.isNotEmpty) {
      return _envSocketUrl;
    }

    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == "localhost" || host == "127.0.0.1") {
        return "http://localhost:5000";
      }
      return "https://biketaxi-1.onrender.com";
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return "https://biketaxi-1.onrender.com";
    }

    return "https://biketaxi-1.onrender.com";
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
