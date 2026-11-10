import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

class LocationService {
  /// Robust geolocation resolver for web and mobile browsers:
  ///
  /// 1. [GPS]: Attempts HTML5 high-accuracy geolocation (GPS / Wi-Fi trilateration) with an 8-second timeout.
  /// 2. [Network]: If high accuracy times out or is unavailable on desktop, immediately retries standard accuracy
  ///    (Windows Location / Network positioning) with an 8-second timeout.
  /// 3. [Fallback]: If HTML5 geolocation is denied, blocked, or times out, directly and immediately falls back
  ///    to Ariyalur, Tamil Nadu (AppConfig.defaultLat, AppConfig.defaultLng).
  ///
  /// IMPORTANT: Desktop Chrome Wi-Fi / network positioning typically has an accuracy radius between 100m
  /// and 3000m. Valid coordinates are NEVER rejected due to wide accuracy radii.
  /// Third-party IP-lookup APIs are completely eliminated to prevent broadband ISP routing to regional hubs (e.g. Salem).
  static Future<Map<String, double>?> getBestCurrentLocation({
    Duration timeout = const Duration(milliseconds: 10000),
    bool allowFallback = true,
  }) async {
    try {
      // Step 1: High Accuracy (GPS / Wi-Fi trilateration) with timeout
      debugPrint("[GPS] Requesting HTML5 high-accuracy geolocation (${timeout.inSeconds}s timeout)...");
      final highFix = await _tryHtml5Geolocation(
        highAccuracy: true,
        timeout: timeout,
      );
      if (highFix != null) {
        return highFix;
      }

      // Step 2: High accuracy timed out or failed on desktop -> immediately retry standard accuracy
      debugPrint("[Network] High-accuracy timed out or unavailable. Retrying HTML5 standard accuracy (${timeout.inSeconds}s timeout)...");
      final stdFix = await _tryHtml5Geolocation(
        highAccuracy: false,
        timeout: timeout,
      );
      if (stdFix != null) {
        return stdFix;
      }
    } catch (e) {
      debugPrint("[LocationService] Error resolving location: $e");
    }

    if (!allowFallback) {
      debugPrint("[LocationService] Geolocation fix unavailable/denied and allowFallback is false.");
      return null;
    }

    // Step 3: Default fallback directly to Ariyalur, Tamil Nadu (no third-party IP lookups)
    debugPrint("[Fallback] HTML5 geolocation unavailable/denied. Falling back directly to Ariyalur: (${AppConfig.defaultLat}, ${AppConfig.defaultLng})");
    return {
      'lat': AppConfig.defaultLat,
      'lng': AppConfig.defaultLng,
      'accuracy': 10000.0,
    };
  }

  static Future<Map<String, double>?> getCurrentPosition({bool allowFallback = true}) async {
    return getBestCurrentLocation(allowFallback: allowFallback);
  }

  static Future<Map<String, double>?> _tryHtml5Geolocation({
    required bool highAccuracy,
    required Duration timeout,
  }) async {
    final completer = Completer<Map<String, double>?>();
    final tag = highAccuracy ? "[GPS]" : "[Network]";

    try {
      html.window.navigator.geolocation.getCurrentPosition(
        enableHighAccuracy: highAccuracy,
        timeout: timeout,
        maximumAge: Duration.zero,
      ).then((pos) {
        final coords = pos.coords;
        if (coords != null && coords.latitude != null && coords.longitude != null) {
          final lat = coords.latitude!.toDouble();
          final lng = coords.longitude!.toDouble();
          final accuracy = coords.accuracy?.toDouble() ?? (highAccuracy ? 15.0 : 1000.0);

          debugPrint("$tag HTML5 Geolocation fix: ($lat, $lng) ±${accuracy.toStringAsFixed(1)}m");
          if (!completer.isCompleted) {
            completer.complete({
              'lat': lat,
              'lng': lng,
              'accuracy': accuracy,
            });
          }
        } else {
          if (!completer.isCompleted) completer.complete(null);
        }
      }).catchError((error) {
        debugPrint("$tag Geolocation error: $error");
        if (!completer.isCompleted) completer.complete(null);
      });
    } catch (e) {
      debugPrint("$tag Failed to initiate geolocation: $e");
      if (!completer.isCompleted) completer.complete(null);
    }

    // Safety timeout in Dart so browser driver hangs don't stall execution
    return completer.future.timeout(
      timeout + const Duration(milliseconds: 500),
      onTimeout: () {
        debugPrint("$tag Geolocation timed out after ${timeout.inSeconds}s");
        return null;
      },
    );
  }
}

