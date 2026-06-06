import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiService {
  static String get baseUrl => AppConfig.apiBaseUrl;
  static const String photonBaseUrl = AppConfig.photonBaseUrl;
  static String? token;

  static Map<String, String> _authHeaders() {
    final headers = <String, String>{
      "Content-Type": "application/json",
    };

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

  static Future<Map<String, dynamic>> login(
    String phone,
    String password, {
    String role = "user",
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "phone": phone,
        "password": password,
        "role": role,
      }),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> toggleDriver(String driverId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/drivers/toggle/$driverId"),
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

  static Future<Map<String, dynamic>> register(
    String name,
    String phone,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "name": name,
        "phone": phone,
        "password": password,
      }),
    );

    return _handleResponse(response);
  }

  static Future<List<Map<String, dynamic>>> searchPhotonPlaces(
    String input,
  ) async {
    if (input.trim().isEmpty) {
      return [];
    }

    final uri = Uri.parse(
      "${photonBaseUrl}?q=${Uri.encodeQueryComponent(input.trim())}&limit=5",
    );

    final response = await http.get(
      uri,
      headers: _locationHeaders(),
    );

    final data = _handleResponse(response);
    final features = data is Map<String, dynamic>
        ? List<dynamic>.from(data["features"] ?? const [])
        : <dynamic>[];

    return features
        .whereType<Map>()
        .map(
          (item) {
            final feature = Map<String, dynamic>.from(item);
            final geometry = Map<String, dynamic>.from(
              feature["geometry"] as Map? ?? const {},
            );
            final properties = Map<String, dynamic>.from(
              feature["properties"] as Map? ?? const {},
            );
            final coordinates = geometry["coordinates"] is List
                ? List<dynamic>.from(geometry["coordinates"] as List)
                : const <dynamic>[];
            final lng = coordinates.isNotEmpty
                ? (coordinates[0] as num?)?.toDouble()
                : null;
            final lat = coordinates.length > 1
                ? (coordinates[1] as num?)?.toDouble()
                : null;
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
          },
        )
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
    double estimatedFare,
  ) async {
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
      body: jsonEncode({
        "offerId": offerId,
      }),
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

  static Future<Map<String, dynamic>> startRide(String rideId, String otp) async {
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
      body: jsonEncode({
        "offeredFare": offeredFare,
      }),
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

  static dynamic _handleResponse(http.Response response) {
    print("STATUS CODE: ${response.statusCode}");
    print("RAW RESPONSE BODY: ${response.body}");

    dynamic data;

    try {
      data = jsonDecode(response.body);
    } catch (e) {
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
