import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'session_service.dart';
import 'socket_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class ApiService {
  static String get baseUrl => AppConfig.apiBaseUrl;
  static const String photonBaseUrl = AppConfig.photonBaseUrl;
  static String? token;
  static bool _isLoggingOut = false;

  static Map<String, String> _authHeaders() {
    final headers = <String, String>{
      "Content-Type": "application/json",
      "Bypass-Tunnel-Reminder": "true",
    };

    if (token == null || token!.isEmpty) {
      final session = SessionService.loadSession();
      if (session != null && session['token'] != null && session['token']!.isNotEmpty) {
        token = session['token'];
      }
    }

    if (token != null && token!.isNotEmpty) {
      headers["Authorization"] = "Bearer $token";
    }

    return headers;
  }

  static Map<String, String> _locationHeaders() {
    return <String, String>{
      "Accept": "application/json",
      "Accept-Language": "en",
    };
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final cleanPath = path.startsWith("/api") ? path.substring(4) : path;
    final url = cleanPath.startsWith("/") ? "$baseUrl$cleanPath" : "$baseUrl/$cleanPath";
    final isAuth = cleanPath.contains("auth") || cleanPath.contains("login") || cleanPath.contains("register");
    final response = await http.post(
      Uri.parse(url),
      headers: isAuth
          ? {
              "Content-Type": "application/json",
              "Bypass-Tunnel-Reminder": "true",
            }
          : _authHeaders(),
      body: jsonEncode(body),
    );
    return _handleResponse(response, isAuthEndpoint: isAuth);
  }

  static Future<Map<String, dynamic>> login(
    String identifier,
    String password, {
    String role = "user",
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/login"),
      headers: {
        "Content-Type": "application/json",
        "Bypass-Tunnel-Reminder": "true",
      },
      body: jsonEncode({"identifier": identifier, "password": password, "role": role}),
    );

    return _handleResponse(response, isAuthEndpoint: true);
  }

  static Future<Map<String, dynamic>> guestLogin(String role) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/guest-login"),
      headers: {
        "Content-Type": "application/json",
        "Bypass-Tunnel-Reminder": "true",
      },
      body: jsonEncode({"role": role}),
    );

    return _handleResponse(response, isAuthEndpoint: true);
  }

  static Future<Map<String, dynamic>> googleLogin(
    String idToken,
    String role, {
    String? email,
    String? name,
    String? avatar,
  }) async {
    final body = <String, dynamic>{
      "idToken": idToken,
      "role": role,
    };
    if (email != null && email.isNotEmpty) body["email"] = email;
    if (name != null && name.isNotEmpty) body["name"] = name;
    if (avatar != null && avatar.isNotEmpty) body["avatar"] = avatar;

    final response = await http.post(
      Uri.parse("$baseUrl/auth/google-login"),
      headers: {
        "Content-Type": "application/json",
        "Bypass-Tunnel-Reminder": "true",
      },
      body: jsonEncode(body),
    );

    return _handleResponse(response, isAuthEndpoint: true);
  }

  static Future<Map<String, dynamic>> toggleDriver(
    String driverId, {
    bool? isAvailable,
    Map<String, double>? location,
  }) async {
    final Map<String, dynamic> body = {};
    if (isAvailable != null) {
      body["isAvailable"] = isAvailable;
    }
    if (location != null) {
      body["location"] = {
        "lat": location["lat"],
        "lng": location["lng"],
      };
    }

    final response = await http.post(
      Uri.parse("$baseUrl/drivers/toggle/$driverId"),
      headers: _authHeaders(),
      body: body.isNotEmpty ? jsonEncode(body) : null,
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getDriverStatus(String driverId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/drivers/status/$driverId"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getDrivers() async {
    final uri = Uri.parse("$baseUrl/users/drivers-list");
    print("CALLING: $uri");

    final response = await http.post(
      uri,
      headers: _authHeaders(),
      body: jsonEncode({}),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getDashboard() async {
    final response = await http.get(
      Uri.parse("$baseUrl/rides/dashboard"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getUserProfile() async {
    final response = await http.get(
      Uri.parse("$baseUrl/users/profile"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> updateLocation(
    double lat,
    double lng,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/location"),
      headers: _authHeaders(),
      body: jsonEncode({"lat": lat, "lng": lng}),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> register(
    String name,
    String phone,
    String password, {
    String role = "user",
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/register"),
      headers: {
        "Content-Type": "application/json",
        "Bypass-Tunnel-Reminder": "true",
      },
      body: jsonEncode({
        "name": name,
        "phone": phone,
        "password": password,
        "role": role,
      }),
    );

    return _handleResponse(response, isAuthEndpoint: true);
  }

  static Future<List<Map<String, dynamic>>> searchPhotonPlaces(
    String input, {
    double? lat,
    double? lng,
  }) async {
    if (input.trim().isEmpty) {
      return [];
    }

    final double biasLat = lat ?? AppConfig.defaultLat;
    final double biasLng = lng ?? AppConfig.defaultLng;

    final uri = Uri.parse(
      "$photonBaseUrl?q=${Uri.encodeQueryComponent(input.trim())}&limit=8&lat=$biasLat&lon=$biasLng",
    );

    final response = await http.get(uri, headers: _locationHeaders());

    return _parsePhotonFeatures(_handleResponse(response));
  }

  static Future<Map<String, dynamic>?> reversePhotonPlace(
    double lat,
    double lng,
  ) async {
    final baseUri = Uri.parse(photonBaseUrl);
    final reversePath = baseUri.path.replaceFirst(
      RegExp(r'/api/?$'),
      '/reverse',
    );
    final uri = baseUri.replace(
      path: reversePath,
      queryParameters: {
        "lat": lat.toString(),
        "lon": lng.toString(),
        "limit": "1",
      },
    );

    final response = await http.get(uri, headers: _locationHeaders());

    final results = _parsePhotonFeatures(_handleResponse(response));
    return results.isEmpty ? null : results.first;
  }

  static List<double>? _findFirstPointInList(dynamic list) {
    if (list is! List || list.isEmpty) return null;
    if (list.length >= 2 && list[0] is num && list[1] is num) {
      final double lng = (list[0] as num).toDouble();
      final double lat = (list[1] as num).toDouble();
      return [lat, lng];
    }
    for (final item in list) {
      final res = _findFirstPointInList(item);
      if (res != null) return res;
    }
    return null;
  }

  static List<Map<String, dynamic>> _parsePhotonFeatures(dynamic data) {
    final features = data is Map<String, dynamic>
        ? List<dynamic>.from(data["features"] ?? const [])
        : <dynamic>[];

    return features
        .whereType<Map>()
        .map((item) {
          final feature = Map<String, dynamic>.from(item);
          final geometry = Map<String, dynamic>.from(
            feature["geometry"] as Map? ?? const {},
          );
          final properties = Map<String, dynamic>.from(
            feature["properties"] as Map? ?? const {},
          );
          final rawCoords = geometry["coordinates"];
          final latLng = _findFirstPointInList(rawCoords);
          final double? lat = latLng != null ? latLng[0] : null;
          final double? lng = latLng != null ? latLng[1] : null;
          final addressParts = <String>[
            properties["name"]?.toString() ?? "",
            properties["street"]?.toString() ?? "",
            properties["city"]?.toString() ?? "",
            properties["state"]?.toString() ?? "",
            properties["country"]?.toString() ?? "",
          ].where((part) => part.trim().isNotEmpty).toList();
          final address = addressParts.isNotEmpty
              ? addressParts.join(", ")
              : (properties["name"]?.toString() ??
                    properties["country"]?.toString() ??
                    "");

          return {
            "placeId":
                "${properties["osm_type"] ?? "feature"}-${properties["osm_id"] ?? feature["id"] ?? ""}",
            "address": address,
            "subtitle": [
              properties["postcode"]?.toString() ?? "",
              properties["district"]?.toString() ?? "",
            ].where((part) => part.trim().isNotEmpty).join(" • "),
            "lat": lat,
            "lng": lng,
          };
        })
        .where(
          (item) =>
              item["placeId"] != "feature-" &&
              (item["address"]?.toString().trim().isNotEmpty ?? false) &&
              item["lat"] != null &&
              item["lng"] != null,
        )
        .toList();
  }

  static Future<Map<String, dynamic>> requestRide(
    String userId,
    String pickupAddress,
    double pickupLat,
    double pickupLng,
    String dropAddress,
    double dropLat,
    double dropLng,
    String paymentMethod,
    String? pickupPlaceId,
    String? dropPlaceId,
    String bookingMode,
    double estimatedFare, {
    bool isDemoMode = false,
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/request"),
      headers: _authHeaders(),
      body: jsonEncode({
        "userId": userId,
        "pickup": pickupAddress,
        "pickupAddress": pickupAddress,
        "pickupLat": pickupLat,
        "pickupLng": pickupLng,
        "pickupPlaceId": pickupPlaceId,
        "destination": dropAddress,
        "dropAddress": dropAddress,
        "dropLat": dropLat,
        "dropLng": dropLng,
        "dropPlaceId": dropPlaceId,
        "paymentMethod": paymentMethod,
        "bookingMode": bookingMode,
        "estimatedFare": estimatedFare,
        "offeredFare": estimatedFare,
        "isDemoMode": isDemoMode,
      }),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getRideOffers(String rideId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/rides/$rideId/offers"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> submitRideOffer(
    String rideId,
    String driverId, {
    double? offeredFare,
    bool acceptBaseFare = false,
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/$rideId/offers"),
      headers: _authHeaders(),
      body: jsonEncode({
        "driverId": driverId,
        "offeredFare": offeredFare,
        "acceptBaseFare": acceptBaseFare,
      }),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> confirmRideOffer(
    String rideId,
    String offerId,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/$rideId/confirm-offer"),
      headers: _authHeaders(),
      body: jsonEncode({"offerId": offerId}),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getDriverNegotiationRides(
    String driverId,
  ) async {
    final response = await http.get(
      Uri.parse("$baseUrl/rides/driver/$driverId/negotiations"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getRide(String rideId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/rides/$rideId"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getDriverRequests(String driverId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/rides/driver/$driverId/requests"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> acceptRide(String rideId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/accept/$rideId"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> startRide(
    String rideId,
    String otp,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/start/$rideId"),
      headers: _authHeaders(),
      body: jsonEncode({"otp": otp}),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> completeRide(String rideId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/complete/$rideId"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> cancelRide(String rideId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/cancel/$rideId"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> payRide(String rideId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/pay/$rideId"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> negotiateFare(
    String rideId,
    double offeredFare,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/negotiate/$rideId"),
      headers: _authHeaders(),
      body: jsonEncode({"offeredFare": offeredFare}),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> acceptFare(String rideId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/accept-offer/$rideId"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> rejectFare(String rideId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/reject-offer/$rideId"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getUserRideHistory(String userId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/rides/user/$userId/history"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getActiveRide() async {
    final response = await http.get(
      Uri.parse("$baseUrl/rides/active/current"),
      headers: _authHeaders(),
    );

    return _handleResponse(response);
  }

  static Future<void> logout() async {
    try {
      if (token != null && token!.isNotEmpty) {
        await http.post(
          Uri.parse("$baseUrl/users/logout"),
          headers: _authHeaders(),
        );
      }
    } catch (e) {
      print("Logout API error: $e");
    } finally {
      token = null;
      SessionService.clearSession();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
      } catch (_) {}
      try {
        SocketService.disconnect();
      } catch (_) {}
    }
  }

  static void triggerAutoLogout({
    String message = "Logged out: Your account was signed in on another device",
  }) async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;

    token = null;
    SessionService.clearSession();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}

    try {
      SocketService.disconnect();
    } catch (_) {}

    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      context.go('/login');
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }

    Future.delayed(const Duration(seconds: 2), () {
      _isLoggingOut = false;
    });
  }

  static dynamic _handleResponse(
    http.Response response, {
    bool isAuthEndpoint = false,
  }) {
    print("STATUS CODE: ${response.statusCode}");
    print("RAW RESPONSE BODY: ${response.body}");

    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {}

    if (response.statusCode == 401) {
      if (isAuthEndpoint) {
        final errMessage = (data is Map && data["message"] != null)
            ? data["message"].toString()
            : "Invalid credentials";
        throw Exception(errMessage);
      }

      String message = "Logged out: Your account was signed in on another device";
      if (data is Map && data["message"] != null) {
        message = data["message"].toString();
      }
      triggerAutoLogout(message: message);
      throw Exception(message);
    }

    if (data == null) {
      throw Exception(
        "Invalid JSON response | Status: ${response.statusCode} | Body: ${response.body}",
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(
        data["message"] ?? "Server error | Status: ${response.statusCode}",
      );
    }
  }
}
